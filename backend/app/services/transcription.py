"""
Transcription service using OpenAI Whisper for meeting transcription.
"""
import os
import tempfile
from typing import Optional, Dict, Any
from uuid import UUID
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.models.meeting import Meeting


class TranscriptionService:
    """
    Audio transcription using OpenAI Whisper.
    Supports GPU acceleration when available.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._model = None

    async def _get_model(self):
        """Load Whisper model (lazy loading)."""
        if self._model is None:
            import whisper

            # Use GPU if available
            model_size = settings.whisper_model_size or "base"
            self._model = whisper.load_model(model_size)

        return self._model

    async def transcribe_audio(
        self,
        audio_path: str,
        language: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Transcribe an audio file.

        Args:
            audio_path: Path to audio file
            language: Optional language code (auto-detected if not specified)

        Returns:
            Transcription result with text and segments
        """
        try:
            model = await self._get_model()

            options = {}
            if language:
                options["language"] = language

            result = model.transcribe(audio_path, **options)

            return {
                "success": True,
                "text": result["text"],
                "language": result.get("language"),
                "segments": [
                    {
                        "start": seg["start"],
                        "end": seg["end"],
                        "text": seg["text"],
                    }
                    for seg in result.get("segments", [])
                ],
            }

        except Exception as e:
            return {"success": False, "error": str(e)}

    async def transcribe_meeting(
        self,
        meeting_id: UUID,
        audio_path: str,
        delete_audio_after: bool = True,
    ) -> Dict[str, Any]:
        """
        Transcribe a meeting and save the result.

        Args:
            meeting_id: Meeting ID to associate transcription with
            audio_path: Path to meeting audio file
            delete_audio_after: Delete audio file after successful transcription (default: True)

        Returns:
            Transcription result
        """
        # Get meeting
        result = await self.db.execute(
            select(Meeting).where(
                Meeting.id == meeting_id,
                Meeting.user_id == self.user_id,
            )
        )
        meeting = result.scalar_one_or_none()

        if not meeting:
            return {"error": "Meeting not found", "success": False}

        try:
            # Transcribe audio
            transcription = await self.transcribe_audio(audio_path)

            if not transcription.get("success"):
                return transcription

            # Update meeting with transcription
            meeting.transcript = transcription["text"]
            await self.db.commit()

            # Generate summary automatically after transcription
            summary_result = await self.generate_meeting_summary(meeting_id)

            return {
                "success": True,
                "meeting_id": str(meeting_id),
                "transcription": transcription["text"],
                "segments": transcription.get("segments", []),
                "summary": summary_result.get("summary") if summary_result.get("success") else None,
            }
        finally:
            # Clean up audio file to save storage
            if delete_audio_after and os.path.exists(audio_path):
                try:
                    os.unlink(audio_path)
                except OSError:
                    pass  # Best effort deletion

    async def generate_meeting_summary(
        self,
        meeting_id: UUID,
    ) -> Dict[str, Any]:
        """
        Generate a summary from meeting transcription using Claude.

        Args:
            meeting_id: Meeting ID with transcription

        Returns:
            Meeting summary
        """
        import anthropic

        # Get meeting with transcription
        result = await self.db.execute(
            select(Meeting).where(
                Meeting.id == meeting_id,
                Meeting.user_id == self.user_id,
            )
        )
        meeting = result.scalar_one_or_none()

        if not meeting:
            return {"error": "Meeting not found", "success": False}

        if not meeting.transcript:
            return {"error": "No transcription available", "success": False}

        # Generate summary using Claude
        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        # Get attendees from existing summary if present
        existing_attendees = meeting.summary.get("attendees", []) if meeting.summary else []

        prompt = f"""Analyze this meeting transcription and provide:
1. A concise summary (2-3 paragraphs)
2. Key decisions made
3. Action items with owners if mentioned
4. Important topics discussed

Meeting: {meeting.event_title or 'Untitled Meeting'}
Date: {meeting.event_start.isoformat() if meeting.event_start else 'Unknown'}

Transcription:
{meeting.transcript}

Provide a structured summary:"""

        response = await client.messages.create(
            model="claude-haiku-4-5-20250929",
            max_tokens=2048,
            messages=[{"role": "user", "content": prompt}],
        )

        summary_text = response.content[0].text

        # Parse action items (simple extraction)
        action_items = []
        key_points = []

        lines = summary_text.split("\n")
        current_section = None

        for line in lines:
            line = line.strip()
            if "action item" in line.lower():
                current_section = "actions"
            elif "decision" in line.lower() or "key point" in line.lower():
                current_section = "points"
            elif line.startswith("-") or line.startswith("•"):
                item = line.lstrip("-•").strip()
                if current_section == "actions":
                    action_items.append(item)
                elif current_section == "points":
                    key_points.append(item)

        # Store summary in Meeting.summary JSONB field
        meeting.summary = {
            "discussion": summary_text,
            "key_points": key_points,
            "action_items": action_items,
            "attendees": existing_attendees,
        }

        await self.db.commit()

        return {
            "success": True,
            "meeting_id": str(meeting_id),
            "summary": summary_text,
            "action_items": action_items,
            "key_points": key_points,
        }

    async def transcribe_from_bytes(
        self,
        audio_data: bytes,
        filename: str = "audio.wav",
        language: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Transcribe audio from bytes (for uploaded files).

        Args:
            audio_data: Audio file bytes
            filename: Original filename for format detection
            language: Optional language code

        Returns:
            Transcription result
        """
        # Write to temp file
        suffix = Path(filename).suffix or ".wav"

        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
            f.write(audio_data)
            temp_path = f.name

        try:
            result = await self.transcribe_audio(temp_path, language)
            return result
        finally:
            # Clean up temp file
            if os.path.exists(temp_path):
                os.unlink(temp_path)

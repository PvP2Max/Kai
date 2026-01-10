"""
Email service for Gmail integration.
"""
import base64
from email.mime.text import MIMEText
from typing import Optional, List, Dict, Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings


class EmailService:
    """
    Gmail API integration for email operations.
    Requires OAuth2 credentials.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._service = None

    async def _get_service(self):
        """Get or create Gmail API service."""
        if self._service is None:
            from google.oauth2.credentials import Credentials
            from googleapiclient.discovery import build

            if not settings.google_client_id:
                raise ValueError("Gmail not configured")

            # Load credentials from database or file
            # This is a simplified version - in production, credentials
            # would be stored securely per user
            creds = Credentials(
                token=settings.google_access_token,
                refresh_token=settings.google_refresh_token,
                token_uri="https://oauth2.googleapis.com/token",
                client_id=settings.google_client_id,
                client_secret=settings.google_client_secret,
            )

            self._service = build("gmail", "v1", credentials=creds)

        return self._service

    async def get_inbox(
        self,
        max_results: int = 20,
        unread_only: bool = False,
        query: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Get recent emails from inbox.

        Args:
            max_results: Maximum number of emails to return
            unread_only: Only return unread emails
            query: Optional Gmail search query

        Returns:
            List of email summaries
        """
        try:
            service = await self._get_service()

            q = query or ""
            if unread_only:
                q += " is:unread"

            results = (
                service.users()
                .messages()
                .list(userId="me", maxResults=max_results, q=q.strip())
                .execute()
            )

            messages = results.get("messages", [])
            emails = []

            for msg in messages:
                email_data = (
                    service.users()
                    .messages()
                    .get(userId="me", id=msg["id"], format="metadata")
                    .execute()
                )

                headers = {
                    h["name"].lower(): h["value"]
                    for h in email_data.get("payload", {}).get("headers", [])
                }

                emails.append({
                    "id": msg["id"],
                    "thread_id": email_data.get("threadId"),
                    "subject": headers.get("subject", "(No subject)"),
                    "from": headers.get("from", "Unknown"),
                    "to": headers.get("to"),
                    "date": headers.get("date"),
                    "snippet": email_data.get("snippet", ""),
                    "labels": email_data.get("labelIds", []),
                    "unread": "UNREAD" in email_data.get("labelIds", []),
                })

            return {"emails": emails, "count": len(emails)}

        except Exception as e:
            return {"error": str(e), "emails": []}

    async def get_thread(self, thread_id: str) -> Dict[str, Any]:
        """
        Get full email thread.

        Args:
            thread_id: Gmail thread ID

        Returns:
            Thread with all messages
        """
        try:
            service = await self._get_service()

            thread = (
                service.users()
                .threads()
                .get(userId="me", id=thread_id, format="full")
                .execute()
            )

            messages = []
            for msg in thread.get("messages", []):
                headers = {
                    h["name"].lower(): h["value"]
                    for h in msg.get("payload", {}).get("headers", [])
                }

                # Extract body
                body = self._get_body(msg.get("payload", {}))

                messages.append({
                    "id": msg["id"],
                    "subject": headers.get("subject"),
                    "from": headers.get("from"),
                    "to": headers.get("to"),
                    "date": headers.get("date"),
                    "body": body,
                })

            return {
                "thread_id": thread_id,
                "messages": messages,
                "message_count": len(messages),
            }

        except Exception as e:
            return {"error": str(e)}

    async def create_draft(
        self,
        thread_id: Optional[str] = None,
        to: Optional[str] = None,
        subject: Optional[str] = None,
        content: str = "",
        tone: str = "friendly",
    ) -> Dict[str, Any]:
        """
        Create an email draft.

        Args:
            thread_id: Thread ID if replying
            to: Recipient email if new email
            subject: Subject if new email
            content: Email content
            tone: Tone for the email

        Returns:
            Created draft details
        """
        try:
            service = await self._get_service()

            if thread_id:
                # Get thread to find reply-to address
                thread = await self.get_thread(thread_id)
                if "error" in thread:
                    return thread

                last_message = thread["messages"][-1]
                to = last_message["from"]
                subject = f"Re: {last_message['subject']}"

            if not to:
                return {"error": "No recipient specified"}

            # Create message
            message = MIMEText(content)
            message["to"] = to
            message["subject"] = subject or "(No subject)"

            raw = base64.urlsafe_b64encode(message.as_bytes()).decode()

            draft_body = {"message": {"raw": raw}}
            if thread_id:
                draft_body["message"]["threadId"] = thread_id

            draft = (
                service.users()
                .drafts()
                .create(userId="me", body=draft_body)
                .execute()
            )

            return {
                "success": True,
                "draft_id": draft["id"],
                "to": to,
                "subject": subject,
            }

        except Exception as e:
            return {"error": str(e), "success": False}

    async def triage(self, max_emails: int = 50) -> Dict[str, Any]:
        """
        Analyze inbox and categorize emails.

        Args:
            max_emails: Maximum emails to analyze

        Returns:
            Categorized email list
        """
        try:
            import anthropic

            inbox = await self.get_inbox(max_results=max_emails, unread_only=True)

            if "error" in inbox:
                return inbox

            emails = inbox.get("emails", [])

            if not emails:
                return {
                    "categories": {},
                    "summary": "No unread emails to triage",
                }

            # Use Claude to categorize
            client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

            email_summaries = "\n".join([
                f"- From: {e['from']}, Subject: {e['subject']}, Snippet: {e['snippet'][:100]}"
                for e in emails[:20]  # Limit for context
            ])

            prompt = f"""Analyze these emails and categorize them:

{email_summaries}

Categories to use:
- urgent: Requires immediate attention
- action_needed: Needs response or action this week
- fyi: Informational, no action needed
- newsletter: Newsletters/marketing
- low_priority: Can wait

For each email, provide the category and a brief reason.
Format: EMAIL_INDEX|CATEGORY|REASON"""

            response = await client.messages.create(
                model="claude-haiku-4-5-20250929",
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )

            # Parse response
            categories = {
                "urgent": [],
                "action_needed": [],
                "fyi": [],
                "newsletter": [],
                "low_priority": [],
            }

            for line in response.content[0].text.split("\n"):
                if "|" in line:
                    parts = line.split("|")
                    if len(parts) >= 2:
                        try:
                            idx = int(parts[0].strip())
                            cat = parts[1].strip().lower()
                            if cat in categories and idx < len(emails):
                                categories[cat].append({
                                    "email": emails[idx],
                                    "reason": parts[2] if len(parts) > 2 else "",
                                })
                        except ValueError:
                            continue

            return {
                "categories": categories,
                "total_analyzed": len(emails),
                "summary": f"Triaged {len(emails)} emails",
            }

        except Exception as e:
            return {"error": str(e)}

    def _get_body(self, payload: Dict) -> str:
        """Extract email body from payload."""
        if "body" in payload and payload["body"].get("data"):
            return base64.urlsafe_b64decode(payload["body"]["data"]).decode()

        if "parts" in payload:
            for part in payload["parts"]:
                if part["mimeType"] == "text/plain":
                    if part.get("body", {}).get("data"):
                        return base64.urlsafe_b64decode(
                            part["body"]["data"]
                        ).decode()
                elif part["mimeType"] == "text/html":
                    if part.get("body", {}).get("data"):
                        # Return HTML as fallback
                        return base64.urlsafe_b64decode(
                            part["body"]["data"]
                        ).decode()

        return ""

    async def send_email(
        self,
        to: str,
        subject: str,
        body: str,
    ) -> Dict[str, Any]:
        """
        Send an email.

        Args:
            to: Recipient email
            subject: Email subject
            body: Email body

        Returns:
            Send result
        """
        try:
            service = await self._get_service()

            message = MIMEText(body)
            message["to"] = to
            message["subject"] = subject

            raw = base64.urlsafe_b64encode(message.as_bytes()).decode()

            sent = (
                service.users()
                .messages()
                .send(userId="me", body={"raw": raw})
                .execute()
            )

            return {
                "success": True,
                "message_id": sent["id"],
            }

        except Exception as e:
            return {"error": str(e), "success": False}

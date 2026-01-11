"""
Email service for multi-account email integration.
Supports Gmail, Outlook, and IMAP providers.
"""

import base64
from datetime import datetime
from email.mime.text import MIMEText
from typing import Optional, List, Dict, Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.email_account import EmailAccount, EmailBriefingConfig


class EmailService:
    """
    Multi-account email integration.
    Supports Gmail via OAuth and IMAP for other providers.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._gmail_services = {}  # Cache per account

    async def _get_active_accounts(
        self,
        for_briefing: bool = False
    ) -> List[EmailAccount]:
        """Get active email accounts, optionally filtered for today's briefing."""
        query = select(EmailAccount).where(
            EmailAccount.user_id == self.user_id,
            EmailAccount.is_active == True,
        )

        result = await self.db.execute(query)
        accounts = result.scalars().all()

        if for_briefing:
            # Get briefing config
            config_result = await self.db.execute(
                select(EmailBriefingConfig).where(
                    EmailBriefingConfig.user_id == self.user_id
                )
            )
            config = config_result.scalar_one_or_none()

            if config and not config.briefing_enabled:
                return []

            # Filter accounts based on briefing schedule
            if config:
                account_ids = config.get_accounts_for_today()
                if account_ids is not None:
                    accounts = [a for a in accounts if str(a.id) in account_ids]
            else:
                # No config, use account-level settings
                accounts = [a for a in accounts if a.should_include_today()]

        return list(accounts)

    async def _get_gmail_service(self, account: EmailAccount):
        """Get or create Gmail API service for an account."""
        account_id = str(account.id)

        if account_id not in self._gmail_services:
            from google.oauth2.credentials import Credentials
            from googleapiclient.discovery import build

            if not account.access_token:
                raise ValueError("Gmail account not properly configured")

            creds = Credentials(
                token=account.access_token,
                refresh_token=account.refresh_token,
                token_uri="https://oauth2.googleapis.com/token",
                client_id=settings.google_client_id,
                client_secret=settings.google_client_secret,
            )

            # Check if token needs refresh
            if account.is_token_expired() and account.refresh_token:
                try:
                    creds.refresh(None)
                    account.access_token = creds.token
                    account.token_expiry = creds.expiry
                    await self.db.commit()
                except Exception as e:
                    account.sync_error = f"Token refresh failed: {str(e)}"
                    await self.db.commit()
                    raise

            self._gmail_services[account_id] = build("gmail", "v1", credentials=creds)

        return self._gmail_services[account_id]

    async def get_inbox(
        self,
        max_results: int = 20,
        unread_only: bool = False,
        query: Optional[str] = None,
        account_id: Optional[UUID] = None,
    ) -> Dict[str, Any]:
        """
        Get recent emails from inbox.

        Args:
            max_results: Maximum number of emails to return
            unread_only: Only return unread emails
            query: Optional search query
            account_id: Specific account to query, or None for all active accounts

        Returns:
            List of email summaries
        """
        try:
            if account_id:
                result = await self.db.execute(
                    select(EmailAccount).where(
                        EmailAccount.id == account_id,
                        EmailAccount.user_id == self.user_id,
                    )
                )
                account = result.scalar_one_or_none()
                accounts = [account] if account else []
            else:
                accounts = await self._get_active_accounts()

            all_emails = []

            for account in accounts:
                try:
                    if account.provider == "gmail":
                        emails = await self._get_gmail_inbox(
                            account, max_results, unread_only, query
                        )
                        for email in emails:
                            email["account_id"] = str(account.id)
                            email["account_name"] = account.display_name
                        all_emails.extend(emails)
                    # Future: Add Outlook, IMAP support
                except Exception as e:
                    # Log error but continue with other accounts
                    account.sync_error = str(e)
                    await self.db.commit()

            # Sort by date (newest first)
            all_emails.sort(key=lambda x: x.get("date", ""), reverse=True)

            return {"emails": all_emails[:max_results], "count": len(all_emails)}

        except Exception as e:
            return {"error": str(e), "emails": []}

    async def _get_gmail_inbox(
        self,
        account: EmailAccount,
        max_results: int,
        unread_only: bool,
        query: Optional[str],
    ) -> List[Dict[str, Any]]:
        """Get inbox from Gmail account."""
        service = await self._get_gmail_service(account)

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

        return emails

    async def get_thread(
        self,
        thread_id: str,
        account_id: Optional[UUID] = None
    ) -> Dict[str, Any]:
        """
        Get full email thread.

        Args:
            thread_id: Email thread ID
            account_id: Specific account (required for multi-account)

        Returns:
            Thread with all messages
        """
        try:
            # Find the account that has this thread
            if account_id:
                result = await self.db.execute(
                    select(EmailAccount).where(
                        EmailAccount.id == account_id,
                        EmailAccount.user_id == self.user_id,
                    )
                )
                account = result.scalar_one_or_none()
            else:
                # Try each account until we find the thread
                accounts = await self._get_active_accounts()
                account = accounts[0] if accounts else None

            if not account:
                return {"error": "No email account found"}

            if account.provider == "gmail":
                return await self._get_gmail_thread(account, thread_id)

            return {"error": f"Unsupported provider: {account.provider}"}

        except Exception as e:
            return {"error": str(e)}

    async def _get_gmail_thread(
        self,
        account: EmailAccount,
        thread_id: str
    ) -> Dict[str, Any]:
        """Get thread from Gmail account."""
        service = await self._get_gmail_service(account)

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
            "account_id": str(account.id),
            "account_name": account.display_name,
            "messages": messages,
            "message_count": len(messages),
        }

    async def create_draft(
        self,
        thread_id: Optional[str] = None,
        to: Optional[str] = None,
        subject: Optional[str] = None,
        content: str = "",
        tone: str = "friendly",
        account_id: Optional[UUID] = None,
    ) -> Dict[str, Any]:
        """
        Create an email draft.

        Args:
            thread_id: Thread ID if replying
            to: Recipient email if new email
            subject: Subject if new email
            content: Email content
            tone: Tone for the email
            account_id: Which account to draft from

        Returns:
            Created draft details
        """
        try:
            if account_id:
                result = await self.db.execute(
                    select(EmailAccount).where(
                        EmailAccount.id == account_id,
                        EmailAccount.user_id == self.user_id,
                    )
                )
                account = result.scalar_one_or_none()
            else:
                accounts = await self._get_active_accounts()
                account = accounts[0] if accounts else None

            if not account:
                return {"error": "No email account found"}

            if account.provider == "gmail":
                return await self._create_gmail_draft(
                    account, thread_id, to, subject, content
                )

            return {"error": f"Unsupported provider: {account.provider}"}

        except Exception as e:
            return {"error": str(e), "success": False}

    async def _create_gmail_draft(
        self,
        account: EmailAccount,
        thread_id: Optional[str],
        to: Optional[str],
        subject: Optional[str],
        content: str,
    ) -> Dict[str, Any]:
        """Create draft in Gmail account."""
        service = await self._get_gmail_service(account)

        if thread_id:
            thread = await self._get_gmail_thread(account, thread_id)
            if "error" in thread:
                return thread

            last_message = thread["messages"][-1]
            to = last_message["from"]
            subject = f"Re: {last_message['subject']}"

        if not to:
            return {"error": "No recipient specified"}

        message = MIMEText(content)
        message["to"] = to
        message["subject"] = subject or "(No subject)"
        message["from"] = account.email_address

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
            "account_id": str(account.id),
            "account_name": account.display_name,
            "to": to,
            "subject": subject,
        }

    async def get_briefing_emails(self) -> Dict[str, Any]:
        """
        Get emails for daily briefing based on schedule configuration.

        Returns:
            Categorized emails from accounts scheduled for today
        """
        try:
            accounts = await self._get_active_accounts(for_briefing=True)

            if not accounts:
                return {
                    "accounts": [],
                    "total_emails": 0,
                    "note": "No email accounts configured for today's briefing",
                }

            all_emails = []
            account_summaries = []

            for account in accounts:
                try:
                    max_emails = account.max_emails_in_briefing or 10

                    if account.provider == "gmail":
                        emails = await self._get_gmail_inbox(
                            account,
                            max_results=max_emails,
                            unread_only=True,
                            query=None,
                        )

                        # Filter by categories if specified
                        if account.categories_to_include and "all" not in account.categories_to_include:
                            # Would need triage to work, for now include all
                            pass

                        for email in emails:
                            email["account_id"] = str(account.id)
                            email["account_name"] = account.display_name

                        all_emails.extend(emails)
                        account_summaries.append({
                            "account_id": str(account.id),
                            "account_name": account.display_name,
                            "email_count": len(emails),
                        })

                except Exception as e:
                    account_summaries.append({
                        "account_id": str(account.id),
                        "account_name": account.display_name,
                        "error": str(e),
                    })

            return {
                "accounts": account_summaries,
                "emails": all_emails,
                "total_emails": len(all_emails),
            }

        except Exception as e:
            return {"error": str(e)}

    async def triage(
        self,
        max_emails: int = 50,
        account_id: Optional[UUID] = None,
    ) -> Dict[str, Any]:
        """
        Analyze inbox and categorize emails.

        Args:
            max_emails: Maximum emails to analyze
            account_id: Specific account or all active accounts

        Returns:
            Categorized email list
        """
        try:
            import anthropic

            inbox = await self.get_inbox(
                max_results=max_emails,
                unread_only=True,
                account_id=account_id,
            )

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
                f"- [{e.get('account_name', 'Unknown')}] From: {e['from']}, Subject: {e['subject']}, Snippet: {e['snippet'][:100]}"
                for e in emails[:20]
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
                model="claude-3-5-haiku-20241022",
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )

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
                        return base64.urlsafe_b64decode(
                            part["body"]["data"]
                        ).decode()

        return ""

    async def send_email(
        self,
        to: str,
        subject: str,
        body: str,
        account_id: Optional[UUID] = None,
    ) -> Dict[str, Any]:
        """
        Send an email.

        Args:
            to: Recipient email
            subject: Email subject
            body: Email body
            account_id: Which account to send from

        Returns:
            Send result
        """
        try:
            if account_id:
                result = await self.db.execute(
                    select(EmailAccount).where(
                        EmailAccount.id == account_id,
                        EmailAccount.user_id == self.user_id,
                    )
                )
                account = result.scalar_one_or_none()
            else:
                accounts = await self._get_active_accounts()
                account = accounts[0] if accounts else None

            if not account:
                return {"error": "No email account found"}

            if account.provider == "gmail":
                service = await self._get_gmail_service(account)

                message = MIMEText(body)
                message["to"] = to
                message["subject"] = subject
                message["from"] = account.email_address

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
                    "account_id": str(account.id),
                }

            return {"error": f"Unsupported provider: {account.provider}"}

        except Exception as e:
            return {"error": str(e), "success": False}

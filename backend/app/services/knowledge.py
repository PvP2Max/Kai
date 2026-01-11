"""
Knowledge service for storing and retrieving user knowledge.

This service manages categorical knowledge about the user to enable
personalized responses without bloating the context window.
"""

import re
from datetime import datetime
from typing import List, Dict, Optional, Any
from uuid import UUID

from sqlalchemy import select, or_, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user_knowledge import UserKnowledge


# Knowledge categories and their related keywords for matching
CATEGORY_KEYWORDS = {
    "personal": [
        "name", "birthday", "age", "timezone", "location", "city", "address",
        "phone", "pronouns", "nickname"
    ],
    "relationships": [
        "wife", "husband", "spouse", "partner", "kid", "kids", "child", "children",
        "son", "daughter", "mom", "dad", "mother", "father", "parent", "parents",
        "brother", "sister", "sibling", "friend", "boss", "manager", "coworker",
        "colleague", "team", "employee", "assistant"
    ],
    "work": [
        "job", "work", "company", "employer", "title", "role", "position",
        "project", "client", "customer", "meeting", "schedule", "office",
        "remote", "hybrid", "salary", "career"
    ],
    "preferences": [
        "prefer", "like", "favorite", "hate", "dislike", "love", "want",
        "always", "never", "morning", "evening", "night", "afternoon",
        "style", "tone", "format"
    ],
    "facts": [
        "allergy", "allergic", "diet", "vegetarian", "vegan", "gym", "exercise",
        "hobby", "hobbies", "routine", "habit", "anniversary", "important",
        "remember", "date", "event"
    ],
}

# Common relationship terms to extract names
RELATIONSHIP_PATTERNS = [
    r"(?:my\s+)?(?:wife|husband|spouse|partner)(?:'s|\s+is)?\s+(\w+)",
    r"(?:my\s+)?(?:boss|manager)(?:'s|\s+is)?\s+(\w+)",
    r"(?:my\s+)?(?:friend)(?:'s|\s+is)?\s+(\w+)",
    r"(\w+)\s+is\s+my\s+(?:wife|husband|spouse|partner|boss|manager|friend)",
]


class KnowledgeService:
    """Service for managing and retrieving user knowledge."""

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id

    async def get_all_knowledge(
        self,
        category: Optional[str] = None,
        limit: int = 100
    ) -> List[UserKnowledge]:
        """Get all knowledge for a user, optionally filtered by category."""
        query = select(UserKnowledge).where(
            UserKnowledge.user_id == self.user_id
        )

        if category:
            query = query.where(UserKnowledge.category == category)

        query = query.order_by(
            UserKnowledge.confidence.desc(),
            UserKnowledge.use_count.desc()
        ).limit(limit)

        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_relevant_knowledge(
        self,
        query_text: str,
        max_results: int = 10,
        min_confidence: float = 0.3
    ) -> List[UserKnowledge]:
        """
        Retrieve knowledge relevant to the given query.

        Uses keyword extraction and category inference to find
        only the knowledge that's relevant, keeping context small.
        """
        # Extract keywords from query
        keywords = self._extract_keywords(query_text)

        # Infer relevant categories based on keywords
        categories = self._infer_categories(keywords)

        # Build query conditions
        conditions = [UserKnowledge.user_id == self.user_id]

        if categories:
            conditions.append(UserKnowledge.category.in_(categories))

        conditions.append(UserKnowledge.confidence >= min_confidence)

        # Build keyword matching conditions
        keyword_conditions = []
        for keyword in keywords:
            keyword_lower = keyword.lower()
            keyword_conditions.append(
                func.lower(UserKnowledge.topic).contains(keyword_lower)
            )
            keyword_conditions.append(
                func.lower(UserKnowledge.value).contains(keyword_lower)
            )

        query = select(UserKnowledge).where(
            and_(*conditions)
        )

        # If we have keyword matches, prioritize them but also include category matches
        if keyword_conditions:
            # Get both keyword matches and high-confidence category matches
            query = query.where(
                or_(
                    or_(*keyword_conditions),
                    UserKnowledge.confidence >= 0.8
                )
            )

        query = query.order_by(
            UserKnowledge.confidence.desc(),
            UserKnowledge.use_count.desc()
        ).limit(max_results)

        result = await self.db.execute(query)
        knowledge_items = list(result.scalars().all())

        # Update usage stats for retrieved items
        for item in knowledge_items:
            item.last_used = datetime.utcnow()
            item.use_count += 1

        await self.db.commit()

        return knowledge_items

    async def learn(
        self,
        category: str,
        topic: str,
        value: str,
        confidence: float = 0.7,
        source: str = "conversation",
        context: Optional[str] = None
    ) -> UserKnowledge:
        """
        Store or update knowledge about the user.

        If knowledge with the same category/topic exists:
        - Updates if new confidence >= existing confidence
        - Keeps existing if new confidence < existing confidence
        """
        # Check for existing knowledge
        existing = await self.db.execute(
            select(UserKnowledge).where(
                and_(
                    UserKnowledge.user_id == self.user_id,
                    UserKnowledge.category == category,
                    UserKnowledge.topic == topic
                )
            )
        )
        existing_knowledge = existing.scalar_one_or_none()

        if existing_knowledge:
            # Only update if new confidence is higher or equal
            if confidence >= existing_knowledge.confidence:
                existing_knowledge.value = value
                existing_knowledge.confidence = confidence
                existing_knowledge.source = source
                existing_knowledge.context = context
                existing_knowledge.updated_at = datetime.utcnow()
                await self.db.commit()
                await self.db.refresh(existing_knowledge)
                return existing_knowledge
            return existing_knowledge

        # Create new knowledge
        knowledge = UserKnowledge(
            user_id=self.user_id,
            category=category,
            topic=topic,
            value=value,
            confidence=confidence,
            source=source,
            context=context
        )
        self.db.add(knowledge)
        await self.db.commit()
        await self.db.refresh(knowledge)
        return knowledge

    async def forget(self, knowledge_id: UUID) -> bool:
        """Remove a piece of knowledge."""
        result = await self.db.execute(
            select(UserKnowledge).where(
                and_(
                    UserKnowledge.id == knowledge_id,
                    UserKnowledge.user_id == self.user_id
                )
            )
        )
        knowledge = result.scalar_one_or_none()

        if knowledge:
            await self.db.delete(knowledge)
            await self.db.commit()
            return True
        return False

    async def get_knowledge_summary(self) -> Dict[str, Any]:
        """Get a summary of all stored knowledge by category."""
        result = await self.db.execute(
            select(
                UserKnowledge.category,
                func.count(UserKnowledge.id).label("count"),
                func.avg(UserKnowledge.confidence).label("avg_confidence")
            ).where(
                UserKnowledge.user_id == self.user_id
            ).group_by(UserKnowledge.category)
        )

        categories = {}
        for row in result:
            categories[row.category] = {
                "count": row.count,
                "avg_confidence": round(row.avg_confidence, 2)
            }

        return {
            "total_items": sum(c["count"] for c in categories.values()),
            "categories": categories
        }

    async def extract_and_learn_from_message(
        self,
        message: str
    ) -> List[UserKnowledge]:
        """
        Analyze a user message and extract learnable facts.

        This is called by the chat handler to passively learn
        from user statements.
        """
        learned = []

        # Extract relationship names
        for pattern in RELATIONSHIP_PATTERNS:
            matches = re.findall(pattern, message, re.IGNORECASE)
            for match in matches:
                # Determine relationship type from the pattern
                if "wife" in pattern or "husband" in pattern or "spouse" in pattern or "partner" in pattern:
                    topic = "spouse_name"
                elif "boss" in pattern or "manager" in pattern:
                    topic = "boss_name"
                elif "friend" in pattern:
                    topic = "friend_name"
                else:
                    continue

                if match and len(match) > 1:  # Ensure we have a real name
                    knowledge = await self.learn(
                        category="relationships",
                        topic=topic,
                        value=match.capitalize(),
                        confidence=0.8,
                        source="inferred",
                        context=f"Extracted from: '{message[:100]}...'"
                    )
                    learned.append(knowledge)

        # Extract explicit preferences
        preference_patterns = [
            (r"i (?:always |usually )?prefer (\w+(?:\s+\w+)*)", "general_preference"),
            (r"i (?:really )?(?:like|love) (\w+(?:\s+\w+)*)", "likes"),
            (r"i (?:really )?(?:hate|dislike|don't like) (\w+(?:\s+\w+)*)", "dislikes"),
            (r"my favorite (\w+) is (\w+(?:\s+\w+)*)", "favorite"),
        ]

        for pattern, topic_prefix in preference_patterns:
            matches = re.findall(pattern, message, re.IGNORECASE)
            for match in matches:
                if isinstance(match, tuple):
                    topic = f"favorite_{match[0]}"
                    value = match[1]
                else:
                    topic = topic_prefix
                    value = match

                if value and len(value) > 1:
                    knowledge = await self.learn(
                        category="preferences",
                        topic=topic,
                        value=value,
                        confidence=0.9,
                        source="explicit",
                        context=f"User stated: '{message[:100]}...'"
                    )
                    learned.append(knowledge)

        return learned

    def _extract_keywords(self, text: str) -> List[str]:
        """Extract meaningful keywords from text."""
        # Remove common stop words
        stop_words = {
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "dare",
            "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by",
            "from", "as", "into", "through", "during", "before", "after",
            "above", "below", "between", "under", "again", "further", "then",
            "once", "here", "there", "when", "where", "why", "how", "all",
            "each", "few", "more", "most", "other", "some", "such", "no", "nor",
            "not", "only", "own", "same", "so", "than", "too", "very", "just",
            "and", "but", "if", "or", "because", "until", "while", "this",
            "that", "these", "those", "what", "which", "who", "whom", "i", "me",
            "my", "myself", "we", "our", "ours", "you", "your", "yours", "he",
            "him", "his", "she", "her", "hers", "it", "its", "they", "them",
            "their", "theirs", "about", "please", "tell", "know", "get", "make"
        }

        # Extract words
        words = re.findall(r'\b\w+\b', text.lower())

        # Filter stop words and short words
        keywords = [w for w in words if w not in stop_words and len(w) > 2]

        return keywords

    def _infer_categories(self, keywords: List[str]) -> List[str]:
        """Infer relevant knowledge categories from keywords."""
        categories = set()

        for category, category_keywords in CATEGORY_KEYWORDS.items():
            for keyword in keywords:
                if keyword in category_keywords:
                    categories.add(category)
                    break

                # Check for partial matches
                for cat_kw in category_keywords:
                    if keyword in cat_kw or cat_kw in keyword:
                        categories.add(category)
                        break

        # If no specific categories found, include high-priority ones
        if not categories:
            categories = {"personal", "relationships", "preferences"}

        return list(categories)

    def format_knowledge_for_context(
        self,
        knowledge_items: List[UserKnowledge]
    ) -> str:
        """Format knowledge items for injection into system prompt."""
        if not knowledge_items:
            return ""

        # Group by category
        by_category: Dict[str, List[UserKnowledge]] = {}
        for item in knowledge_items:
            if item.category not in by_category:
                by_category[item.category] = []
            by_category[item.category].append(item)

        lines = ["## Known Information About User"]

        for category, items in by_category.items():
            lines.append(f"\n### {category.title()}")
            for item in items:
                confidence_indicator = "✓" if item.confidence >= 0.8 else "~"
                lines.append(f"- {item.topic}: {item.value} {confidence_indicator}")

        return "\n".join(lines)

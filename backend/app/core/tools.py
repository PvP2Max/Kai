"""
Claude tools definitions for Kai.
"""

TOOLS = [
    # Calendar Tools
    {
        "name": "get_calendar_events",
        "description": "Retrieve calendar events for a date range",
        "input_schema": {
            "type": "object",
            "properties": {
                "start_date": {"type": "string", "description": "ISO format start date"},
                "end_date": {"type": "string", "description": "ISO format end date"}
            },
            "required": ["start_date", "end_date"]
        }
    },
    {
        "name": "create_calendar_event",
        "description": "Create a new calendar event",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start": {"type": "string", "description": "ISO datetime"},
                "end": {"type": "string", "description": "ISO datetime"},
                "location": {"type": "string"},
                "description": {"type": "string"},
                "attendees": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["title", "start", "end"]
        }
    },
    {
        "name": "update_calendar_event",
        "description": "Update an existing calendar event",
        "input_schema": {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"},
                "updates": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "start": {"type": "string"},
                        "end": {"type": "string"},
                        "location": {"type": "string"},
                        "description": {"type": "string"}
                    }
                }
            },
            "required": ["event_id", "updates"]
        }
    },
    {
        "name": "delete_calendar_event",
        "description": "Delete a calendar event",
        "input_schema": {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"}
            },
            "required": ["event_id"]
        }
    },
    {
        "name": "propose_schedule_optimization",
        "description": "Analyze schedule and propose optimizations. Always use this before making changes - never modify calendar directly without approval.",
        "input_schema": {
            "type": "object",
            "properties": {
                "date_range_start": {"type": "string"},
                "date_range_end": {"type": "string"},
                "optimization_goal": {"type": "string", "description": "What to optimize for: 'efficiency', 'focus_time', 'balance'"}
            },
            "required": ["date_range_start", "date_range_end"]
        }
    },

    # Reminder Tools
    {
        "name": "get_reminders",
        "description": "Get reminders from Apple Reminders",
        "input_schema": {
            "type": "object",
            "properties": {
                "list_name": {"type": "string"},
                "include_completed": {"type": "boolean", "default": False}
            }
        }
    },
    {
        "name": "create_reminder",
        "description": "Create a reminder in Apple Reminders",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "due_date": {"type": "string", "description": "ISO datetime, optional"},
                "priority": {"type": "string", "enum": ["low", "medium", "high"]},
                "list_name": {"type": "string"},
                "notes": {"type": "string"}
            },
            "required": ["title"]
        }
    },
    {
        "name": "complete_reminder",
        "description": "Mark a reminder as complete",
        "input_schema": {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string"}
            },
            "required": ["reminder_id"]
        }
    },

    # Note Tools
    {
        "name": "search_notes",
        "description": "Search through Kamron's notes",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "project_id": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["query"]
        }
    },
    {
        "name": "create_note",
        "description": "Create a new note",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "project_id": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["content"]
        }
    },
    {
        "name": "get_note",
        "description": "Retrieve a specific note by ID",
        "input_schema": {
            "type": "object",
            "properties": {
                "note_id": {"type": "string"}
            },
            "required": ["note_id"]
        }
    },

    # Email Tools
    {
        "name": "get_email_inbox",
        "description": "Get recent emails from Gmail inbox",
        "input_schema": {
            "type": "object",
            "properties": {
                "max_results": {"type": "integer", "default": 20},
                "unread_only": {"type": "boolean", "default": False}
            }
        }
    },
    {
        "name": "get_email_thread",
        "description": "Get full email thread",
        "input_schema": {
            "type": "object",
            "properties": {
                "thread_id": {"type": "string"}
            },
            "required": ["thread_id"]
        }
    },
    {
        "name": "draft_email_reply",
        "description": "Draft a reply to an email thread. Never send directly - only draft for Kamron's review.",
        "input_schema": {
            "type": "object",
            "properties": {
                "thread_id": {"type": "string"},
                "reply_content": {"type": "string"},
                "tone": {"type": "string", "enum": ["formal", "casual", "friendly"]}
            },
            "required": ["thread_id", "reply_content"]
        }
    },
    {
        "name": "triage_emails",
        "description": "Analyze inbox and categorize emails by priority and action needed",
        "input_schema": {
            "type": "object",
            "properties": {
                "max_emails": {"type": "integer", "default": 50}
            }
        }
    },

    # Meeting Tools
    {
        "name": "get_meeting_summary",
        "description": "Get the summary of a past meeting",
        "input_schema": {
            "type": "object",
            "properties": {
                "meeting_id": {"type": "string"},
                "calendar_event_id": {"type": "string"}
            }
        }
    },
    {
        "name": "get_meeting_prep",
        "description": "Prepare briefing for an upcoming meeting - includes relevant notes, past interactions with attendees, and context",
        "input_schema": {
            "type": "object",
            "properties": {
                "calendar_event_id": {"type": "string"}
            },
            "required": ["calendar_event_id"]
        }
    },

    # Project Tools
    {
        "name": "get_project_status",
        "description": "Get comprehensive status of a project including related meetings, notes, tasks",
        "input_schema": {
            "type": "object",
            "properties": {
                "project_id": {"type": "string"},
                "project_name": {"type": "string"}
            }
        }
    },
    {
        "name": "create_project",
        "description": "Create a new project to group related items",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "description": {"type": "string"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "link_to_project",
        "description": "Link a note, meeting, or task to a project",
        "input_schema": {
            "type": "object",
            "properties": {
                "project_id": {"type": "string"},
                "item_type": {"type": "string", "enum": ["note", "meeting", "action_item"]},
                "item_id": {"type": "string"}
            },
            "required": ["project_id", "item_type", "item_id"]
        }
    },

    # Follow-up Tools
    {
        "name": "get_pending_follow_ups",
        "description": "Get list of things Kamron is waiting on from others",
        "input_schema": {
            "type": "object",
            "properties": {
                "overdue_only": {"type": "boolean", "default": False}
            }
        }
    },
    {
        "name": "create_follow_up",
        "description": "Track that Kamron is waiting on something from someone",
        "input_schema": {
            "type": "object",
            "properties": {
                "contact_name": {"type": "string"},
                "contact_email": {"type": "string"},
                "context": {"type": "string"},
                "follow_up_date": {"type": "string", "description": "When to remind if no response"}
            },
            "required": ["contact_name", "context"]
        }
    },
    {
        "name": "draft_follow_up_nudge",
        "description": "Draft a polite follow-up email for something Kamron is waiting on",
        "input_schema": {
            "type": "object",
            "properties": {
                "follow_up_id": {"type": "string"}
            },
            "required": ["follow_up_id"]
        }
    },

    # Read Later Tools
    {
        "name": "save_for_later",
        "description": "Save a URL to read later",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "title": {"type": "string"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "get_read_later_list",
        "description": "Get the read-later queue",
        "input_schema": {
            "type": "object",
            "properties": {
                "unread_only": {"type": "boolean", "default": True}
            }
        }
    },

    # Location & Travel Tools
    {
        "name": "get_travel_time",
        "description": "Get travel time between two locations with current traffic",
        "input_schema": {
            "type": "object",
            "properties": {
                "origin": {"type": "string", "description": "Address or saved location name like 'home'"},
                "destination": {"type": "string"},
                "departure_time": {"type": "string", "description": "ISO datetime, defaults to now"}
            },
            "required": ["origin", "destination"]
        }
    },
    {
        "name": "get_weather",
        "description": "Get weather forecast",
        "input_schema": {
            "type": "object",
            "properties": {
                "location": {"type": "string", "description": "City or saved location name"},
                "days": {"type": "integer", "default": 1}
            }
        }
    },

    # Preference & Memory Tools
    {
        "name": "get_user_preferences",
        "description": "Get Kamron's preferences for a category",
        "input_schema": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "enum": ["scheduling", "communication", "general", "all"]}
            },
            "required": ["category"]
        }
    },
    {
        "name": "update_user_preference",
        "description": "Update or learn a preference",
        "input_schema": {
            "type": "object",
            "properties": {
                "category": {"type": "string"},
                "key": {"type": "string"},
                "value": {"type": "object"},
                "learned": {"type": "boolean", "description": "True if inferred from behavior, false if explicitly stated"}
            },
            "required": ["category", "key", "value"]
        }
    },

    # Knowledge & Learning Tools
    {
        "name": "get_relevant_knowledge",
        "description": "Retrieve relevant knowledge about the user based on the current context. Use this to personalize responses with known facts about the user.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "The current context or query to find relevant knowledge for"},
                "categories": {
                    "type": "array",
                    "items": {"type": "string", "enum": ["personal", "relationships", "work", "preferences", "facts"]},
                    "description": "Optional: specific categories to search"
                },
                "max_results": {"type": "integer", "default": 10}
            },
            "required": ["query"]
        }
    },
    {
        "name": "learn_about_user",
        "description": "Store important information about the user for future reference. Use this when the user shares personal facts, preferences, relationships, or other information worth remembering.",
        "input_schema": {
            "type": "object",
            "properties": {
                "category": {
                    "type": "string",
                    "enum": ["personal", "relationships", "work", "preferences", "facts"],
                    "description": "Category of knowledge"
                },
                "topic": {
                    "type": "string",
                    "description": "Specific topic (e.g., 'spouse_name', 'job_title', 'preferred_meeting_time')"
                },
                "value": {
                    "type": "string",
                    "description": "The actual information to remember"
                },
                "confidence": {
                    "type": "number",
                    "description": "How confident (0.5 for inferred, 0.8 for stated, 1.0 for explicit confirmation)",
                    "default": 0.8
                }
            },
            "required": ["category", "topic", "value"]
        }
    },
    {
        "name": "get_knowledge_summary",
        "description": "Get a summary of all stored knowledge about the user, grouped by category",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "forget_knowledge",
        "description": "Remove a piece of stored knowledge when asked by the user",
        "input_schema": {
            "type": "object",
            "properties": {
                "knowledge_id": {"type": "string", "description": "ID of the knowledge item to forget"}
            },
            "required": ["knowledge_id"]
        }
    },

    # Notification Tools
    {
        "name": "send_push_notification",
        "description": "Send a push notification to Kamron's devices",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string"},
                "category": {"type": "string", "enum": ["reminder", "briefing", "alert", "info"]},
                "action_url": {"type": "string", "description": "Deep link for when notification is tapped"}
            },
            "required": ["title", "body"]
        }
    },

    # Briefing Tools
    {
        "name": "generate_daily_briefing",
        "description": "Generate the daily briefing with calendar, weather, priorities",
        "input_schema": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "description": "ISO date, defaults to today"}
            }
        }
    },
    {
        "name": "generate_weekly_review",
        "description": "Generate weekly review with accomplishments, patterns, suggestions",
        "input_schema": {
            "type": "object",
            "properties": {
                "week_start": {"type": "string", "description": "ISO date of week start"}
            }
        }
    },

    # Meta Tools
    {
        "name": "undo_last_action",
        "description": "Undo the most recent reversible action",
        "input_schema": {
            "type": "object",
            "properties": {
                "action_id": {"type": "string", "description": "Specific action ID to undo, or omit for most recent"}
            }
        }
    },
    {
        "name": "explain_reasoning",
        "description": "Explain why Kai made a particular suggestion or decision",
        "input_schema": {
            "type": "object",
            "properties": {
                "context": {"type": "string", "description": "What decision or suggestion to explain"}
            },
            "required": ["context"]
        }
    },
    {
        "name": "log_activity",
        "description": "Log an action to the activity log",
        "input_schema": {
            "type": "object",
            "properties": {
                "action_type": {"type": "string"},
                "action_data": {"type": "object"},
                "reversible": {"type": "boolean"}
            },
            "required": ["action_type", "action_data"]
        }
    }
]

# Kai — Kamron's Adaptive Intelligence

## Claude Code Build Prompt

You are building **Kai**, a personal AI assistant for Kamron. Kai manages scheduling, meeting intelligence, tasks, notes, email triage, and more. It learns from Kamron's patterns over time and is accessible via Siri voice commands, a web interface, and push notifications.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENTS                                      │
├─────────────────┬─────────────────┬─────────────────────────────────┤
│   Siri Shortcut │    Web App      │     Push Notifications          │
│   (Voice I/O)   │  (Chat + UI)    │     (iOS APNs)                  │
└────────┬────────┴────────┬────────┴─────────────┬───────────────────┘
         │                 │                      │
         └────────────────┼──────────────────────┘
                          │
                ┌─────────▼─────────┐
                │  Cloudflare Tunnel │
                └─────────┬─────────┘
                          │
         ┌────────────────▼────────────────┐
         │         Kai Server (FastAPI)     │
         │                                  │
         │  ┌─────────────────────────────┐ │
         │  │      Core Intelligence      │ │
         │  │      (Claude API + Tools)   │ │
         │  └─────────────────────────────┘ │
         │                                  │
         │  ┌──────────┐ ┌──────────────┐  │
         │  │ Whisper  │ │ Tool Modules │  │
         │  │ (Local)  │ │              │  │
         │  └──────────┘ └──────────────┘  │
         └───────────────┬─────────────────┘
                         │
    ┌────────────────────┼────────────────────┐
    │                    │                    │
┌───▼───┐  ┌─────────────▼──────────────┐  ┌──▼──────────────┐
│Postgres│  │     External APIs          │  │  Apple Services │
│  DB    │  │ - Gmail API                │  │  - CalDAV       │
│        │  │ - Google Maps (traffic)    │  │  - Reminders    │
│        │  │ - Open-Meteo (weather)     │  │  - APNs         │
└────────┘  └────────────────────────────┘  └─────────────────┘
```

---

## Tech Stack

### Backend

- **Python 3.11+**
- **FastAPI** — REST API server
- **SQLAlchemy** — ORM for Postgres
- **Anthropic SDK** — Claude API integration
- **openai-whisper** — Local transcription (large-v3 model)
- **caldav** — Apple Calendar integration
- **google-api-python-client** — Gmail API
- **httpx** — Async HTTP client
- **APNs2** — Apple Push Notifications
- **python-jose** — JWT for auth
- **passlib[bcrypt]** — Password hashing
- **pydantic** — Data validation

### Frontend

- **React 18** with TypeScript
- **Vite** — Build tool
- **TailwindCSS** — Styling
- **React Query** — Data fetching
- **React Router** — Navigation

### Infrastructure

- **PostgreSQL 17** — Primary database
- **Cloudflare Tunnel** — Secure exposure
- **Local GPU (3080 Ti)** — Whisper transcription

---

## Database Schema

```sql
-- Users table (single user, but extensible)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Conversations (chat history)
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    title VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL, -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,
    tool_calls JSONB, -- Store any tool calls made
    created_at TIMESTAMP DEFAULT NOW()
);

-- Activity log (everything Kai does)
CREATE TABLE activity_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action_type VARCHAR(100) NOT NULL, -- 'calendar_create', 'reminder_create', 'email_draft', etc.
    action_data JSONB NOT NULL, -- Full details of the action
    source VARCHAR(50), -- 'siri', 'web', 'proactive'
    reversible BOOLEAN DEFAULT false,
    reversed BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Notes
CREATE TABLE notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    title VARCHAR(255),
    content TEXT NOT NULL,
    source VARCHAR(50), -- 'meeting', 'quick_capture', 'manual'
    meeting_event_id VARCHAR(255), -- Apple Calendar event ID if linked
    project_id UUID REFERENCES projects(id),
    tags TEXT[], -- Array of tags
    embedding VECTOR(1536), -- For semantic search (optional, add pgvector)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Meeting transcripts and summaries
CREATE TABLE meetings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    calendar_event_id VARCHAR(255), -- Apple Calendar event ID
    event_title VARCHAR(255),
    event_start TIMESTAMP,
    event_end TIMESTAMP,
    audio_file_path VARCHAR(500),
    transcript TEXT,
    summary JSONB, -- Structured: {discussion, key_points, action_items, attendees}
    project_id UUID REFERENCES projects(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Action items extracted from meetings
CREATE TABLE action_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID REFERENCES meetings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    description TEXT NOT NULL,
    owner VARCHAR(255), -- Who is responsible
    due_date TIMESTAMP,
    priority VARCHAR(20) DEFAULT 'medium', -- 'low', 'medium', 'high'
    reminder_id VARCHAR(255), -- Apple Reminder ID if created
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'completed', 'cancelled'
    created_at TIMESTAMP DEFAULT NOW()
);

-- Projects (group related items)
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'completed', 'archived'
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Read-it-later queue
CREATE TABLE read_later (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    url TEXT NOT NULL,
    title VARCHAR(500),
    summary TEXT, -- AI-generated summary
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Follow-up tracking
CREATE TABLE follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    contact_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    context TEXT, -- What we're waiting on
    last_contact_date TIMESTAMP,
    follow_up_date TIMESTAMP, -- When to nudge
    status VARCHAR(20) DEFAULT 'waiting', -- 'waiting', 'responded', 'closed'
    created_at TIMESTAMP DEFAULT NOW()
);

-- User preferences and learned patterns
CREATE TABLE preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    category VARCHAR(100) NOT NULL, -- 'scheduling', 'communication', 'general'
    key VARCHAR(255) NOT NULL,
    value JSONB NOT NULL,
    learned BOOLEAN DEFAULT false, -- true if inferred, false if explicit
    confidence FLOAT DEFAULT 1.0, -- How confident in learned preference
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, category, key)
);

-- Common locations
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    name VARCHAR(100) NOT NULL, -- 'home', 'office', 'gym'
    address TEXT NOT NULL,
    latitude FLOAT,
    longitude FLOAT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Push notification device tokens
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    token TEXT NOT NULL,
    device_name VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- Scheduled proactive tasks
CREATE TABLE scheduled_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    task_type VARCHAR(100) NOT NULL, -- 'daily_briefing', 'weekly_review', 'break_reminder', 'follow_up_check'
    schedule JSONB NOT NULL, -- Cron-like schedule or interval
    last_run TIMESTAMP,
    next_run TIMESTAMP,
    enabled BOOLEAN DEFAULT true,
    config JSONB, -- Task-specific configuration
    created_at TIMESTAMP DEFAULT NOW()
);

-- Model usage tracking (for cost analysis and optimization)
CREATE TABLE model_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    conversation_id UUID REFERENCES conversations(id),
    model_tier VARCHAR(20) NOT NULL, -- 'haiku', 'sonnet', 'opus'
    model_version VARCHAR(50) NOT NULL, -- Full model string
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    task_type VARCHAR(100), -- What kind of task triggered this
    routing_reason VARCHAR(255), -- Why this model was selected
    latency_ms INTEGER, -- Response time
    created_at TIMESTAMP DEFAULT NOW()
);

-- Model routing settings (user configurable)
CREATE TABLE routing_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) UNIQUE,
    task_routing JSONB DEFAULT '{}', -- Task type -> model overrides
    tool_routing JSONB DEFAULT '{}', -- Tool name -> model overrides
    custom_patterns JSONB DEFAULT '{"haiku": [], "opus": []}', -- Custom regex patterns
    default_model VARCHAR(20) DEFAULT 'sonnet',
    enable_chaining BOOLEAN DEFAULT true, -- Allow multi-model chains
    chain_configs JSONB DEFAULT '{}', -- Custom chain configurations
    cost_limit_daily DECIMAL(10,4), -- Daily spending cap (null = unlimited)
    prefer_speed BOOLEAN DEFAULT false, -- Bias toward faster models
    prefer_quality BOOLEAN DEFAULT false, -- Bias toward better models
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Index for usage analytics
CREATE INDEX idx_model_usage_user_date ON model_usage(user_id, created_at);
CREATE INDEX idx_model_usage_tier ON model_usage(model_tier, created_at);
```

---

## API Endpoints

### Authentication

```
POST   /api/auth/register          # Initial setup (one-time)
POST   /api/auth/login             # Returns JWT
POST   /api/auth/refresh           # Refresh token
GET    /api/auth/me                # Current user info
```

### Chat / Core Intelligence

```
POST   /api/chat                   # Main chat endpoint (Siri + Web)
       Body: { message: string, conversation_id?: string, source: 'siri' | 'web' }
       Returns: { response: string, conversation_id: string, actions_taken: Action[] }

GET    /api/conversations          # List conversations
GET    /api/conversations/:id      # Get conversation with messages
DELETE /api/conversations/:id      # Delete conversation
```

### Activity Log

```
GET    /api/activity               # List activity (paginated)
       Query: ?limit=50&offset=0&type=calendar_create
POST   /api/activity/:id/undo      # Undo an action
```

### Calendar

```
GET    /api/calendar/events        # List events
       Query: ?start=ISO&end=ISO
POST   /api/calendar/events        # Create event
PUT    /api/calendar/events/:id    # Update event
DELETE /api/calendar/events/:id    # Delete event
POST   /api/calendar/optimize      # Get optimization suggestions
       Body: { date_range: {start, end}, protected_event_ids: string[] }
       Returns: { suggestions: ScheduleChange[], reasoning: string }
POST   /api/calendar/optimize/apply # Apply approved changes
       Body: { approved_changes: ScheduleChange[] }
```

### Meetings

```
GET    /api/meetings               # List meetings with summaries
POST   /api/meetings/upload        # Upload audio for transcription
       Body: FormData with audio file + calendar_event_id
GET    /api/meetings/:id           # Get meeting details + summary
POST   /api/meetings/:id/reprocess # Re-generate summary
```

### Notes

```
GET    /api/notes                  # List notes (with search)
       Query: ?search=text&project_id=uuid&tag=string
POST   /api/notes                  # Create note
GET    /api/notes/:id              # Get note
PUT    /api/notes/:id              # Update note
DELETE /api/notes/:id              # Delete note
```

### Reminders

```
GET    /api/reminders              # List reminders from Apple
POST   /api/reminders              # Create reminder
PUT    /api/reminders/:id          # Update reminder
DELETE /api/reminders/:id          # Delete reminder
POST   /api/reminders/sync         # Sync with Apple Reminders
```

### Email

```
GET    /api/email/inbox            # Get inbox summary
GET    /api/email/triage           # Get AI-triaged priority list
POST   /api/email/draft            # Create draft reply
       Body: { thread_id: string, instruction: string }
GET    /api/email/drafts           # List pending drafts
```

### Projects

```
GET    /api/projects               # List projects
POST   /api/projects               # Create project
GET    /api/projects/:id           # Get project with all related items
PUT    /api/projects/:id           # Update project
GET    /api/projects/:id/status    # Get AI-generated status summary
```

### Read Later

```
GET    /api/read-later             # List queue
POST   /api/read-later             # Add URL
PUT    /api/read-later/:id         # Mark as read
DELETE /api/read-later/:id         # Remove
```

### Follow-ups

```
GET    /api/follow-ups             # List pending follow-ups
POST   /api/follow-ups             # Create follow-up tracker
PUT    /api/follow-ups/:id         # Update status
POST   /api/follow-ups/:id/nudge   # Draft nudge email
```

### Preferences & Settings

```
GET    /api/preferences            # Get all preferences
PUT    /api/preferences            # Update preferences
GET    /api/locations              # Get saved locations
POST   /api/locations              # Add location
DELETE /api/locations/:id          # Remove location
```

### Notifications

```
POST   /api/devices/register       # Register device for push
DELETE /api/devices/:token         # Unregister device
GET    /api/notifications          # Get notification history
```

### Briefings

```
GET    /api/briefing/daily         # Get today's briefing
GET    /api/briefing/weekly        # Get weekly review
POST   /api/briefing/daily/send    # Trigger daily briefing push
```

### Model Usage & Analytics

```
GET    /api/usage/summary          # Get usage summary (tokens, costs by model)
       Query: ?period=day|week|month
       Returns: { by_model: {...}, by_task: {...}, totals: {...} }

GET    /api/usage/history          # Detailed usage history
       Query: ?limit=100&offset=0&model_tier=opus
       Returns: { items: [...], total: int }

GET    /api/usage/cost             # Estimated cost breakdown
       Query: ?period=day|week|month
       Returns: { current_period: float, projected_month: float, by_day: [...] }

GET    /api/usage/daily-costs      # Daily cost data for charts
       Query: ?days=30
       Returns: [{ date, haiku, sonnet, opus, total }, ...]

GET    /api/usage/task-breakdown   # Usage by task type
       Query: ?period=week
       Returns: { tasks: [{ task_type, requests, cost, avg_latency }] }
```

### Model Routing Settings

```
GET    /api/routing/settings       # Get current routing configuration
       Returns: {
         task_routing: { task_type: model_tier },
         tool_routing: { tool_name: model_tier },
         custom_patterns: { haiku: [...], opus: [...] },
         default_model: string,
         enable_chaining: boolean,
         chain_configs: {...},
         cost_limit_daily: float | null,
         prefer_speed: boolean,
         prefer_quality: boolean
       }

PUT    /api/routing/settings       # Update routing configuration
       Body: { ...partial settings to update }

GET    /api/routing/defaults       # Get default routing rules (for reference/reset)
       Returns: { task_routing: {...}, tool_routing: {...}, patterns: {...}, chains: {...} }

POST   /api/routing/reset          # Reset to defaults
       Body: { sections: ['task_routing', 'tool_routing', 'patterns', 'chains'] }

GET    /api/routing/chains         # Get available chain configurations
       Returns: { default_chains: {...}, custom_chains: {...} }

POST   /api/routing/chains         # Create custom chain
       Body: { name, description, steps: [{ model, purpose, prompt_template }] }

PUT    /api/routing/chains/:name   # Update custom chain
DELETE /api/routing/chains/:name   # Delete custom chain

POST   /api/routing/test           # Test routing for a message (doesn't execute)
       Body: { message: string, task_type?: string }
       Returns: {
         selected_model: string,
         would_chain: boolean,
         chain_name?: string,
         reasoning: string
       }
```

---

## Claude Tools Definition

Define these tools for Claude to use when processing requests:

```python
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
```

---

## Core Modules Implementation

### 1. Chat Handler (`app/core/chat.py`)

```python
"""
Main chat handler that processes messages and orchestrates tool usage.
"""

class ChatHandler:
    def __init__(self, db: Session, user_id: str):
        self.db = db
        self.user_id = user_id
        self.client = Anthropic()
        self.tool_executor = ToolExecutor(db, user_id)

    async def process_message(
        self,
        message: str,
        conversation_id: Optional[str] = None,
        source: str = "web"
    ) -> ChatResponse:
        # 1. Get or create conversation
        conversation = self._get_or_create_conversation(conversation_id)

        # 2. Build message history
        history = self._build_history(conversation.id)

        # 3. Build system prompt with user context
        system_prompt = self._build_system_prompt()

        # 4. Call Claude with tools
        response = await self._call_claude(system_prompt, history, message)

        # 5. Execute any tool calls
        actions_taken = []
        while response.stop_reason == "tool_use":
            tool_results = await self._execute_tools(response.content)
            actions_taken.extend(tool_results)
            response = await self._continue_with_results(response, tool_results)

        # 6. Save messages to DB
        self._save_messages(conversation.id, message, response)

        # 7. Return response
        return ChatResponse(
            response=self._extract_text(response),
            conversation_id=conversation.id,
            actions_taken=actions_taken
        )

    def _build_system_prompt(self) -> str:
        preferences = self._get_user_preferences()
        return f"""You are Kai (Kamron's Adaptive Intelligence), a personal AI assistant.

## Your Personality
- Warm, efficient, and proactive
- Confirm major actions verbally, execute minor ones silently
- Always log what you do
- Learn from Kamron's patterns and preferences

## Current User Context
Name: Kamron
Preferences: {json.dumps(preferences)}
Current time: {datetime.now().isoformat()}

## Behavioral Guidelines

### For Scheduling
- Never modify calendar directly without proposing changes first
- Respect protected time blocks
- Consider travel time between locations
- Learn preferred meeting times and durations

### For Meeting Summaries
- Structure: Discussion points, key decisions, action items (with owners), follow-ups
- Ask before creating reminders from action items
- Detect delegation ("Kamron will handle X")

### For Tasks/Reminders
- Infer due dates when context suggests them
- Infer priority (can be adjusted)
- Ask confirmation before creating

### For Email
- Never send emails directly - only draft
- Categorize by urgency and action needed
- Track follow-ups automatically

### Action Confirmation Rules
- ALWAYS confirm: calendar changes, sending communications, deleting anything
- Silently execute: searches, lookups, generating briefings, saving notes
- Log everything to activity log

### Learning
- Note patterns in scheduling preferences
- Remember communication style preferences
- Track commonly referenced projects and people
"""
```

### 2. Transcription Service (`app/services/transcription.py`)

```python
"""
Local Whisper transcription service.
"""
import whisper
import torch

class TranscriptionService:
    def __init__(self):
        # Load large-v3 model - fits easily in 12GB VRAM
        self.model = whisper.load_model("large-v3", device="cuda")

    async def transcribe(self, audio_path: str) -> TranscriptionResult:
        result = self.model.transcribe(
            audio_path,
            language="en",
            task="transcribe",
            verbose=False
        )

        return TranscriptionResult(
            text=result["text"],
            segments=result["segments"],
            language=result["language"]
        )

    async def transcribe_and_summarize(
        self,
        audio_path: str,
        event_context: Optional[dict] = None
    ) -> MeetingSummary:
        # 1. Transcribe
        transcription = await self.transcribe(audio_path)

        # 2. Use Claude to generate structured summary
        summary = await self._generate_summary(transcription.text, event_context)

        return summary

    async def _generate_summary(
        self,
        transcript: str,
        event_context: Optional[dict]
    ) -> MeetingSummary:
        client = Anthropic()

        context_str = ""
        if event_context:
            context_str = f"""
Meeting context:
- Title: {event_context.get('title', 'Unknown')}
- Attendees: {', '.join(event_context.get('attendees', []))}
- Date: {event_context.get('date', 'Unknown')}
"""

        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            messages=[{
                "role": "user",
                "content": f"""Analyze this meeting transcript and provide a structured summary.

{context_str}

Transcript:
{transcript}

Provide a JSON response with:
{{
    "discussion_summary": "Brief overview of what was discussed",
    "key_points": ["Important point 1", "Important point 2"],
    "decisions_made": ["Decision 1", "Decision 2"],
    "action_items": [
        {{
            "description": "What needs to be done",
            "owner": "Person responsible (use 'Kamron' if assigned to user)",
            "due_date": "Inferred date or null",
            "priority": "low/medium/high"
        }}
    ],
    "follow_ups": [
        {{
            "contact": "Person name",
            "topic": "What to follow up on",
            "suggested_date": "When to follow up"
        }}
    ],
    "delegation_detected": [
        {{
            "task": "Task delegated to Kamron",
            "by": "Who delegated it",
            "context": "Context from transcript"
        }}
    ]
}}"""
            }]
        )

        return MeetingSummary.parse_raw(response.content[0].text)
```

### 3. Calendar Service (`app/services/calendar.py`)

```python
"""
Apple Calendar integration via CalDAV.
"""
import caldav
from caldav.elements import dav, cdav

class CalendarService:
    def __init__(self, caldav_url: str, username: str, password: str):
        self.client = caldav.DAVClient(
            url=caldav_url,
            username=username,
            password=password
        )
        self.principal = self.client.principal()
        self.calendars = self.principal.calendars()

    def get_events(
        self,
        start: datetime,
        end: datetime,
        calendar_name: Optional[str] = None
    ) -> List[CalendarEvent]:
        events = []
        calendars = self.calendars

        if calendar_name:
            calendars = [c for c in calendars if c.name == calendar_name]

        for calendar in calendars:
            results = calendar.date_search(start=start, end=end)
            for event in results:
                events.append(self._parse_event(event))

        return sorted(events, key=lambda e: e.start)

    def create_event(self, event: CreateEventRequest) -> CalendarEvent:
        calendar = self._get_calendar(event.calendar_name)

        vcal = f"""BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:{event.title}
DTSTART:{event.start.strftime('%Y%m%dT%H%M%S')}
DTEND:{event.end.strftime('%Y%m%dT%H%M%S')}
LOCATION:{event.location or ''}
DESCRIPTION:{event.description or ''}
END:VEVENT
END:VCALENDAR"""

        created = calendar.save_event(vcal)
        return self._parse_event(created)

    def update_event(self, event_id: str, updates: dict) -> CalendarEvent:
        event = self._find_event(event_id)
        vobj = event.vobject_instance.vevent

        if 'title' in updates:
            vobj.summary.value = updates['title']
        if 'start' in updates:
            vobj.dtstart.value = updates['start']
        if 'end' in updates:
            vobj.dtend.value = updates['end']
        if 'location' in updates:
            vobj.location.value = updates['location']

        event.save()
        return self._parse_event(event)

    def delete_event(self, event_id: str) -> bool:
        event = self._find_event(event_id)
        event.delete()
        return True

    def get_protected_events(self) -> List[str]:
        """Get IDs of events marked as protected/immovable."""
        # Implementation: check for specific category or tag
        pass
```

### 4. Schedule Optimizer (`app/services/optimizer.py`)

```python
"""
Schedule optimization engine.
"""

class ScheduleOptimizer:
    def __init__(
        self,
        calendar_service: CalendarService,
        location_service: LocationService,
        preferences: dict
    ):
        self.calendar = calendar_service
        self.locations = location_service
        self.preferences = preferences

    async def propose_optimization(
        self,
        start: datetime,
        end: datetime,
        protected_ids: List[str],
        goal: str = "efficiency"
    ) -> OptimizationProposal:
        # 1. Get all events in range
        events = self.calendar.get_events(start, end)

        # 2. Identify movable vs protected
        protected = set(protected_ids)
        movable = [e for e in events if e.id not in protected]
        fixed = [e for e in events if e.id in protected]

        # 3. Get preferences
        preferred_hours = self.preferences.get('preferred_meeting_hours', (9, 17))
        focus_blocks = self.preferences.get('focus_time_blocks', [])
        buffer_minutes = self.preferences.get('meeting_buffer_minutes', 15)

        # 4. Calculate travel times between events with locations
        travel_requirements = await self._calculate_travel_times(events)

        # 5. Generate optimized schedule
        proposed_changes = self._optimize(
            movable=movable,
            fixed=fixed,
            travel=travel_requirements,
            preferred_hours=preferred_hours,
            focus_blocks=focus_blocks,
            buffer=buffer_minutes,
            goal=goal
        )

        # 6. Generate explanation
        reasoning = self._explain_changes(proposed_changes)

        return OptimizationProposal(
            changes=proposed_changes,
            reasoning=reasoning,
            affected_events=[c.event_id for c in proposed_changes]
        )

    def _optimize(self, **kwargs) -> List[ScheduleChange]:
        """
        Core optimization algorithm.
        Considers:
        - Protected time blocks
        - Travel time between locations
        - Preferred meeting hours
        - Focus time preservation
        - Buffer between meetings
        """
        # Implementation: constraint satisfaction / greedy algorithm
        pass
```

### 5. Learning Service (`app/services/learning.py`)

```python
"""
Pattern learning and preference adaptation.
"""

class LearningService:
    def __init__(self, db: Session, user_id: str):
        self.db = db
        self.user_id = user_id

    async def learn_from_interaction(
        self,
        interaction_type: str,
        context: dict,
        user_choice: Any
    ):
        """
        Learn from user's choices and behaviors.
        """
        if interaction_type == "scheduling":
            await self._learn_scheduling_preference(context, user_choice)
        elif interaction_type == "reminder_priority":
            await self._learn_priority_preference(context, user_choice)
        elif interaction_type == "communication_style":
            await self._learn_communication_preference(context, user_choice)

    async def _learn_scheduling_preference(self, context: dict, choice: dict):
        # Track patterns like:
        # - Preferred times for different meeting types
        # - How often user accepts optimization suggestions
        # - Typical meeting durations

        # Example: user always schedules 1:1s in afternoon
        if 'meeting_type' in context:
            meeting_type = context['meeting_type']
            chosen_time = choice.get('start_time')

            if chosen_time:
                hour = datetime.fromisoformat(chosen_time).hour
                await self._update_preference(
                    category="scheduling",
                    key=f"preferred_hour_{meeting_type}",
                    value={"hour": hour},
                    learned=True,
                    confidence=0.6  # Start with moderate confidence
                )

    async def get_preference_with_confidence(
        self,
        category: str,
        key: str
    ) -> Tuple[Any, float]:
        pref = self.db.query(Preference).filter(
            Preference.user_id == self.user_id,
            Preference.category == category,
            Preference.key == key
        ).first()

        if pref:
            return pref.value, pref.confidence
        return None, 0.0

    async def _update_preference(
        self,
        category: str,
        key: str,
        value: dict,
        learned: bool,
        confidence: float
    ):
        existing = self.db.query(Preference).filter(
            Preference.user_id == self.user_id,
            Preference.category == category,
            Preference.key == key
        ).first()

        if existing:
            # Increase confidence if same value, decrease if different
            if existing.value == value:
                existing.confidence = min(1.0, existing.confidence + 0.1)
            else:
                existing.confidence = max(0.0, existing.confidence - 0.1)
                if existing.confidence < 0.3:
                    existing.value = value
                    existing.confidence = 0.5
            existing.updated_at = datetime.utcnow()
        else:
            new_pref = Preference(
                user_id=self.user_id,
                category=category,
                key=key,
                value=value,
                learned=learned,
                confidence=confidence
            )
            self.db.add(new_pref)

        self.db.commit()
```

### 6. Model Router (`app/core/model_router.py`)

```python
"""
Intelligent model selection based on task complexity and type.
Supports configurable routing rules, multi-model chains, and usage analytics.

Model Tiers:
- Haiku: Fast, cheap — simple lookups, confirmations, basic parsing
- Sonnet: Balanced — most tasks, tool use, summaries, drafting
- Opus: Maximum capability — complex reasoning, optimization, learning, nuanced decisions
"""

from enum import Enum
from typing import Optional, List, Dict, Any
from dataclasses import dataclass
from datetime import datetime, timedelta
import re
import json


class ModelTier(Enum):
    HAIKU = "claude-haiku-4-5-20250929"
    SONNET = "claude-sonnet-4-20250514"
    OPUS = "claude-opus-4-20250514"


@dataclass
class ModelStep:
    """A single step in a multi-model chain."""
    tier: ModelTier
    purpose: str  # 'classify', 'execute', 'synthesize', 'validate'
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: int = 0


@dataclass
class ChainResult:
    """Result of a multi-model chain execution."""
    steps: List[ModelStep]
    final_response: str
    total_cost: float
    total_latency_ms: int


# Default task-to-model mappings (user can override)
DEFAULT_TASK_ROUTING = {
    # Task type -> model tier
    "greeting": "haiku",
    "simple_lookup": "haiku",
    "confirmation": "haiku",
    "basic_crud": "haiku",
    "status_check": "haiku",
    "calendar_query": "haiku",
    "reminder_query": "haiku",

    "calendar_create": "sonnet",
    "reminder_create": "sonnet",
    "note_create": "sonnet",
    "email_draft": "sonnet",
    "standard_tool_use": "sonnet",
    "daily_briefing": "sonnet",
    "travel_time": "sonnet",

    "schedule_optimization": "opus",
    "weekly_review": "opus",
    "meeting_summary": "opus",
    "complex_analysis": "opus",
    "decision_support": "opus",
    "pattern_learning": "opus",
    "conflict_resolution": "opus",
    "email_triage": "opus",
    "project_status": "opus",
    "explain_reasoning": "opus",
}

# Default tool-to-model mappings (user can override)
DEFAULT_TOOL_ROUTING = {
    # Tool name -> model tier
    "get_calendar_events": "haiku",
    "get_reminders": "haiku",
    "get_note": "haiku",
    "search_notes": "haiku",
    "get_read_later_list": "haiku",
    "get_weather": "haiku",
    "complete_reminder": "haiku",
    "get_travel_time": "haiku",

    "create_calendar_event": "sonnet",
    "update_calendar_event": "sonnet",
    "create_reminder": "sonnet",
    "create_note": "sonnet",
    "draft_email_reply": "sonnet",
    "save_for_later": "sonnet",
    "create_follow_up": "sonnet",
    "send_push_notification": "sonnet",

    "propose_schedule_optimization": "opus",
    "generate_weekly_review": "opus",
    "generate_daily_briefing": "sonnet",  # Can be upgraded
    "explain_reasoning": "opus",
    "triage_emails": "opus",
    "get_project_status": "opus",
    "get_meeting_prep": "opus",
    "get_meeting_summary": "opus",
}

# Default pattern matching (user can add/remove)
DEFAULT_PATTERNS = {
    "haiku": [
        r"what time",
        r"what'?s on my calendar",
        r"do i have any (meetings|events|reminders)",
        r"read (back|me) (the|my)",
        r"list my",
        r"show me",
        r"how many",
        r"is there a",
        r"when is",
        r"where is",
        r"confirm",
        r"yes|no|ok|okay|sure|thanks|thank you",
        r"cancel that",
        r"never\s?mind",
        r"^(hi|hey|hello|good morning|good afternoon)$",
    ],
    "opus": [
        r"optimi[zs]e my (schedule|calendar|day|week)",
        r"reorgani[zs]e",
        r"what should i prioriti[zs]e",
        r"help me (decide|think through|figure out)",
        r"analy[zs]e",
        r"why did you",
        r"explain your reasoning",
        r"what patterns",
        r"review my (week|month|progress)",
        r"suggest.*(strategy|approach|plan)",
        r"complex|complicated|nuanced",
        r"trade.?offs?",
        r"compare.*(options|approaches)",
        r"what do you think",
        r"advice",
    ],
}


class RoutingConfig:
    """
    User-configurable routing settings.
    Loaded from database, cached in memory.
    """

    def __init__(self, db_session, user_id: str):
        self.db = db_session
        self.user_id = user_id
        self._cache = None
        self._cache_time = None
        self._cache_ttl = timedelta(minutes=5)

    def get_config(self) -> dict:
        """Get current routing configuration."""
        if self._cache and self._cache_time and datetime.utcnow() - self._cache_time < self._cache_ttl:
            return self._cache

        # Load from database
        config = self.db.query(RoutingSettings).filter(
            RoutingSettings.user_id == self.user_id
        ).first()

        if config:
            self._cache = {
                "task_routing": {**DEFAULT_TASK_ROUTING, **config.task_routing},
                "tool_routing": {**DEFAULT_TOOL_ROUTING, **config.tool_routing},
                "patterns": {
                    "haiku": DEFAULT_PATTERNS["haiku"] + config.custom_patterns.get("haiku", []),
                    "opus": DEFAULT_PATTERNS["opus"] + config.custom_patterns.get("opus", []),
                },
                "default_model": config.default_model or "sonnet",
                "enable_chaining": config.enable_chaining,
                "chain_configs": config.chain_configs or {},
                "cost_limit_daily": config.cost_limit_daily,
                "prefer_speed": config.prefer_speed,
                "prefer_quality": config.prefer_quality,
            }
        else:
            # Return defaults
            self._cache = {
                "task_routing": DEFAULT_TASK_ROUTING,
                "tool_routing": DEFAULT_TOOL_ROUTING,
                "patterns": DEFAULT_PATTERNS,
                "default_model": "sonnet",
                "enable_chaining": True,
                "chain_configs": {},
                "cost_limit_daily": None,
                "prefer_speed": False,
                "prefer_quality": False,
            }

        self._cache_time = datetime.utcnow()
        return self._cache

    def update_config(self, updates: dict) -> dict:
        """Update routing configuration."""
        config = self.db.query(RoutingSettings).filter(
            RoutingSettings.user_id == self.user_id
        ).first()

        if not config:
            config = RoutingSettings(user_id=self.user_id)
            self.db.add(config)

        for key, value in updates.items():
            if hasattr(config, key):
                setattr(config, key, value)

        config.updated_at = datetime.utcnow()
        self.db.commit()

        # Invalidate cache
        self._cache = None
        return self.get_config()

    def invalidate_cache(self):
        self._cache = None


class ModelRouter:
    """
    Intelligent model selection with configurable rules.
    """

    def __init__(self, config: RoutingConfig):
        self.config = config
        self._compiled_patterns = {}

    def _get_patterns(self) -> dict:
        """Get compiled regex patterns."""
        cfg = self.config.get_config()
        cache_key = str(cfg["patterns"])

        if cache_key not in self._compiled_patterns:
            self._compiled_patterns[cache_key] = {
                "haiku": [re.compile(p, re.IGNORECASE) for p in cfg["patterns"]["haiku"]],
                "opus": [re.compile(p, re.IGNORECASE) for p in cfg["patterns"]["opus"]],
            }

        return self._compiled_patterns[cache_key]

    def select_model(
        self,
        message: str,
        conversation_history: list = None,
        pending_tools: list = None,
        task_type: Optional[str] = None,
        force_tier: Optional[ModelTier] = None
    ) -> ModelTier:
        """
        Select the appropriate model based on multiple signals.
        """
        cfg = self.config.get_config()

        # 1. Honor forced tier
        if force_tier:
            return force_tier

        # 2. Check speed/quality preferences
        if cfg["prefer_speed"]:
            # Bias toward faster models
            return self._select_with_speed_bias(message, task_type, pending_tools)
        if cfg["prefer_quality"]:
            # Bias toward better models
            return self._select_with_quality_bias(message, task_type, pending_tools)

        # 3. Task type routing
        if task_type and task_type in cfg["task_routing"]:
            return ModelTier[cfg["task_routing"][task_type].upper()]

        # 4. Tool-based routing
        if pending_tools:
            tool_tier = self._route_by_tools(pending_tools, cfg)
            if tool_tier:
                return tool_tier

        # 5. Pattern matching
        patterns = self._get_patterns()
        message_lower = message.lower().strip()

        for pattern in patterns["opus"]:
            if pattern.search(message_lower):
                return ModelTier.OPUS

        for pattern in patterns["haiku"]:
            if pattern.search(message_lower):
                return ModelTier.HAIKU

        # 6. Conversation context escalation
        if conversation_history and self._should_escalate(conversation_history):
            return ModelTier.OPUS

        # 7. Default
        return ModelTier[cfg["default_model"].upper()]

    def _route_by_tools(self, tools: list, cfg: dict) -> Optional[ModelTier]:
        """Route based on tools being used."""
        tool_routing = cfg["tool_routing"]

        tiers_needed = set()
        for tool in tools:
            if tool in tool_routing:
                tiers_needed.add(tool_routing[tool])

        # Use highest tier needed
        if "opus" in tiers_needed:
            return ModelTier.OPUS
        if "sonnet" in tiers_needed:
            return ModelTier.SONNET
        if "haiku" in tiers_needed:
            return ModelTier.HAIKU

        return None

    def _select_with_speed_bias(self, message: str, task_type: str, tools: list) -> ModelTier:
        """Prefer faster models when quality preference is 'speed'."""
        base = self.select_model(message, task_type=task_type, pending_tools=tools)

        # Downgrade where safe
        if base == ModelTier.OPUS:
            # Only downgrade for non-critical tasks
            critical_tasks = ["schedule_optimization", "decision_support", "meeting_summary"]
            if task_type not in critical_tasks:
                return ModelTier.SONNET

        return base

    def _select_with_quality_bias(self, message: str, task_type: str, tools: list) -> ModelTier:
        """Prefer better models when quality preference is 'quality'."""
        base = self.select_model(message, task_type=task_type, pending_tools=tools)

        # Upgrade where beneficial
        if base == ModelTier.HAIKU:
            return ModelTier.SONNET
        if base == ModelTier.SONNET:
            # Upgrade for anything involving synthesis or generation
            upgrade_tasks = ["email_draft", "note_create", "daily_briefing"]
            if task_type in upgrade_tasks:
                return ModelTier.OPUS

        return base

    def _should_escalate(self, history: list) -> bool:
        """Check if conversation suggests escalation."""
        escalation_triggers = [
            r"i'm not sure",
            r"it's complicated",
            r"there's a conflict",
            r"multiple options",
            r"what would you recommend",
            r"this is important",
            r"high priority",
            r"urgent",
        ]
        patterns = [re.compile(p, re.IGNORECASE) for p in escalation_triggers]

        recent = history[-4:] if len(history) > 4 else history
        for msg in recent:
            if msg.get("role") == "user":
                content = msg.get("content", "").lower()
                for pattern in patterns:
                    if pattern.search(content):
                        return True

        return False

    def should_use_chain(self, message: str, task_type: str) -> Optional[str]:
        """
        Determine if this request should use a multi-model chain.
        Returns chain config name or None.
        """
        cfg = self.config.get_config()

        if not cfg["enable_chaining"]:
            return None

        # Check for chain-appropriate tasks
        chain_tasks = {
            "meeting_summary": "transcribe_summarize_chain",
            "schedule_optimization": "analyze_optimize_chain",
            "email_triage": "classify_triage_chain",
            "complex_query": "classify_execute_synthesize_chain",
        }

        if task_type in chain_tasks:
            chain_name = chain_tasks[task_type]
            if chain_name in cfg["chain_configs"] or chain_name in DEFAULT_CHAINS:
                return chain_name

        return None


# Pre-defined multi-model chains
DEFAULT_CHAINS = {
    "classify_execute_synthesize_chain": {
        "description": "Haiku classifies intent, Sonnet executes tools, Opus synthesizes response",
        "steps": [
            {"model": "haiku", "purpose": "classify", "prompt_template": "classify_intent"},
            {"model": "sonnet", "purpose": "execute", "prompt_template": "execute_tools"},
            {"model": "opus", "purpose": "synthesize", "prompt_template": "synthesize_response"},
        ]
    },
    "transcribe_summarize_chain": {
        "description": "Process meeting: Sonnet structures transcript, Opus generates insights",
        "steps": [
            {"model": "sonnet", "purpose": "structure", "prompt_template": "structure_transcript"},
            {"model": "opus", "purpose": "synthesize", "prompt_template": "meeting_insights"},
        ]
    },
    "analyze_optimize_chain": {
        "description": "Haiku gathers data, Opus analyzes and optimizes",
        "steps": [
            {"model": "haiku", "purpose": "gather", "prompt_template": "gather_schedule_data"},
            {"model": "opus", "purpose": "analyze", "prompt_template": "optimize_schedule"},
        ]
    },
    "classify_triage_chain": {
        "description": "Haiku does initial sort, Sonnet categorizes, Opus prioritizes",
        "steps": [
            {"model": "haiku", "purpose": "classify", "prompt_template": "initial_email_sort"},
            {"model": "sonnet", "purpose": "categorize", "prompt_template": "categorize_emails"},
            {"model": "opus", "purpose": "prioritize", "prompt_template": "prioritize_actions"},
        ]
    },
    "quick_validate_chain": {
        "description": "Sonnet generates, Haiku validates format",
        "steps": [
            {"model": "sonnet", "purpose": "generate", "prompt_template": "generate_content"},
            {"model": "haiku", "purpose": "validate", "prompt_template": "validate_format"},
        ]
    },
}


class ModelChainExecutor:
    """
    Execute multi-model chains for complex tasks.
    """

    def __init__(self, client, router: ModelRouter):
        self.client = client
        self.router = router
        self.prompt_templates = self._load_prompt_templates()

    async def execute_chain(
        self,
        chain_name: str,
        initial_input: str,
        context: dict = None
    ) -> ChainResult:
        """
        Execute a multi-model chain.
        """
        cfg = self.router.config.get_config()
        chain_config = cfg["chain_configs"].get(chain_name) or DEFAULT_CHAINS.get(chain_name)

        if not chain_config:
            raise ValueError(f"Unknown chain: {chain_name}")

        steps_completed = []
        current_input = initial_input
        current_context = context or {}

        for step_config in chain_config["steps"]:
            model_tier = ModelTier[step_config["model"].upper()]
            purpose = step_config["purpose"]

            # Build prompt for this step
            prompt = self._build_step_prompt(
                template_name=step_config["prompt_template"],
                input_data=current_input,
                context=current_context,
                purpose=purpose
            )

            # Execute
            start_time = datetime.utcnow()
            response = await self.client.messages.create(
                model=model_tier.value,
                max_tokens=4096,
                messages=[{"role": "user", "content": prompt}]
            )
            latency = int((datetime.utcnow() - start_time).total_seconds() * 1000)

            # Record step
            step = ModelStep(
                tier=model_tier,
                purpose=purpose,
                input_tokens=response.usage.input_tokens,
                output_tokens=response.usage.output_tokens,
                latency_ms=latency
            )
            steps_completed.append(step)

            # Prepare for next step
            current_input = response.content[0].text
            current_context["previous_step"] = {
                "purpose": purpose,
                "output": current_input
            }

        # Calculate totals
        total_cost = sum(self._calculate_step_cost(s) for s in steps_completed)
        total_latency = sum(s.latency_ms for s in steps_completed)

        return ChainResult(
            steps=steps_completed,
            final_response=current_input,
            total_cost=total_cost,
            total_latency_ms=total_latency
        )

    def _build_step_prompt(self, template_name: str, input_data: str, context: dict, purpose: str) -> str:
        """Build prompt for a chain step."""
        template = self.prompt_templates.get(template_name, "{input}")

        return template.format(
            input=input_data,
            context=json.dumps(context),
            purpose=purpose,
            **context
        )

    def _calculate_step_cost(self, step: ModelStep) -> float:
        costs = CostTracker.COSTS[step.tier]
        return (step.input_tokens / 1000) * costs["input"] + (step.output_tokens / 1000) * costs["output"]

    def _load_prompt_templates(self) -> dict:
        """Load prompt templates for chain steps."""
        return {
            "classify_intent": """Analyze this user request and classify it.

Request: {input}

Respond with JSON:
{{
    "intent": "primary intent",
    "entities": ["extracted entities"],
    "complexity": "simple|moderate|complex",
    "tools_likely_needed": ["tool1", "tool2"],
    "requires_confirmation": true/false
}}""",

            "execute_tools": """Execute the required tools for this request.

Original request: {input}
Classification: {context}

Perform the necessary actions and return the results.""",

            "synthesize_response": """Synthesize a helpful response from these results.

Original request: {input}
Execution results: {context}

Provide a clear, helpful response to the user. If actions were taken, summarize them.
If there are follow-up suggestions, include them.""",

            "structure_transcript": """Structure this meeting transcript into clear sections.

Transcript: {input}

Organize into:
- Key discussion points (in order)
- Participants and their main contributions
- Decisions made
- Questions raised
- Action items mentioned (with who said them)""",

            "meeting_insights": """Generate comprehensive meeting insights.

Structured transcript: {input}

Provide:
1. Executive summary (2-3 sentences)
2. Key decisions and their implications
3. Action items with owners and suggested due dates
4. Follow-up items
5. Any concerns or risks mentioned
6. Suggested next steps""",

            "gather_schedule_data": """Gather and organize schedule data for optimization.

Request: {input}

List all relevant:
- Current events in the time range
- Their constraints (fixed vs flexible)
- Travel time requirements
- Buffer preferences
- Protected time blocks""",

            "optimize_schedule": """Optimize this schedule based on the gathered data.

Schedule data: {input}
User preferences: {context}

Provide:
1. Recommended changes with reasoning
2. Trade-offs for each change
3. Alternative options if changes aren't accepted
4. Impact analysis""",

            "initial_email_sort": """Do an initial sort of these emails.

Emails: {input}

Categorize each as:
- urgent_action: Needs response today
- needs_response: Should respond within a few days
- informational: FYI only
- low_priority: Can wait or ignore
- spam: Junk""",

            "categorize_emails": """Categorize these sorted emails by topic and action type.

Sorted emails: {input}

Group by:
- Topic/project
- Type of action needed (reply, schedule, delegate, archive)
- Related threads""",

            "prioritize_actions": """Create a prioritized action list from these categorized emails.

Categorized emails: {input}

Provide:
1. Top 3 emails that need immediate attention and why
2. Suggested responses for urgent items
3. Items that can be batched together
4. Recommended delegation if applicable
5. Summary of what can be safely ignored""",

            "generate_content": """Generate the requested content.

Request: {input}
Context: {context}""",

            "validate_format": """Validate this content meets requirements.

Content: {input}
Requirements: Proper formatting, no errors, complete information

If issues found, list them. If valid, respond with "VALID".""",
        }


class CostTracker:
    """Track model usage for cost awareness and analytics."""

    COSTS = {
        ModelTier.HAIKU: {"input": 0.00025, "output": 0.00125},
        ModelTier.SONNET: {"input": 0.003, "output": 0.015},
        ModelTier.OPUS: {"input": 0.015, "output": 0.075},
    }

    def __init__(self, db_session, user_id: str):
        self.db = db_session
        self.user_id = user_id

    def record_usage(
        self,
        tier: ModelTier,
        input_tokens: int,
        output_tokens: int,
        conversation_id: str = None,
        task_type: str = None,
        routing_reason: str = None,
        latency_ms: int = None
    ):
        """Record model usage to database."""
        usage = ModelUsage(
            user_id=self.user_id,
            conversation_id=conversation_id,
            model_tier=tier.name.lower(),
            model_version=tier.value,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            task_type=task_type,
            routing_reason=routing_reason,
            latency_ms=latency_ms,
            created_at=datetime.utcnow()
        )
        self.db.add(usage)
        self.db.commit()

    def get_usage_summary(self, period: str = "day") -> dict:
        """Get usage summary for a time period."""
        if period == "day":
            start = datetime.utcnow() - timedelta(days=1)
        elif period == "week":
            start = datetime.utcnow() - timedelta(weeks=1)
        elif period == "month":
            start = datetime.utcnow() - timedelta(days=30)
        else:
            start = datetime.utcnow() - timedelta(days=1)

        usages = self.db.query(ModelUsage).filter(
            ModelUsage.user_id == self.user_id,
            ModelUsage.created_at >= start
        ).all()

        summary = {
            "period": period,
            "start": start.isoformat(),
            "end": datetime.utcnow().isoformat(),
            "by_model": {},
            "by_task": {},
            "totals": {
                "requests": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cost": 0.0,
                "avg_latency_ms": 0
            }
        }

        latencies = []

        for usage in usages:
            tier = ModelTier[usage.model_tier.upper()]

            # By model
            if tier.name not in summary["by_model"]:
                summary["by_model"][tier.name] = {
                    "requests": 0,
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "cost": 0.0
                }

            model_summary = summary["by_model"][tier.name]
            model_summary["requests"] += 1
            model_summary["input_tokens"] += usage.input_tokens
            model_summary["output_tokens"] += usage.output_tokens
            model_summary["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            # By task
            task = usage.task_type or "unknown"
            if task not in summary["by_task"]:
                summary["by_task"][task] = {"requests": 0, "cost": 0.0}
            summary["by_task"][task]["requests"] += 1
            summary["by_task"][task]["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            # Totals
            summary["totals"]["requests"] += 1
            summary["totals"]["input_tokens"] += usage.input_tokens
            summary["totals"]["output_tokens"] += usage.output_tokens
            summary["totals"]["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            if usage.latency_ms:
                latencies.append(usage.latency_ms)

        if latencies:
            summary["totals"]["avg_latency_ms"] = sum(latencies) // len(latencies)

        return summary

    def get_daily_costs(self, days: int = 30) -> List[dict]:
        """Get daily cost breakdown for charting."""
        start = datetime.utcnow() - timedelta(days=days)

        usages = self.db.query(ModelUsage).filter(
            ModelUsage.user_id == self.user_id,
            ModelUsage.created_at >= start
        ).all()

        # Group by day
        daily = {}
        for usage in usages:
            day = usage.created_at.date().isoformat()
            tier = ModelTier[usage.model_tier.upper()]
            cost = self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            if day not in daily:
                daily[day] = {"date": day, "haiku": 0, "sonnet": 0, "opus": 0, "total": 0}

            daily[day][tier.name.lower()] += cost
            daily[day]["total"] += cost

        return sorted(daily.values(), key=lambda x: x["date"])

    def check_daily_limit(self) -> tuple[bool, float, float]:
        """Check if daily cost limit is exceeded. Returns (within_limit, current_cost, limit)."""
        cfg_query = self.db.query(RoutingSettings).filter(
            RoutingSettings.user_id == self.user_id
        ).first()

        limit = cfg_query.cost_limit_daily if cfg_query else None

        if not limit:
            return True, 0, None

        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

        usages = self.db.query(ModelUsage).filter(
            ModelUsage.user_id == self.user_id,
            ModelUsage.created_at >= today_start
        ).all()

        current_cost = sum(
            self._calculate_cost(ModelTier[u.model_tier.upper()], u.input_tokens, u.output_tokens)
            for u in usages
        )

        return current_cost < limit, current_cost, limit

    def _calculate_cost(self, tier: ModelTier, input_tokens: int, output_tokens: int) -> float:
        costs = self.COSTS[tier]
        return (input_tokens / 1000) * costs["input"] + (output_tokens / 1000) * costs["output"]
```

### Updated Chat Handler with Routing and Chaining

```python
class ChatHandler:
    def __init__(self, db: Session, user_id: str):
        self.db = db
        self.user_id = user_id
        self.client = Anthropic()

        # Initialize routing
        self.routing_config = RoutingConfig(db, user_id)
        self.router = ModelRouter(self.routing_config)
        self.chain_executor = ModelChainExecutor(self.client, self.router)
        self.cost_tracker = CostTracker(db, user_id)
        self.tool_executor = ToolExecutor(db, user_id)

    async def process_message(
        self,
        message: str,
        conversation_id: Optional[str] = None,
        source: str = "web"
    ) -> ChatResponse:
        # Check cost limits
        within_limit, current_cost, limit = self.cost_tracker.check_daily_limit()
        if not within_limit:
            return ChatResponse(
                response=f"Daily cost limit (${limit:.2f}) reached. Current spend: ${current_cost:.2f}. You can adjust this in settings.",
                conversation_id=conversation_id,
                actions_taken=[]
            )

        # Classify task
        task_type = await self._classify_task(message)

        # Check if we should use a chain
        chain_name = self.router.should_use_chain(message, task_type)

        if chain_name:
            # Execute multi-model chain
            result = await self.chain_executor.execute_chain(
                chain_name=chain_name,
                initial_input=message,
                context={"conversation_id": conversation_id, "source": source}
            )

            # Record all steps
            for step in result.steps:
                self.cost_tracker.record_usage(
                    tier=step.tier,
                    input_tokens=step.input_tokens,
                    output_tokens=step.output_tokens,
                    conversation_id=conversation_id,
                    task_type=task_type,
                    routing_reason=f"chain:{chain_name}:{step.purpose}",
                    latency_ms=step.latency_ms
                )

            return ChatResponse(
                response=result.final_response,
                conversation_id=conversation_id,
                actions_taken=[],
                model_info={
                    "chain": chain_name,
                    "steps": [{"model": s.tier.name, "purpose": s.purpose} for s in result.steps],
                    "total_cost": result.total_cost
                }
            )

        # Standard single-model flow
        conversation = self._get_or_create_conversation(conversation_id)
        history = self._build_history(conversation.id)
        system_prompt = self._build_system_prompt()

        # Select model
        model_tier = self.router.select_model(
            message=message,
            conversation_history=history,
            task_type=task_type
        )

        # Execute
        start_time = datetime.utcnow()
        response = await self.client.messages.create(
            model=model_tier.value,
            max_tokens=4096,
            system=system_prompt,
            tools=TOOLS,
            messages=history + [{"role": "user", "content": message}]
        )
        latency = int((datetime.utcnow() - start_time).total_seconds() * 1000)

        # Track usage
        self.cost_tracker.record_usage(
            tier=model_tier,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            conversation_id=conversation.id,
            task_type=task_type,
            routing_reason=f"direct:{task_type}",
            latency_ms=latency
        )

        # Handle tool use
        actions_taken = []
        while response.stop_reason == "tool_use":
            tool_results = await self._execute_tools(response.content)
            actions_taken.extend(tool_results)

            # Maybe adjust model for next iteration
            model_tier = self.router.select_for_tool_response(
                original_tier=model_tier,
                tool_results=tool_results,
                remaining_steps=self._estimate_remaining_steps(response)
            )

            start_time = datetime.utcnow()
            response = await self.client.messages.create(
                model=model_tier.value,
                max_tokens=4096,
                system=system_prompt,
                tools=TOOLS,
                messages=self._build_continuation(history, message, response, tool_results)
            )
            latency = int((datetime.utcnow() - start_time).total_seconds() * 1000)

            self.cost_tracker.record_usage(
                tier=model_tier,
                input_tokens=response.usage.input_tokens,
                output_tokens=response.usage.output_tokens,
                conversation_id=conversation.id,
                task_type=f"{task_type}_tool_continue",
                routing_reason="tool_continuation",
                latency_ms=latency
            )

        self._save_messages(conversation.id, message, response)

        return ChatResponse(
            response=self._extract_text(response),
            conversation_id=conversation.id,
            actions_taken=actions_taken,
            model_info={"model": model_tier.name, "task_type": task_type}
        )

    async def _classify_task(self, message: str) -> str:
        """Quick task classification using Haiku."""
        response = await self.client.messages.create(
            model=ModelTier.HAIKU.value,
            max_tokens=100,
            messages=[{
                "role": "user",
                "content": f"""Classify this request into one category:
greeting, simple_lookup, confirmation, basic_crud, status_check, calendar_query, reminder_query,
calendar_create, reminder_create, note_create, email_draft, standard_tool_use, daily_briefing,
schedule_optimization, weekly_review, meeting_summary, complex_analysis, decision_support,
pattern_learning, conflict_resolution, email_triage, project_status, explain_reasoning

Request: {message}

Category:"""
            }]
        )

        return response.content[0].text.strip().lower()
```

### Routing Examples

| User Message                                             | Model(s) Used                 | Reason                     |
| -------------------------------------------------------- | ----------------------------- | -------------------------- |
| "What's on my calendar today?"                           | Haiku                         | Simple lookup pattern      |
| "Schedule a meeting with Dan tomorrow at 2pm"            | Sonnet                        | Standard tool use          |
| "Optimize my schedule for next week"                     | Haiku → Opus (chain)          | analyze_optimize_chain     |
| "Thanks!"                                                | Haiku                         | Simple confirmation        |
| "Help me decide whether to reschedule the board meeting" | Opus                          | Decision support pattern   |
| "Summarize my meeting with the product team"             | Sonnet → Opus (chain)         | transcribe_summarize_chain |
| "Add milk to my grocery list"                            | Haiku                         | Simple CRUD                |
| "Triage my inbox"                                        | Haiku → Sonnet → Opus (chain) | classify_triage_chain      |
| "What patterns have you noticed in my scheduling?"       | Opus                          | Pattern analysis           |
| "Why did you suggest moving that meeting?"               | Opus                          | Explain reasoning          |

---

### 7. Push Notification Service (`app/services/notifications.py`)

```python
"""
Apple Push Notification service.
"""
from apns2.client import APNsClient
from apns2.payload import Payload

class PushNotificationService:
    def __init__(self, cert_path: str, bundle_id: str):
        self.client = APNsClient(cert_path, use_sandbox=False)
        self.bundle_id = bundle_id

    async def send_notification(
        self,
        user_id: str,
        title: str,
        body: str,
        category: str = "info",
        action_url: Optional[str] = None,
        db: Session = None
    ):
        # Get device tokens for user
        tokens = db.query(DeviceToken).filter(
            DeviceToken.user_id == user_id
        ).all()

        payload = Payload(
            alert={"title": title, "body": body},
            sound="default",
            category=category,
            custom={"action_url": action_url} if action_url else {}
        )

        for token in tokens:
            try:
                self.client.send_notification(
                    token.token,
                    payload,
                    self.bundle_id
                )
            except Exception as e:
                # Handle invalid tokens
                if "Unregistered" in str(e):
                    db.delete(token)
                    db.commit()
```

---

## Web Interface Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── Chat/
│   │   │   ├── ChatWindow.tsx      # Main chat interface
│   │   │   ├── MessageBubble.tsx   # Individual messages
│   │   │   ├── ToolCallDisplay.tsx # Show actions taken
│   │   │   ├── ModelBadge.tsx      # Shows which model responded
│   │   │   └── VoiceInput.tsx      # Voice recording option
│   │   ├── Activity/
│   │   │   ├── ActivityLog.tsx     # Activity feed
│   │   │   ├── ActivityItem.tsx    # Single activity
│   │   │   └── UndoButton.tsx      # Undo action
│   │   ├── Analytics/
│   │   │   ├── AnalyticsDashboard.tsx    # Main analytics view
│   │   │   ├── UsageSummaryCards.tsx     # Quick stats cards
│   │   │   ├── CostChart.tsx             # Daily cost line/bar chart
│   │   │   ├── ModelDistributionPie.tsx  # Pie chart of model usage
│   │   │   ├── TaskBreakdownTable.tsx    # Table of usage by task
│   │   │   ├── LatencyChart.tsx          # Response time trends
│   │   │   └── CostProjection.tsx        # Projected monthly cost
│   │   ├── ModelSettings/
│   │   │   ├── RoutingSettings.tsx       # Main settings view
│   │   │   ├── TaskRoutingEditor.tsx     # Edit task -> model mappings
│   │   │   ├── ToolRoutingEditor.tsx     # Edit tool -> model mappings
│   │   │   ├── PatternEditor.tsx         # Add/remove regex patterns
│   │   │   ├── ChainEditor.tsx           # Configure multi-model chains
│   │   │   ├── ChainVisualizer.tsx       # Visual chain step display
│   │   │   ├── CostLimitSetting.tsx      # Daily budget cap
│   │   │   ├── QualitySpeedToggle.tsx    # Prefer speed vs quality
│   │   │   └── RoutingTester.tsx         # Test routing for messages
│   │   ├── Calendar/
│   │   │   ├── CalendarView.tsx    # Calendar display
│   │   │   ├── EventCard.tsx       # Event details
│   │   │   └── OptimizationModal.tsx # Approve schedule changes
│   │   ├── Meetings/
│   │   │   ├── MeetingsList.tsx    # List of meetings with summaries
│   │   │   ├── MeetingDetail.tsx   # Full meeting summary
│   │   │   ├── AudioUpload.tsx     # Upload meeting recording
│   │   │   └── ActionItems.tsx     # Action items from meeting
│   │   ├── Notes/
│   │   │   ├── NotesList.tsx       # Browse notes
│   │   │   ├── NoteEditor.tsx      # View/edit note
│   │   │   └── NoteSearch.tsx      # Search notes
│   │   ├── Projects/
│   │   │   ├── ProjectsList.tsx    # All projects
│   │   │   └── ProjectDetail.tsx   # Project with related items
│   │   ├── ReadLater/
│   │   │   └── ReadLaterList.tsx   # Read later queue
│   │   └── Settings/
│   │       ├── Preferences.tsx     # User preferences
│   │       ├── Locations.tsx       # Manage locations
│   │       └── Notifications.tsx   # Notification settings
│   ├── pages/
│   │   ├── Login.tsx
│   │   ├── Dashboard.tsx           # Main view with chat + briefing
│   │   ├── Calendar.tsx
│   │   ├── Meetings.tsx
│   │   ├── Notes.tsx
│   │   ├── Projects.tsx
│   │   ├── Activity.tsx
│   │   ├── Analytics.tsx           # Analytics dashboard page
│   │   ├── ModelSettings.tsx       # Model routing settings page
│   │   └── Settings.tsx
│   ├── hooks/
│   │   ├── useChat.ts              # Chat functionality
│   │   ├── useAuth.ts              # Authentication
│   │   ├── useAnalytics.ts         # Analytics data fetching
│   │   ├── useRoutingSettings.ts   # Routing config management
│   │   └── usePushNotifications.ts # Register for push
│   ├── api/
│   │   └── client.ts               # API client
│   └── App.tsx
```

### Key UI Components

**Dashboard Layout:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Kai - Dashboard                            [Activity] [Settings]│
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────┐  ┌───────────────────────────┐ │
│  │     Daily Briefing          │  │     Today's Schedule      │ │
│  │                             │  │                           │ │
│  │  Good morning, Kamron!      │  │  9:00  Team standup       │ │
│  │                             │  │  10:30 1:1 with Sarah     │ │
│  │  Weather: 72°F, sunny       │  │  12:00 Lunch (protected)  │ │
│  │                             │  │  2:00  Project review     │ │
│  │  3 priority emails          │  │  4:00  Focus time         │ │
│  │  2 pending follow-ups       │  │                           │ │
│  │                             │  │                           │ │
│  └─────────────────────────────┘  └───────────────────────────┘ │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                         Chat with Kai                        ││
│  │                                                              ││
│  │  You: What's my schedule like tomorrow?                     ││
│  │                                                              ││
│  │  Kai: Tomorrow you have 4 meetings:           [Haiku ⚡]    ││
│  │  • 9am - Budget review with finance team                    ││
│  │  • 11am - Interview: Senior developer candidate             ││
│  │  • 2pm - Project kickoff (Building B - leave by 1:40)       ││
│  │  • 4pm - Weekly sync with leadership                        ││
│  │                                                              ││
│  │  You have a 2-hour focus block in the morning. Want me      ││
│  │  to protect that time?                                       ││
│  │                                                              ││
│  │  [─────────────────────────────────────────────────] [Send] ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Analytics Dashboard:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Kai - Analytics                    [Day ▾] [Week] [Month]      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────┐│
│  │  Requests    │ │  Total Cost  │ │  Avg Latency │ │ Projected││
│  │    247       │ │    $3.42     │ │    1.2s      │ │  $42/mo  ││
│  │  ↑12% week   │ │  ↓8% week    │ │  ↓0.3s week  │ │          ││
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────┘│
│                                                                  │
│  ┌─────────────────────────────────┐ ┌─────────────────────────┐│
│  │     Cost by Day (Last 30d)      │ │   Model Distribution    ││
│  │                                 │ │                         ││
│  │  $0.50 ┤      ╭─╮               │ │      ┌─────────────┐    ││
│  │        │    ╭─╯ ╰╮   ╭╮        │ │      │   Haiku     │    ││
│  │  $0.25 ┤  ╭─╯    ╰─╮╭╯╰╮       │ │      │    62%      │    ││
│  │        │╭─╯        ╰╯  ╰─╮     │ │      ├─────────────┤    ││
│  │  $0.00 ┼─────────────────╰──   │ │      │  Sonnet 31% │    ││
│  │        Jan 1        Jan 30     │ │      │  Opus 7%    │    ││
│  │  ■ Haiku ■ Sonnet ■ Opus       │ │      └─────────────┘    ││
│  └─────────────────────────────────┘ └─────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Usage by Task Type                        ││
│  ├────────────────────┬──────────┬─────────┬─────────┬─────────┤│
│  │ Task Type          │ Requests │ Model   │ Cost    │ Latency ││
│  ├────────────────────┼──────────┼─────────┼─────────┼─────────┤│
│  │ calendar_query     │    89    │ Haiku   │ $0.12   │  0.4s   ││
│  │ email_draft        │    34    │ Sonnet  │ $0.87   │  1.8s   ││
│  │ meeting_summary    │    12    │ Chain   │ $1.24   │  4.2s   ││
│  │ schedule_optimize  │     5    │ Opus    │ $0.95   │  3.1s   ││
│  │ reminder_create    │    42    │ Haiku   │ $0.08   │  0.3s   ││
│  │ ...                │          │         │         │         ││
│  └────────────────────┴──────────┴─────────┴─────────┴─────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Model Settings Page:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Kai - Model Settings                          [Reset Defaults] │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  General Settings                                            ││
│  │                                                              ││
│  │  Default Model:  [Sonnet ▾]                                  ││
│  │                                                              ││
│  │  Quality Preference:                                         ││
│  │  ◉ Balanced   ○ Prefer Speed   ○ Prefer Quality             ││
│  │                                                              ││
│  │  Daily Cost Limit:  [$5.00    ] (leave empty for unlimited) ││
│  │                                                              ││
│  │  ☑ Enable Multi-Model Chains                                ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Task Routing                                    [+ Add]     ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │  greeting            │ [Haiku ▾]   │ Default               ││
│  │  simple_lookup       │ [Haiku ▾]   │ Default               ││
│  │  calendar_create     │ [Sonnet ▾]  │ Default               ││
│  │  email_draft         │ [Opus ▾]    │ ★ Custom override     ││
│  │  schedule_optimize   │ [Opus ▾]    │ Default               ││
│  │  meeting_summary     │ [Chain ▾]   │ Default               ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Chain Configurations                            [+ New]     ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │                                                              ││
│  │  ┌─ transcribe_summarize_chain ──────────────────────────┐  ││
│  │  │                                                        │  ││
│  │  │  [Sonnet] ──────► [Opus]                              │  ││
│  │  │  Structure        Insights                             │  ││
│  │  │                                                        │  ││
│  │  │  Used for: meeting_summary                    [Edit]   │  ││
│  │  └────────────────────────────────────────────────────────┘  ││
│  │                                                              ││
│  │  ┌─ classify_triage_chain ───────────────────────────────┐  ││
│  │  │                                                        │  ││
│  │  │  [Haiku] ──► [Sonnet] ──► [Opus]                      │  ││
│  │  │  Classify    Categorize   Prioritize                   │  ││
│  │  │                                                        │  ││
│  │  │  Used for: email_triage                       [Edit]   │  ││
│  │  └────────────────────────────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Test Routing                                                ││
│  │                                                              ││
│  │  [Type a message to see which model would handle it...    ] ││
│  │                                                              ││
│  │  Result: "optimize my schedule" → Opus (chain: analyze_opt) ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Chain Editor Modal:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Edit Chain: transcribe_summarize_chain                    [X]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Name: [transcribe_summarize_chain                           ]  │
│  Description: [Process meeting: structure then insights      ]  │
│                                                                  │
│  Steps:                                                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Step 1                                              [🗑️]    ││
│  │  Model: [Sonnet ▾]    Purpose: [structure ▾]                ││
│  │  Prompt Template: [structure_transcript ▾]                  ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Step 2                                              [🗑️]    ││
│  │  Model: [Opus ▾]      Purpose: [synthesize ▾]               ││
│  │  Prompt Template: [meeting_insights ▾]                      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  [+ Add Step]                                                    │
│                                                                  │
│  Used for tasks: [meeting_summary ▾] [+ Add]                    │
│                                                                  │
│                                        [Cancel]  [Save Chain]   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Siri Shortcut Configuration

Create a Shortcut named "Kai" with these steps:

```
1. Dictate Text
   - Language: English
   - Stop Listening: After Pause

   [Output: Dictated Text]

2. Get Contents of URL
   - URL: https://your-domain.com/api/chat
   - Method: POST
   - Headers:
     - Authorization: Bearer [your-jwt-token]
     - Content-Type: application/json
   - Request Body: JSON
     {
       "message": [Dictated Text],
       "source": "siri"
     }

   [Output: Contents of URL]

3. Get Dictionary Value
   - Get: Value for "response"
   - in: [Contents of URL]

   [Output: Dictionary Value]

4. Speak Text
   - Text: [Dictionary Value]
   - Voice: Samantha (or preferred)
   - Rate: Default
```

**Invocation:** "Hey Siri, Kai schedule a meeting with Dan tomorrow at 2pm"

---

## Proactive Task Scheduler

Set up these scheduled tasks:

```python
SCHEDULED_TASKS = [
    {
        "task_type": "daily_briefing",
        "schedule": {"hour": 7, "minute": 0},  # 7 AM daily
        "action": "Generate and push daily briefing"
    },
    {
        "task_type": "weekly_review",
        "schedule": {"day_of_week": "sunday", "hour": 18, "minute": 0},  # Sunday 6 PM
        "action": "Generate and push weekly review"
    },
    {
        "task_type": "break_reminder",
        "schedule": {"interval_minutes": 90},  # Every 90 mins during focus blocks
        "action": "Check for long focus sessions, push break reminder"
    },
    {
        "task_type": "follow_up_check",
        "schedule": {"hour": 9, "minute": 0},  # 9 AM daily
        "action": "Check for overdue follow-ups, notify if any"
    },
    {
        "task_type": "departure_alert",
        "schedule": {"check_interval_minutes": 15},
        "action": "Check upcoming events with locations, calculate travel, alert if time to leave"
    }
]
```

---

## Implementation Order

Build in this sequence:

### Phase 1: Foundation

1. Database setup (Postgres schema)
2. FastAPI server skeleton
3. Authentication (JWT)
4. Basic chat endpoint with Claude
5. Activity logging

### Phase 2: Core Features

6. Calendar integration (CalDAV)
7. Basic tool definitions for calendar CRUD
8. Reminders integration
9. Notes storage and search
10. Web interface (chat + basic views)

### Phase 3: Intelligence

11. Whisper transcription service
12. Meeting summary generation
13. Action item extraction
14. Schedule optimizer
15. Preference learning system

### Phase 4: Proactive Features

16. Push notification service
17. Scheduled tasks (briefings, reminders)
18. Travel time integration
19. Follow-up tracking
20. Email triage (Gmail)

### Phase 5: Polish

21. Siri Shortcut setup
22. Weekly review generation
23. Project tracking
24. Read-it-later queue
25. Undo functionality
26. Explain reasoning capability

---

## Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/kai

# Claude API
ANTHROPIC_API_KEY=sk-ant-...

# Apple Calendar (CalDAV)
CALDAV_URL=https://caldav.icloud.com
CALDAV_USERNAME=your@icloud.com
CALDAV_PASSWORD=app-specific-password

# Gmail
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...

# Apple Push Notifications
APNS_CERT_PATH=/path/to/cert.pem
APNS_BUNDLE_ID=com.yourapp.kai

# Google Maps (traffic)
GOOGLE_MAPS_API_KEY=...

# JWT
JWT_SECRET=your-secret-key
JWT_ALGORITHM=HS256

# Server
HOST=0.0.0.0
PORT=8000
```

---

## Security Considerations

1. **Authentication**: JWT tokens with refresh mechanism
2. **API Keys**: Store in environment, never in code
3. **Cloudflare Tunnel**: Handles HTTPS termination
4. **Database**: Use parameterized queries (SQLAlchemy handles this)
5. **Input Validation**: Pydantic models for all inputs
6. **Rate Limiting**: Implement for public endpoints
7. **Audit Log**: All actions logged with timestamps

---

## Testing Commands

```bash
# Start server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Test chat endpoint
curl -X POST http://localhost:8000/api/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "What is on my calendar today?", "source": "web"}'

# Test transcription
curl -X POST http://localhost:8000/api/meetings/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "audio=@meeting.m4a" \
  -F "calendar_event_id=event123"
```

---

This specification should give you everything needed to build Kai. Start with Phase 1 and work through sequentially. Each component is designed to work independently, so you can test as you go.

Questions to ask while building:

- "I'm implementing [component]. Here's my approach... does this match the spec?"
- "I'm stuck on [issue]. The spec says X but I'm seeing Y."
- "Ready for Phase N. What's the first task?"

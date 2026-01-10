# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kai (Kamron's Adaptive Intelligence) is a personal AI assistant that manages scheduling, meeting intelligence, tasks, notes, email triage, and more. It learns from user patterns and is accessible via Siri voice commands, a web interface, and push notifications.

## Tech Stack

**Backend:** Python 3.11+, FastAPI, SQLAlchemy (async), Alembic, Anthropic SDK, openai-whisper, caldav, google-api-python-client, APNs2, python-jose, pydantic

**Frontend:** React 18, TypeScript, Vite, TailwindCSS, React Query, React Router, Recharts, Lucide Icons

**Infrastructure:** PostgreSQL 17, Docker, Docker Compose, NVIDIA CUDA (GPU server)

## Quick Start

```bash
# Development
./scripts/start-dev.sh

# Or manually:
docker-compose up -d

# Access points:
# Frontend: http://localhost:5173
# Backend API: http://localhost:8000
# API Docs: http://localhost:8000/docs
```

## Project Structure

```
kai/
├── docker-compose.yml          # Development services
├── docker-compose.prod.yml     # Production with GPU
├── Dockerfile                  # Backend (Python 3.11)
├── Dockerfile.gpu              # Backend with CUDA
├── Dockerfile.frontend         # Frontend (Node 20)
├── .env.example               # Environment template
├── backend/
│   ├── app/
│   │   ├── main.py            # FastAPI entry
│   │   ├── config.py          # Pydantic settings
│   │   ├── database.py        # Async SQLAlchemy
│   │   ├── models/            # SQLAlchemy models
│   │   ├── schemas/           # Pydantic schemas
│   │   ├── api/               # Route handlers
│   │   ├── core/              # Intelligence layer
│   │   │   ├── chat.py        # ChatHandler
│   │   │   ├── model_router.py # Model selection
│   │   │   ├── tools.py       # Tool definitions
│   │   │   └── tool_executor.py
│   │   └── services/          # External integrations
│   │       ├── calendar.py    # CalDAV
│   │       ├── transcription.py # Whisper
│   │       ├── email.py       # Gmail
│   │       ├── notifications.py # APNs
│   │       ├── weather.py     # Open-Meteo
│   │       ├── maps.py        # Google Maps
│   │       ├── learning.py    # Preference learning
│   │       └── optimizer.py   # Schedule optimization
│   ├── alembic/               # Migrations
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── api/client.ts      # API client
│   │   ├── hooks/             # React hooks
│   │   ├── components/        # React components
│   │   └── pages/             # Page components
│   ├── package.json
│   └── vite.config.ts
└── scripts/
    └── start-dev.sh
```

## Common Commands

```bash
# Backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Database migrations
alembic upgrade head
alembic revision --autogenerate -m "description"

# Frontend
npm run dev
npm run build

# Docker
docker-compose up -d
docker-compose logs -f backend
docker-compose down
```

## API Endpoints

- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - Login (returns JWT tokens)
- `POST /api/auth/refresh` - Refresh access token
- `GET /api/auth/me` - Current user info

- `POST /api/chat` - Send message to Kai
- `GET /api/chat/conversations` - List conversations
- `GET /api/chat/conversations/{id}` - Get conversation

- `GET /api/calendar/events` - Get events
- `POST /api/calendar/events` - Create event
- `GET /api/calendar/optimize` - Schedule optimization

- `GET /api/notes/search` - Search notes
- `POST /api/notes` - Create note
- `GET /api/meetings` - List meetings
- `POST /api/meetings/{id}/transcribe` - Upload audio

- `GET /api/usage/summary` - Usage metrics
- `GET /api/routing/config` - Model routing config
- `PUT /api/routing/config` - Update routing

## Architecture

### Core Components

- **ChatHandler** (`app/core/chat.py`): Main orchestrator that processes messages, manages conversation history, executes tools, and handles model routing with agentic tool loops

- **ModelRouter** (`app/core/model_router.py`): Intelligent model selection based on:
  - Task complexity analysis
  - Keyword patterns
  - Conversation length
  - Pending tool calls
  - Multi-model chain support

- **ToolExecutor** (`app/core/tool_executor.py`): Executes 40+ Claude tools including calendar, reminders, notes, email, projects, follow-ups, weather, travel time, preferences, and briefings

### Model Routing Strategy

Three tiers with automatic routing:

| Model | Use Cases | Cost |
|-------|-----------|------|
| **Haiku** | Simple lookups, confirmations, greetings | Lowest |
| **Sonnet** | Standard tool use, drafting, CRUD | Medium |
| **Opus** | Complex reasoning, optimization, analysis | Highest |

Multi-model chains for complex tasks:
- `meeting_summary`: Haiku (transcribe) → Sonnet (extract) → Opus (synthesize)
- `schedule_optimization`: Haiku (gather) → Opus (analyze) → Sonnet (format)
- `email_triage`: Haiku (categorize) → Sonnet (prioritize) → Haiku (format)

### Database Models

- `User`, `Conversation`, `Message` - Core chat
- `ActivityLog` - Audit trail with undo support
- `Note`, `Project`, `Meeting`, `MeetingSummary`
- `FollowUp`, `ReadLaterItem`
- `UserPreference`, `DeviceToken`
- `ModelUsage`, `RoutingSettings`

## Key Behavioral Rules

1. **Never modify calendar directly** - Always propose changes first
2. **Never send emails directly** - Only draft for user review
3. **Always confirm**: Calendar changes, sending communications, deletions
4. **Silently execute**: Searches, lookups, briefings, saving notes
5. **Log all actions** to activity log for undo capability

## Environment Variables

Required in `.env`:
```
DATABASE_URL=postgresql+asyncpg://kai:password@db:5432/kai
ANTHROPIC_API_KEY=sk-ant-...
JWT_SECRET=your-secret-key

# Optional integrations
CALDAV_URL=https://caldav.icloud.com/...
CALDAV_USERNAME=
CALDAV_PASSWORD=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_MAPS_API_KEY=
APNS_CERT_PATH=
APNS_BUNDLE_ID=
```

## GPU Deployment

For production with Whisper transcription:

```bash
docker-compose -f docker-compose.prod.yml up -d
```

Uses `Dockerfile.gpu` with NVIDIA CUDA 12.1 base image.

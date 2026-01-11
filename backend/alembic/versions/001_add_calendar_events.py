"""Add calendar_events table

Revision ID: 001_add_calendar_events
Revises:
Create Date: 2026-01-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '001_add_calendar_events'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'calendar_events',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('end', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_all_day', sa.Boolean(), default=False),
        sa.Column('location', sa.String(500), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('eventkit_id', sa.String(255), nullable=True),
        sa.Column('source', sa.String(50), nullable=True),
        sa.Column('calendar_name', sa.String(255), nullable=True),
        sa.Column('calendar_color', sa.String(20), nullable=True),
        sa.Column('recurrence_rule', sa.String(500), nullable=True),
        sa.Column('created_at', sa.DateTime(), default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), default=sa.func.now(), onupdate=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_calendar_events_user_id', 'calendar_events', ['user_id'])
    op.create_index('ix_calendar_events_start', 'calendar_events', ['start'])
    op.create_index('ix_calendar_events_eventkit_id', 'calendar_events', ['eventkit_id'])


def downgrade() -> None:
    op.drop_index('ix_calendar_events_eventkit_id', table_name='calendar_events')
    op.drop_index('ix_calendar_events_start', table_name='calendar_events')
    op.drop_index('ix_calendar_events_user_id', table_name='calendar_events')
    op.drop_table('calendar_events')

"""Add timezone column to users table

Revision ID: 002_add_user_timezone
Revises: 001_add_calendar_events
Create Date: 2026-01-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '002_add_user_timezone'
down_revision: Union[str, None] = '001_add_calendar_events'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('timezone', sa.String(50), nullable=False, server_default='America/Chicago')
    )


def downgrade() -> None:
    op.drop_column('users', 'timezone')

"""Add is_video column to timeline_posts

Revision ID: f6a2c8e1b3d5
Revises: b3e1f9a2c7d4
Create Date: 2026-07-13 00:00:00.000001

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f6a2c8e1b3d5'
down_revision = 'b3e1f9a2c7d4'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'timeline_posts',
        sa.Column(
            'is_video',
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade():
    op.drop_column('timeline_posts', 'is_video')
"""Add last_read_at to group_members

Revision ID: e1a2b3c4d5f6
Revises: c2f7b8a1d3e6
Create Date: 2026-07-23 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'e1a2b3c4d5f6'
down_revision = 'c2f7b8a1d3e6'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('group_members', schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                'last_read_at',
                sa.DateTime(timezone=True),
                nullable=False,
                # Backfill existing memberships to "now" so the unread-count
                # feature doesn't retroactively flood everyone with every
                # message ever sent before this migration ran — only new
                # messages from this point on count as unread.
                server_default=sa.text('CURRENT_TIMESTAMP'),
            )
        )


def downgrade():
    with op.batch_alter_table('group_members', schema=None) as batch_op:
        batch_op.drop_column('last_read_at')
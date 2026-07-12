"""Add chat_type to group_chats

Revision ID: a1b2c3d4e5f6
Revises: f3a9c1d2e4b6
Create Date: 2026-07-12 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = 'f3a9c1d2e4b6'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('group_chats', schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                'chat_type',
                sa.String(length=10),
                nullable=False,
                server_default='group',
            )
        )
        batch_op.create_index(
            batch_op.f('ix_group_chats_chat_type'), ['chat_type'], unique=False
        )


def downgrade():
    with op.batch_alter_table('group_chats', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_group_chats_chat_type'))
        batch_op.drop_column('chat_type')

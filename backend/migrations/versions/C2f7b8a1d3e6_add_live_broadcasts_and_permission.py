"""Add live_broadcasts table and user broadcast permission columns

Revision ID: c2f7b8a1d3e6
Revises: d8e4a1c6f2b9
Create Date: 2026-07-21 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c2f7b8a1d3e6'
down_revision = 'd8e4a1c6f2b9'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('can_go_live', sa.Boolean(), nullable=False, server_default='false'))
        batch_op.add_column(sa.Column('broadcast_permission_granted_by_id', sa.BigInteger(), nullable=True))
        batch_op.add_column(sa.Column('broadcast_permission_granted_at', sa.DateTime(timezone=True), nullable=True))
        batch_op.create_foreign_key(
            'fk_users_broadcast_permission_granted_by',
            'users',
            ['broadcast_permission_granted_by_id'],
            ['id'],
        )

    op.create_table(
        'live_broadcasts',
        sa.Column('id', sa.BigInteger(), primary_key=True),
        sa.Column('uuid', sa.String(length=36), nullable=False, unique=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('meta_data', sa.JSON(), nullable=True),
        sa.Column('user_id', sa.BigInteger(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('platform', sa.String(length=20), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=True),
        sa.Column('stream_ref', sa.String(length=500), nullable=True),
        sa.Column('is_live', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('ended_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('mux_stream_id', sa.String(length=100), nullable=True),
        sa.Column('mux_stream_key', sa.String(length=200), nullable=True),
        sa.Column('mux_playback_id', sa.String(length=100), nullable=True),
        sa.CheckConstraint("platform IN ('youtube', 'facebook', 'native')", name='ck_live_broadcast_platform'),
    )
    op.create_index('ix_live_broadcasts_user_live', 'live_broadcasts', ['user_id', 'is_live'])
    op.create_index('ix_live_broadcasts_is_live', 'live_broadcasts', ['is_live'])


def downgrade():
    op.drop_index('ix_live_broadcasts_is_live', table_name='live_broadcasts')
    op.drop_index('ix_live_broadcasts_user_live', table_name='live_broadcasts')
    op.drop_table('live_broadcasts')

    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_constraint('fk_users_broadcast_permission_granted_by', type_='foreignkey')
        batch_op.drop_column('broadcast_permission_granted_at')
        batch_op.drop_column('broadcast_permission_granted_by_id')
        batch_op.drop_column('can_go_live')
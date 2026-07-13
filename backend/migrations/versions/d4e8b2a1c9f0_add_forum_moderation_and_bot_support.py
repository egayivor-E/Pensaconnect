"""Add forum pin/lock, user is_bot flag, and forum_reports table

Revision ID: d4e8b2a1c9f0
Revises: a1b2c3d4e5f6
Create Date: 2026-07-13 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'd4e8b2a1c9f0'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade():
    # --- forum_threads: pin/lock moderation controls ---
    with op.batch_alter_table('forum_threads', schema=None) as batch_op:
        batch_op.add_column(sa.Column('is_pinned', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('is_locked', sa.Boolean(), nullable=False, server_default=sa.false()))

    # --- users: is_bot flag for the forum assistant service account ---
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('is_bot', sa.Boolean(), nullable=False, server_default=sa.false()))

    # --- forum_reports: report/flag queue for posts and comments ---
    op.create_table(
        'forum_reports',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('uuid', sa.String(length=36), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('meta_data', sa.JSON(), nullable=True),
        sa.Column('reporter_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('post_id', sa.Integer(), sa.ForeignKey('forum_posts.id'), nullable=True),
        sa.Column('comment_id', sa.Integer(), sa.ForeignKey('forum_comments.id'), nullable=True),
        sa.Column('reason', sa.String(length=255), nullable=True),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='open'),
        sa.Column('resolved_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint('uuid'),
        sa.UniqueConstraint('reporter_id', 'post_id', name='uq_reporter_post_report'),
        sa.UniqueConstraint('reporter_id', 'comment_id', name='uq_reporter_comment_report'),
    )
    op.create_index('ix_forum_reports_status', 'forum_reports', ['status'])


def downgrade():
    op.drop_index('ix_forum_reports_status', table_name='forum_reports')
    op.drop_table('forum_reports')

    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_column('is_bot')

    with op.batch_alter_table('forum_threads', schema=None) as batch_op:
        batch_op.drop_column('is_locked')
        batch_op.drop_column('is_pinned')
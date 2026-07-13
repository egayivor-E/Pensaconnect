"""Add timeline_posts table

Revision ID: b3e1f9a2c7d4
Revises: d4e8b2a1c9f0
Create Date: 2026-07-13 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b3e1f9a2c7d4'
down_revision = 'd4e8b2a1c9f0'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'timeline_posts',
        sa.Column('uuid', sa.String(length=36), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False),
        sa.Column('meta_data', sa.JSON(), nullable=True),
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('image_url', sa.String(length=500), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('uuid'),
    )


def downgrade():
    op.drop_table('timeline_posts')
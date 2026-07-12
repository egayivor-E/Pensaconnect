"""Add image_url to activities

Revision ID: f3a9c1d2e4b6
Revises: 9a1f5e3c7b2d
Create Date: 2026-07-12 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f3a9c1d2e4b6'
down_revision = '9a1f5e3c7b2d'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('activities', schema=None) as batch_op:
        batch_op.add_column(sa.Column('image_url', sa.String(length=500), nullable=True))


def downgrade():
    with op.batch_alter_table('activities', schema=None) as batch_op:
        batch_op.drop_column('image_url')

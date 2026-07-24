"""Add source_type/source_id to archives

Revision ID: a2b4c6d8e0f1
Revises: e1a2b3c4d5f6
Create Date: 2026-07-24 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a2b4c6d8e0f1'
down_revision = 'e1a2b3c4d5f6'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('archives', schema=None) as batch_op:
        # Nullable: existing rows (and archives created directly via
        # POST /bible/archives with no underlying record) have no source
        # to link back to.
        batch_op.add_column(sa.Column('source_type', sa.String(length=20), nullable=True))
        batch_op.add_column(sa.Column('source_id', sa.BigInteger(), nullable=True))


def downgrade():
    with op.batch_alter_table('archives', schema=None) as batch_op:
        batch_op.drop_column('source_id')
        batch_op.drop_column('source_type')
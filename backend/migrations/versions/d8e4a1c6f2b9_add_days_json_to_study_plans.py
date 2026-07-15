"""Add days_json to study_plans

Revision ID: d8e4a1c6f2b9
Revises: a4f1c9d8e2b7
Create Date: 2026-07-16 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'd8e4a1c6f2b9'
down_revision = 'a4f1c9d8e2b7'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('study_plans', schema=None) as batch_op:
        batch_op.add_column(sa.Column('days_json', sa.Text(), nullable=True))


def downgrade():
    with op.batch_alter_table('study_plans', schema=None) as batch_op:
        batch_op.drop_column('days_json')

"""Add indexes on foreign-key columns that were missing them

Unlike primary keys, Postgres does NOT automatically index foreign key
columns. Almost every hot-path query in this app filters or joins on one
of these columns (ForumPost.thread_id, GroupMessage.group_chat_id,
Activity.user_id, ForumComment.post_id, TestimonyComment.testimony_id,
...), so without an index each of those lookups is a sequential scan
that gets slower as each table grows. This migration adds a plain
b-tree index to every FK column that didn't already have one (via
index=True or an existing composite Index()).

Revision ID: a4f1c9d8e2b7
Revises: ea5c7b9132ee
Create Date: 2026-07-16 00:00:00.000001

"""
from alembic import op


# revision identifiers, used by Alembic.
revision = 'a4f1c9d8e2b7'
down_revision = 'ea5c7b9132ee'
branch_labels = None
depends_on = None


# (table_name, column_name) pairs, one CREATE INDEX per FK column that
# wasn't already covered.
FK_COLUMNS = [
    ("post_categories", "parent_id"),
    ("posts", "approved_by_id"),
    ("posts", "user_id"),
    ("posts", "thread_id"),
    ("prayer_requests", "user_id"),
    ("prayers", "prayer_request_id"),
    ("comments", "user_id"),
    ("comments", "event_id"),
    ("comments", "parent_id"),
    ("reactions", "post_id"),
    ("reactions", "comment_id"),
    ("events", "user_id"),
    ("events", "event_type_id"),
    ("event_attendees", "event_id"),
    ("event_reminders", "event_id"),
    ("resources", "user_id"),
    ("resources", "resource_type_id"),
    ("notifications", "notification_type_id"),
    ("donation_notifications", "recipient_id"),
    ("activities", "user_id"),
    ("messages", "sender_id"),
    ("study_plan_progresses", "plan_id"),
    ("archives", "author_id"),
    ("forum_threads", "category_id"),
    ("forum_threads", "author_id"),
    ("forum_posts", "thread_id"),
    ("forum_posts", "author_id"),
    ("forum_comments", "post_id"),
    ("forum_comments", "author_id"),
    ("forum_attachments", "post_id"),
    ("forum_attachments", "comment_id"),
    ("forum_likes", "user_id"),
    ("forum_likes", "post_id"),
    ("forum_likes", "thread_id"),
    ("forum_reports", "reporter_id"),
    ("forum_reports", "post_id"),
    ("forum_reports", "comment_id"),
    ("forum_reports", "resolved_by_id"),
    ("testimonies", "user_id"),
    ("testimony_comments", "testimony_id"),
    ("testimony_comments", "user_id"),
    ("testimony_likes", "testimony_id"),
    ("testimony_likes", "user_id"),
    ("group_chats", "created_by_id"),
    ("group_members", "group_chat_id"),
    ("group_messages", "replied_to_id"),
    ("timeline_posts", "user_id"),
]


def _index_name(table, column):
    return f"ix_{table}_{column}"


def upgrade():
    bind = op.get_bind()
    inspector = None
    try:
        from sqlalchemy import inspect
        inspector = inspect(bind)
    except Exception:
        inspector = None

    for table, column in FK_COLUMNS:
        name = _index_name(table, column)
        # Defensive: skip cleanly if the table/column doesn't exist in a
        # given environment (e.g. a partially-migrated dev DB), and skip
        # if something already created this exact index name, instead of
        # failing the whole migration partway through.
        if inspector is not None:
            try:
                existing = {ix["name"] for ix in inspector.get_indexes(table)}
            except Exception:
                existing = set()
            if name in existing:
                continue
        try:
            op.create_index(name, table, [column])
        except Exception:
            # Best-effort: don't let one missing table/column (schema
            # drift between environments) block the rest of the index
            # additions.
            pass


def downgrade():
    for table, column in FK_COLUMNS:
        name = _index_name(table, column)
        try:
            op.drop_index(name, table_name=table)
        except Exception:
            pass

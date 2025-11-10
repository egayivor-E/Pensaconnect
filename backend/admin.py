from flask import redirect, request, flash, url_for
from flask_admin import Admin, AdminIndexView, expose
from flask_admin.contrib.sqla import ModelView
from flask_login import current_user
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from wtforms import validators
from backend.extensions import db
from backend.models import (
    User, Role, Activity, PrayerRequest, Prayer, Comment, Reaction, PrayerStatus,
    Post, PostCategory, Devotion, StudyPlan, StudyPlanProgress, Archive,
    Event, EventType, EventAttendee, EventReminder,
    Resource, ResourceType,
    Notification, NotificationType, Donation, DonationNotification,
    Testimony, TestimonyComment, TestimonyLike,
    GroupChat, GroupMember, GroupMessage,
    ForumCategory, ForumThread, ForumPost, ForumComment, ForumAttachment, ForumLike
)

from wtforms.fields.core import UnboundField

_original_bind = UnboundField.bind

def patched_bind(self, form=None, **kwargs):
    if 'flags' in kwargs and isinstance(kwargs['flags'], tuple):
        print(f"[DEBUG] Patched UnboundField.bind: converting flags tuple to dict for {self.field_class.__name__}")
        kwargs['flags'] = {}
    return _original_bind(self, form=form, **kwargs)


# ---------------------------------------------------
# Secure AdminIndexView
# ---------------------------------------------------
class SecureAdminIndexView(AdminIndexView):
    @expose("/")
    def index(self):
        if not current_user.is_authenticated or not current_user.has_role("admin"):
            flash("You must be an admin to access this area.", "error")
            return redirect(url_for("admin_auth.admin_login"))
        return super().index()

    def is_accessible(self):
        return current_user.is_authenticated and current_user.has_role("admin")

    def inaccessible_callback(self, name, **kwargs):
        flash("Please log in as an admin to continue.", "error")
        return redirect(url_for("admin_auth.admin_login"))

# ---------------------------------------------------
# SafeModelView (Base)
# ---------------------------------------------------
class SafeModelView(ModelView):
    can_create = True
    can_edit = True
    can_delete = True
    can_view_details = True
    create_modal = True
    edit_modal = True
    column_display_pk = True
    page_size = 30
    column_hide_backrefs = False
    form_excluded_columns = [
        "meta_data", "uuid", "created_at", "updated_at", "is_active"
    ]

    def is_accessible(self):
        return current_user.is_authenticated and current_user.has_role("admin")

    def inaccessible_callback(self, name, **kwargs):
        flash("You are not authorized to view this page.", "error")
        return redirect(url_for("admin_auth.admin_login"))

    def handle_view_exception(self, exc):
        db.session.rollback()
        if isinstance(exc, (IntegrityError, SQLAlchemyError, ValueError)):
            flash(f"Database error: {exc}", "error")
            return redirect(request.url)
        return super().handle_view_exception(exc)

# ---------------------------------------------------
# Individual Model Admins
class UserAdmin(SafeModelView):
    column_list = ["id", "username", "email", "first_name", "last_name", "status", "is_premium", "created_at"]

    form_excluded_columns = SafeModelView.form_excluded_columns + [
        "password_hash", "roles", "posts", "notifications", "messages",
        "comments", "prayer_requests", "resources", "group_messages",
        "activities", "forum_threads", "forum_posts", "forum_comments"
    ]

    form_args = {
        "email": {
            "validators": [validators.DataRequired(), validators.Email()]
        },
        "username": {
            "validators": [validators.DataRequired(), validators.Length(min=3, max=80)]
        },
    }

    def scaffold_form(self):
        form_class = super().scaffold_form()

        # Defensive check: skip if form_class is None or lacks _unbound_fields
        if not form_class or not hasattr(form_class, "_unbound_fields") or form_class._unbound_fields is None:
            return form_class

        cleaned_fields = []
        for name, unbound_field in form_class._unbound_fields:
            flags = unbound_field.kwargs.get("flags")
            if isinstance(flags, tuple):
                print(f"⚠️ Removing tuple flags from field '{name}' before binding")
                unbound_field.kwargs.pop("flags")
            cleaned_fields.append((name, unbound_field))

        form_class._unbound_fields = cleaned_fields
        return form_class

    def create_form(self, obj=None):
        form = super().create_form(obj)
        for name, field in form._fields.items():
            print(f"{name}: {type(field)}, flags={getattr(field, 'flags', None)}")
        return form

class RoleAdmin(SafeModelView):
    column_list = ["id", "name"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["users"]

class PostAdmin(SafeModelView):
    column_list = ["id", "title", "user_id", "is_approved", "created_at"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["comments", "reactions"]
    form_args = {
        "title": {"validators": [validators.DataRequired()]},
        "content": {"validators": [validators.DataRequired()]},
    }

class PrayerRequestAdmin(SafeModelView):
    column_list = ["id", "title", "category", "status_id", "user_id", "is_public", "created_at"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["prayers", "comments"]

class EventAdmin(SafeModelView):
    column_list = ["id", "title", "start_time", "end_time", "user_id", "event_type_id"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["attendees", "reminders", "comments"]

class ResourceAdmin(SafeModelView):
    column_list = ["id", "title", "url", "resource_type_id", "user_id"]
    form_excluded_columns = SafeModelView.form_excluded_columns
    form_args = {"url": {"validators": [validators.DataRequired(), validators.URL()]}}

class NotificationAdmin(SafeModelView):
    column_list = ["id", "user_id", "title", "is_read", "notification_type_id"]
    form_excluded_columns = SafeModelView.form_excluded_columns

class TestimonyAdmin(SafeModelView):
    column_list = ["id", "title", "user_id", "is_anonymous", "created_at"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["comments", "likes"]

class GroupChatAdmin(SafeModelView):
    column_list = ["id", "name", "is_public", "max_members", "created_by_id"]
    form_excluded_columns = SafeModelView.form_excluded_columns + ["members", "messages"]

class GroupMemberAdmin(SafeModelView):
    column_list = ["id", "group_chat_id", "user_id", "group_role", "joined_at"]

class GroupMessageAdmin(SafeModelView):
    column_list = ["id", "group_chat_id", "sender_id", "content", "created_at"]

# ---------------------------------------------------
# Build Admin Panel
# ---------------------------------------------------
admin = Admin(
    name="PensaConnect Admin",
    index_view=SecureAdminIndexView()
)

# --- User Management ---
admin.add_view(UserAdmin(User, db.session, category="👤 User Management"))
admin.add_view(RoleAdmin(Role, db.session, category="👤 User Management"))
admin.add_view(SafeModelView(Activity, db.session, category="👤 User Management"))

# --- Faith & Content ---
admin.add_view(PostAdmin(Post, db.session, category="✝️ Faith & Content"))
admin.add_view(SafeModelView(PostCategory, db.session, category="✝️ Faith & Content"))
admin.add_view(SafeModelView(Devotion, db.session, category="✝️ Faith & Content"))
admin.add_view(SafeModelView(StudyPlan, db.session, category="✝️ Faith & Content"))
admin.add_view(SafeModelView(StudyPlanProgress, db.session, category="✝️ Faith & Content"))
admin.add_view(SafeModelView(Archive, db.session, category="✝️ Faith & Content"))
admin.add_view(TestimonyAdmin(Testimony, db.session, category="✝️ Faith & Content"))

# --- Prayer ---
admin.add_view(PrayerRequestAdmin(PrayerRequest, db.session, category="🙏 Prayer"))
admin.add_view(SafeModelView(Prayer, db.session, category="🙏 Prayer"))
admin.add_view(SafeModelView(PrayerStatus, db.session, category="🙏 Prayer"))

# --- Events & Donations ---
admin.add_view(EventAdmin(Event, db.session, category="🕊️ Events & Donations"))
admin.add_view(SafeModelView(EventType, db.session, category="🕊️ Events & Donations"))
admin.add_view(SafeModelView(EventAttendee, db.session, category="🕊️ Events & Donations"))
admin.add_view(SafeModelView(EventReminder, db.session, category="🕊️ Events & Donations"))
admin.add_view(SafeModelView(Donation, db.session, category="🕊️ Events & Donations"))
admin.add_view(SafeModelView(DonationNotification, db.session, category="🕊️ Events & Donations"))

# --- Resources ---
admin.add_view(ResourceAdmin(Resource, db.session, category="📚 Resources"))
admin.add_view(SafeModelView(ResourceType, db.session, category="📚 Resources"))

# --- Notifications ---
admin.add_view(NotificationAdmin(Notification, db.session, category="🔔 Notifications"))
admin.add_view(SafeModelView(NotificationType, db.session, category="🔔 Notifications"))

# --- Groups & Chat ---
admin.add_view(GroupChatAdmin(GroupChat, db.session, category="💬 Groups & Chat"))
admin.add_view(GroupMemberAdmin(GroupMember, db.session, category="💬 Groups & Chat"))
admin.add_view(GroupMessageAdmin(GroupMessage, db.session, category="💬 Groups & Chat"))

# --- Forum ---
admin.add_view(SafeModelView(ForumCategory, db.session, category="🗣️ Forum"))
admin.add_view(SafeModelView(ForumThread, db.session, category="🗣️ Forum"))
admin.add_view(SafeModelView(ForumPost, db.session, category="🗣️ Forum"))
admin.add_view(SafeModelView(ForumComment, db.session, category="🗣️ Forum"))
admin.add_view(SafeModelView(ForumAttachment, db.session, category="🗣️ Forum"))
admin.add_view(SafeModelView(ForumLike, db.session, category="🗣️ Forum"))
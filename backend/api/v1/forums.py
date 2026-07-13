from math import ulp
import os
import logging
import uuid
from functools import wraps

from flask import Blueprint, request, send_file
from flask.views import MethodView
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash

from backend.extensions import db
from backend.models import (
    ForumThread,
    ForumPost,
    ForumComment,
    ForumAttachment,
    ForumCategory,
    ForumLike,
    ForumReport,
    User,
    Activity,
    Notification,
    NotificationType,
)
from .ai_assistant import generate_assistant_reply, AssistantError
from backend.supabase_client import (
    upload_file_to_supabase,
    delete_file_from_supabase,
    FORUM_MEDIA_BUCKET,
)
from .utils import success_response, error_response, broadcast_new_activity

logger = logging.getLogger(__name__)

forums_bp = Blueprint("forums", __name__, url_prefix="/forums")

# Legacy local folder — still referenced when serving attachments that were
# uploaded before the Supabase migration (see get_attachment below).
UPLOAD_FOLDER = "uploads/forum"
IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
VIDEO_EXTENSIONS = {"mp4", "mov", "avi", "webm", "mkv", "m4v"}
DOCUMENT_EXTENSIONS = {"pdf", "docx", "txt"}
ALLOWED_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS | DOCUMENT_EXTENSIONS

CONTENT_TYPES = {
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "gif": "image/gif", "webp": "image/webp",
    "mp4": "video/mp4", "mov": "video/quicktime", "avi": "video/x-msvideo",
    "webm": "video/webm", "mkv": "video/x-matroska", "m4v": "video/x-m4v",
    "pdf": "application/pdf",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "txt": "text/plain",
}


# ------------------------ Helpers ------------------------

def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

def _extension(filename: str) -> str:
    return filename.rsplit(".", 1)[1].lower() if "." in filename else ""

def is_image_file(filename: str) -> bool:
    return _extension(filename) in IMAGE_EXTENSIONS

def is_video_file(filename: str) -> bool:
    return _extension(filename) in VIDEO_EXTENSIONS

def _save_attachment_file(f, subfolder: str) -> tuple[str, str]:
    """
    Uploads a single werkzeug FileStorage to Supabase Storage.
    Returns (public_url, storage_path). Raises on failure — callers
    should let this propagate so the request fails loudly instead of
    silently creating an attachment row that points at nothing.
    """
    filename = secure_filename(f.filename)
    ext = _extension(filename)
    unique_name = f"{uuid.uuid4()}_{filename}"
    destination_path = f"{subfolder}/{unique_name}"
    content_type = CONTENT_TYPES.get(ext, f.mimetype or "application/octet-stream")

    file_bytes = f.read()
    public_url = upload_file_to_supabase(
        file_bytes=file_bytes,
        destination_path=destination_path,
        content_type=content_type,
        bucket=FORUM_MEDIA_BUCKET,
    )
    return public_url, destination_path

def paginate_query(query):
    """Helper for pagination with consistent response format"""
    page = request.args.get("page", default=1, type=int)
    per_page = request.args.get("per_page", default=10, type=int)
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    return {
        "items": [item.to_dict() for item in pagination.items],
        "total": pagination.total,
        "page": pagination.page,
        "pages": pagination.pages,
    }

def get_current_user() -> User:
    return User.query.get(get_jwt_identity())

def user_has_role(user: User, role_name: str) -> bool:
    # assumes User.roles relationship exists
    return any(r.name == role_name for r in (user.roles or []))

def is_staff(user: User) -> bool:
    # centralize the notion of “staff” who can moderate
    return user_has_role(user, "admin") or user_has_role(user, "moderator")

def can_manage(author_id: int, user: User) -> bool:
    # author can manage their own; staff can manage any
    return user and (author_id == user.id or is_staff(user))

def roles_required(*roles):
    """Decorator to require at least one role"""
    def wrapper(fn):
        @wraps(fn)
        @jwt_required()
        def decorated(*args, **kwargs):
            current_user = get_current_user()
            if not current_user or not any(user_has_role(current_user, r) for r in roles):
                return error_response("Unauthorized", 403)
            return fn(*args, **kwargs)
        return decorated
    return wrapper


BOT_USERNAME = "pensa_assistant"


def get_or_create_bot_user() -> User:
    """The single service account the AI assistant posts/comments as.

    Lazily created on first use rather than seeded, so environments that
    never touch the assistant feature never get a stray account. Always
    is_bot=True and locked (unusable) for normal login — it's never meant
    to authenticate, only to be a foreign key target for authored content.
    """
    bot = User.query.filter_by(username=BOT_USERNAME).first()
    if bot:
        return bot

    bot = User(
        username=BOT_USERNAME,
        email="assistant@pensaconnect.local",
        password_hash=generate_password_hash(uuid.uuid4().hex),
        first_name="Pensa",
        last_name="Assistant",
        email_verified=True,
        is_bot=True,
        status="active",
    )
    db.session.add(bot)
    db.session.commit()
    return bot


def get_or_create_notification_type(name: str):
    from backend.models import NotificationType as NT
    nt = NT.query.filter_by(name=name).first()
    if nt:
        return nt
    nt = NT(name=name)
    db.session.add(nt)
    db.session.commit()
    return nt


def notify_reply(*, recipient_id: int, actor_name: str, thread_id: int, post_id: int, is_bot: bool = False):
    """Notify a post's author that someone replied to it. Best-effort and
    isolated (own try/except) for the same reason broadcast_new_activity
    is — a notification hiccup must never fail the comment that triggered
    it, and it must never fire for someone replying to themselves."""
    try:
        nt = get_or_create_notification_type("forum_reply")
        title = "The assistant replied to your post" if is_bot else "New reply to your post"
        notification = Notification(
            user_id=recipient_id,
            notification_type_id=nt.id,
            title=title,
            message=f"{actor_name} replied to your post.",
            action_url=f"/threads/{thread_id}?post={post_id}",
            action_label="View reply",
            source_id=post_id,
        )
        db.session.add(notification)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        logger.error(f"Failed to create reply notification: {e}")


def thread_is_locked_for(thread: "ForumThread", user: User) -> bool:
    return bool(thread.is_locked) and not is_staff(user)


# ------------------------ CATEGORIES ------------------------

@forums_bp.route("/categories", methods=["GET"])
def get_categories():
    categories = ForumCategory.query.all()
    return success_response([c.to_dict() for c in categories])

@forums_bp.route("/categories", methods=["POST"])
@roles_required("admin", "moderator")
def create_category():
    data = request.get_json() or {}
    name = (data.get("name") or "").strip().lower()
    if not name:
        return error_response("Category name is required", 400)

    if ForumCategory.query.filter_by(name=name).first():
        return error_response("Category already exists", 400)

    category = ForumCategory(name=name)
    db.session.add(category)
    db.session.commit()
    return success_response(category.to_dict(), 201)


# ------------------------ THREADS ------------------------

@forums_bp.route("/threads", methods=["GET"])
def get_threads():
    """
    Query params:
      q     - optional search string, matched against title/description
      sort  - "newest" (default), "active" (most posts), or "liked"
      limit - cap on rows returned (default 100, max 200) — a real
              cursor/page param can replace this once thread volume
              actually warrants it; for now this just stops an
              unbounded SELECT * as the forum grows.
    Pinned threads always sort first, regardless of `sort`.
    """
    query = ForumThread.query

    q = (request.args.get("q") or "").strip()
    if q:
        like = f"%{q}%"
        query = query.filter(
            db.or_(ForumThread.title.ilike(like), ForumThread.description.ilike(like))
        )

    sort = request.args.get("sort", default="newest")
    if sort == "liked":
        # Correlated subquery keeps this a single query instead of N+1s.
        like_count_sq = (
            db.session.query(db.func.count(ForumLike.id))
            .filter(ForumLike.thread_id == ForumThread.id, ForumLike.reaction_type == "like")
            .correlate(ForumThread)
            .scalar_subquery()
        )
        query = query.order_by(ForumThread.is_pinned.desc(), like_count_sq.desc())
    elif sort == "active":
        query = query.outerjoin(ForumThread.forum_posts).group_by(ForumThread.id).order_by(
            ForumThread.is_pinned.desc(), db.func.count(ForumPost.id).desc()
        )
    else:
        query = query.order_by(ForumThread.is_pinned.desc(), ForumThread.created_at.desc())

    limit = min(request.args.get("limit", default=100, type=int) or 100, 200)
    threads = query.limit(limit).all()
    return success_response([t.to_dict() for t in threads])

@forums_bp.route("/threads/<int:thread_id>", methods=["GET"])
def get_thread(thread_id):
    thread = ForumThread.query.get_or_404(thread_id)
    return success_response(thread.to_dict(include_posts=True))

@forums_bp.route("/threads", methods=["POST"])
@jwt_required()
def create_thread():
    data = request.get_json() or {}
    title = (data.get("title") or "").strip()
    if not title:
        return error_response("Thread title is required", 400)

    current_user = get_current_user()

    thread = ForumThread(
        title=title,
        category_id=data.get("category_id"),
        author_id=current_user.id,
        description=data.get("description"),
        # Only staff can start a thread pre-pinned; a regular member
        # sending `is_pinned: true` is silently ignored, not errored,
        # since it's not something they need to know is even a field.
        is_pinned=bool(data.get("is_pinned")) if is_staff(current_user) else False,
    )
    db.session.add(thread)
    db.session.commit()

    # Activity feed logging — matches the pattern used in posts.py/testimonies.py.
    # Thread creation is the only forum event logged to the feed (see discussion:
    # individual post replies are deliberately excluded to avoid flooding it).
    # No anonymity concern here (unlike testimonies/prayers), so no skip-logic
    # is needed — thread.author_id is always attributable.
    # Wrapped in its own try/except and committed separately so a logging
    # failure (bad enum value, DB hiccup) can't roll back or fail the
    # already-successful thread creation.
    try:
        activity = Activity(
            title=f"{current_user.get_full_name()} started a new discussion",
            subtitle=(thread.description or thread.title)[:140],
            icon="forum",
            color="orange",
            user_id=current_user.id,
            target_type="forum_thread",
            target_id=thread.id,
        )
        db.session.add(activity)
        db.session.commit()
        broadcast_new_activity(activity)
    except Exception:
        logger.exception("Failed to log activity for thread %s", thread.id)
        db.session.rollback()

    return success_response(thread.to_dict(), 201)

@forums_bp.route("/threads/<int:thread_id>/react", methods=["POST"])
@jwt_required()
def react_to_thread(thread_id):
    """Toggle like or dislike for a thread."""
    thread = ForumThread.query.get_or_404(thread_id)
    current_user = get_current_user()

    # ✅ Ensure both JSON and form requests work
    data = request.get_json(silent=True) or request.form.to_dict()
    reaction_type = data.get("type", "like")  # client sends `type` field

    if reaction_type not in ["like", "dislike"]:
        return error_response("Invalid reaction type", 400)

    # Check if user already reacted with this type
    existing = ForumLike.query.filter_by(
        user_id=current_user.id,
        thread_id=thread.id,
        reaction_type=reaction_type,
    ).first()

    if existing:
        # Remove the reaction (toggle off)
        db.session.delete(existing)
        db.session.commit()
        return success_response({
            "message": f"{reaction_type.capitalize()} removed",
            "reaction_type": reaction_type,
            "liked": False,
            "likes_count": ForumLike.query.filter_by(thread_id=thread.id, reaction_type="like").count(),
            "dislikes_count": ForumLike.query.filter_by(thread_id=thread.id, reaction_type="dislike").count(),
        })

    # Remove opposite reaction if exists
    opposite = "dislike" if reaction_type == "like" else "like"
    opposite_reaction = ForumLike.query.filter_by(
        user_id=current_user.id,
        thread_id=thread.id,
        reaction_type=opposite,
    ).first()
    if opposite_reaction:
        db.session.delete(opposite_reaction)

    # Add new reaction
    new_reaction = ForumLike(
        user_id=current_user.id,
        thread_id=thread.id,
        reaction_type=reaction_type,
    )
    db.session.add(new_reaction)
    db.session.commit()

    return success_response({
        "message": f"{reaction_type.capitalize()} added",
        "reaction_type": reaction_type,
        "liked": True,
        "likes_count": ForumLike.query.filter_by(thread_id=thread.id, reaction_type="like").count(),
        "dislikes_count": ForumLike.query.filter_by(thread_id=thread.id, reaction_type="dislike").count(),
    })




@forums_bp.route("/threads/<int:thread_id>", methods=["PATCH"])
@jwt_required()
def update_thread(thread_id):
    thread = ForumThread.query.get_or_404(thread_id)
    current_user = get_current_user()

    if not can_manage(thread.author_id, current_user):
        return error_response("Unauthorized", 403)

    data = request.get_json() or {}
    if "title" in data and data["title"]:
        thread.title = data["title"].strip()
    if "description" in data:
        thread.description = data["description"]

    # Pin/lock are moderation-only, regardless of whether this particular
    # requester is allowed to edit title/description as the thread's own
    # author — can_manage() above already let authors through, but pin/
    # lock is a step above "manage your own content".
    if is_staff(current_user):
        if "is_pinned" in data:
            thread.is_pinned = bool(data["is_pinned"])
        if "is_locked" in data:
            thread.is_locked = bool(data["is_locked"])

    db.session.commit()
    return success_response(thread.to_dict())

@forums_bp.route("/threads/<int:thread_id>", methods=["DELETE"])
@jwt_required()
def delete_thread(thread_id):
    thread = ForumThread.query.get_or_404(thread_id)
    current_user = get_current_user()

    if not can_manage(thread.author_id, current_user):
        return error_response("Unauthorized", 403)

    db.session.delete(thread)
    db.session.commit()
    return success_response({"message": "Thread deleted"})


# ------------------------ POSTS ------------------------

@forums_bp.route("/posts", methods=["GET"])
def get_posts():
    thread_id = request.args.get("thread_id", type=int)
    query = ForumPost.query
    if thread_id:
        query = query.filter_by(thread_id=thread_id)

    query = query.order_by(ForumPost.created_at.desc())
    return success_response(paginate_query(query))

@forums_bp.route("/posts/<int:post_id>", methods=["GET"])
def get_post(post_id):
    post = ForumPost.query.get_or_404(post_id)
    return success_response(post.to_dict())

@forums_bp.route("/posts", methods=["POST"])
@jwt_required()
def create_post():
    current_user = get_current_user()

    # Debug logs help while integrating web/mobile client payloads
    print("📥 Raw JSON body:", request.get_json(silent=True))
    print("📥 Raw FORM body:", request.form.to_dict())
    print("📥 Content-Type:", request.content_type)

    # Multipart form
    if request.content_type and request.content_type.startswith("multipart/form-data"):
        title = (request.form.get("title") or "").strip()
        content = request.form.get("content")
        thread_id = request.form.get("thread_id", type=int)

        if not title or not content or not thread_id:
            return error_response("title, content and thread_id required", 400)

        thread = ForumThread.query.get(thread_id)
        if not thread:
            return error_response("Thread does not exist", 400)
        if thread_is_locked_for(thread, current_user):
            return error_response("This thread is locked and no longer accepting posts", 403)

        post = ForumPost(
            thread_id=thread.id,
            author_id=current_user.id,
            title=title,
            content=content,
        )
        db.session.add(post)
        db.session.flush()  # get post.id for attachments

        # ✅ Track upload failures instead of silently `continue`-ing past
        # them. Previously a failed Supabase upload (missing bucket, bad
        # creds, network hiccup) just vanished — the post still saved
        # successfully with zero attachments and nothing told the client
        # an image was dropped. Now every failure is recorded and handed
        # back in the response so the UI can surface it.
        attachment_errors = []
        if "files" in request.files:
            for f in request.files.getlist("files"):
                if not f.filename:
                    continue
                if not allowed_file(f.filename):
                    attachment_errors.append(
                        {"file_name": f.filename, "error": "Unsupported file type"}
                    )
                    continue
                filename = secure_filename(f.filename)
                try:
                    public_url, storage_path = _save_attachment_file(f, "posts")
                except Exception as e:
                    logger.error(f"Forum attachment upload failed: {e}")
                    attachment_errors.append(
                        {"file_name": f.filename, "error": str(e)}
                    )
                    continue
                attachment = ForumAttachment(
                    file_url=public_url,
                    file_type=f.mimetype,
                    post_id=post.id,
                    # file_path now holds the Supabase storage path
                    # (bucket-relative), not a local disk path — used
                    # for deletion cleanup, not for serving.
                    file_path=storage_path,
                    file_name=filename,
                    mime_type=f.mimetype,
                )
                db.session.add(attachment)

        db.session.commit()

        # ✅ Log + broadcast an Activity so this post shows up in the live
        # Home feed. If there's a video attachment, that becomes the
        # feed card's "reel" (autoplaying video); otherwise the first
        # image (if any) becomes a static thumbnail. Both ride along in
        # meta_data — no schema change needed. thread_id always rides
        # along too (not just when media is present) so every "post"
        # activity can deep-link back to the thread it lives in.
        first_image = next(
            (a for a in post.attachments if is_image_file(a.file_name)), None
        )
        first_video = next(
            (a for a in post.attachments if is_video_file(a.file_name)), None
        )
        media_meta = {"thread_id": post.thread_id}
        if first_video:
            media_meta["video_url"] = first_video.to_dict()["url"]
        if first_image:
            media_meta["image_url"] = first_image.to_dict()["url"]

        activity = Activity(
            title=f"{current_user.get_full_name()} shared a new post",
            subtitle=(post.content or post.title)[:140],
            icon="forum",
            color="blue",
            user_id=current_user.id,
            target_type="post",
            target_id=post.id,
            meta_data=media_meta,
        )
        db.session.add(activity)
        db.session.commit()
        broadcast_new_activity(activity)

        response_data = post.to_dict(include_attachments=True)
        if attachment_errors:
            response_data["attachment_errors"] = attachment_errors

        # FIX: Change from 200 to 201
        return success_response(response_data, 201)  # ✅ Changed to 201

    # JSON body
    data = request.get_json() or {}
    title = (data.get("title") or "").strip()
    content = data.get("content")
    thread_id = data.get("thread_id")

    if not title or not content or not thread_id:
        return error_response("title, content and thread_id required", 400)

    thread = ForumThread.query.get(thread_id)
    if not thread:
        return error_response("Thread does not exist", 400)
    if thread_is_locked_for(thread, current_user):
        return error_response("This thread is locked and no longer accepting posts", 403)

    post = ForumPost(
        thread_id=thread.id,
        author_id=current_user.id,
        title=title,
        content=content,
    )
    db.session.add(post)
    db.session.commit()

    activity = Activity(
        title=f"{current_user.get_full_name()} shared a new post",
        subtitle=(post.content or post.title)[:140],
        icon="forum",
        color="blue",
        user_id=current_user.id,
        target_type="post",
        target_id=post.id,
        meta_data={"thread_id": post.thread_id},
    )
    db.session.add(activity)
    db.session.commit()
    broadcast_new_activity(activity)

    # FIX: Already 201 here, but keep it
    return success_response(post.to_dict(), 201)  # ✅ Already correct

@forums_bp.route("/posts/<int:post_id>", methods=["PATCH"])
@jwt_required()
def update_post(post_id):
    post = ForumPost.query.get_or_404(post_id)
    current_user = get_current_user()

    if not can_manage(post.author_id, current_user):
        return error_response("Unauthorized", 403)

    data = request.get_json() or {}
    if "title" in data and data["title"]:
        post.title = data["title"].strip()
    if "content" in data:
        post.content = data["content"]

    db.session.commit()
    return success_response(post.to_dict())

@forums_bp.route("/posts/<int:post_id>", methods=["DELETE"])
@jwt_required()
def delete_post(post_id):
    post = ForumPost.query.get_or_404(post_id)
    current_user = get_current_user()

    if not can_manage(post.author_id, current_user):
        return error_response("Unauthorized", 403)

    db.session.delete(post)
    db.session.commit()
    return success_response({"message": "Post deleted"})

@forums_bp.route("/posts/<int:post_id>/like", methods=["POST"])
@jwt_required()
def toggle_like(post_id):
    post = ForumPost.query.get_or_404(post_id)
    current_user = get_current_user()

    like = ForumLike.query.filter_by(user_id=current_user.id, post_id=post.id).first()
    if like:
        db.session.delete(like)  # unlike
    else:
        like = ForumLike(user_id=current_user.id, post_id=post.id)
        db.session.add(like)

    db.session.commit()
    return success_response(post.to_dict())


# ------------------------ COMMENTS ------------------------




@forums_bp.route("/posts/<int:post_id>/comments", methods=["GET"])
def get_comments(post_id):
    query = ForumComment.query.filter_by(post_id=post_id).order_by(ForumComment.created_at.asc())
    return success_response(paginate_query(query))

@forums_bp.route("/posts/<int:post_id>/comments", methods=["POST"])
@jwt_required()
def add_comment(post_id):
    post = ForumPost.query.get_or_404(post_id)
    current_user = get_current_user()
    if thread_is_locked_for(post.thread, current_user):
        return error_response("This thread is locked and no longer accepting replies", 403)

    # Multipart form
    if request.content_type and request.content_type.startswith("multipart/form-data"):
        content = request.form.get("content")
        if not content:
            return error_response("Content is required", 400)

        comment = ForumComment(
            post_id=post_id,
            author_id=current_user.id,
            content=content,
        )
        db.session.add(comment)
        db.session.flush()

        attachment_errors = []
        if "files" in request.files:
            for f in request.files.getlist("files"):
                if not f.filename:
                    continue
                if not allowed_file(f.filename):
                    attachment_errors.append(
                        {"file_name": f.filename, "error": "Unsupported file type"}
                    )
                    continue
                filename = secure_filename(f.filename)
                try:
                    public_url, storage_path = _save_attachment_file(f, "comments")
                except Exception as e:
                    logger.error(f"Forum attachment upload failed: {e}")
                    attachment_errors.append(
                        {"file_name": f.filename, "error": str(e)}
                    )
                    continue
                attachment = ForumAttachment(
                    file_url=public_url,
                    file_type=f.mimetype,
                    comment_id=comment.id,
                    file_path=storage_path,
                    file_name=filename,
                    mime_type=f.mimetype,
                )
                db.session.add(attachment)

        db.session.commit()

        if post.author_id != current_user.id:
            notify_reply(
                recipient_id=post.author_id,
                actor_name=current_user.get_full_name(),
                thread_id=post.thread_id,
                post_id=post.id,
                is_bot=bool(getattr(current_user, "is_bot", False)),
            )

        response_data = comment.to_dict(include_attachments=True)
        if attachment_errors:
            response_data["attachment_errors"] = attachment_errors
        # FIX: Change from 200 to 201
        return success_response(response_data, 201)  # ✅ Changed to 201

    # JSON body
    data = request.get_json() or {}
    content = data.get("content")
    if not content:
        return error_response("Content is required", 400)

    comment = ForumComment(
        post_id=post_id,
        author_id=current_user.id,
        content=content,
    )
    db.session.add(comment)
    db.session.commit()

    if post.author_id != current_user.id:
        notify_reply(
            recipient_id=post.author_id,
            actor_name=current_user.get_full_name(),
            thread_id=post.thread_id,
            post_id=post.id,
            is_bot=bool(getattr(current_user, "is_bot", False)),
        )

    # FIX: Already 201 here, but keep it
    return success_response(comment.to_dict(include_attachments=True), 201)


@forums_bp.route("/posts/<int:post_id>/comments/<int:comment_id>", methods=["PATCH"])
@jwt_required()
def update_comment(post_id, comment_id):
    comment = ForumComment.query.get_or_404(comment_id)
    current_user = get_current_user()

    if comment.post_id != post_id:
        return error_response("Comment does not belong to this post", 400)

    if not can_manage(comment.author_id, current_user):
        return error_response("Unauthorized", 403)

    data = request.get_json() or {}
    if "content" in data:
        comment.content = data["content"]

    db.session.commit()
    return success_response(comment.to_dict())

@forums_bp.route("/posts/<int:post_id>/comments/<int:comment_id>", methods=["DELETE"])
@jwt_required()
def delete_comment(post_id, comment_id):
    comment = ForumComment.query.get_or_404(comment_id)
    current_user = get_current_user()

    if comment.post_id != post_id:
        return error_response("Comment does not belong to this post", 400)

    if not can_manage(comment.author_id, current_user):
        return error_response("Unauthorized", 403)

    db.session.delete(comment)
    db.session.commit()
    return success_response({"message": "Comment deleted"})


# ------------------------ REPORTS ------------------------

def _create_report(*, current_user, post_id=None, comment_id=None):
    data = request.get_json(silent=True) or {}
    reason = (data.get("reason") or "").strip()[:255] or None

    existing = ForumReport.query.filter_by(
        reporter_id=current_user.id, post_id=post_id, comment_id=comment_id
    ).first()
    if existing:
        return success_response({"message": "You've already reported this."})

    report = ForumReport(
        reporter_id=current_user.id,
        post_id=post_id,
        comment_id=comment_id,
        reason=reason,
    )
    db.session.add(report)
    db.session.commit()
    return success_response({"message": "Thanks — a moderator will take a look."}, 201)


@forums_bp.route("/posts/<int:post_id>/report", methods=["POST"])
@jwt_required()
def report_post(post_id):
    ForumPost.query.get_or_404(post_id)
    return _create_report(current_user=get_current_user(), post_id=post_id)


@forums_bp.route("/comments/<int:comment_id>/report", methods=["POST"])
@jwt_required()
def report_comment(comment_id):
    ForumComment.query.get_or_404(comment_id)
    return _create_report(current_user=get_current_user(), comment_id=comment_id)


@forums_bp.route("/reports", methods=["GET"])
@roles_required("admin", "moderator")
def list_reports():
    status = request.args.get("status", default="open")
    query = ForumReport.query
    if status != "all":
        query = query.filter_by(status=status)
    query = query.order_by(ForumReport.created_at.desc())
    return success_response(paginate_query(query))


@forums_bp.route("/reports/<int:report_id>", methods=["PATCH"])
@roles_required("admin", "moderator")
def resolve_report(report_id):
    report = ForumReport.query.get_or_404(report_id)
    current_user = get_current_user()
    data = request.get_json() or {}
    status = data.get("status", "resolved")
    if status not in ("open", "resolved"):
        return error_response("Invalid status", 400)

    report.status = status
    if status == "resolved":
        report.resolved_by_id = current_user.id
        report.resolved_at = db.func.now()
    db.session.commit()
    return success_response(report.to_dict())


# ------------------------ AI ASSISTANT ------------------------
#
# Deliberately narrow surface: the assistant only ever acts when a
# moderator explicitly invokes it on a specific post or thread. It never
# gets a route that lets it post unprompted. See ai_assistant.py for the
# model-calling logic and the reasoning behind this shape.

@forums_bp.route("/posts/<int:post_id>/ai-reply", methods=["POST"])
@roles_required("admin", "moderator")
def ai_reply_to_post(post_id):
    post = ForumPost.query.get_or_404(post_id)
    if thread_is_locked_for(post.thread, get_current_user()):
        return error_response("This thread is locked", 403)

    data = request.get_json(silent=True) or {}
    instruction = (data.get("instruction") or "").strip() or "Write a thoughtful reply to this forum post."

    context = f"Thread: {post.thread.title}\nPost title: {post.title}\nPost content: {post.content}"
    existing_comments = ForumComment.query.filter_by(post_id=post.id).order_by(
        ForumComment.created_at.asc()
    ).limit(10).all()
    if existing_comments:
        context += "\n\nExisting replies:\n" + "\n".join(
            f"- {c.user.username if c.user else 'someone'}: {c.content}" for c in existing_comments
        )

    try:
        reply_text = generate_assistant_reply(context=context, instruction=instruction)
    except AssistantError as e:
        return error_response(str(e), 502)

    bot = get_or_create_bot_user()
    comment = ForumComment(post_id=post.id, author_id=bot.id, content=reply_text)
    db.session.add(comment)
    db.session.commit()

    if post.author_id != bot.id:
        notify_reply(
            recipient_id=post.author_id,
            actor_name="Pensa Assistant",
            thread_id=post.thread_id,
            post_id=post.id,
            is_bot=True,
        )

    return success_response(comment.to_dict(include_attachments=False), 201)


@forums_bp.route("/threads/<int:thread_id>/ai-post", methods=["POST"])
@roles_required("admin", "moderator")
def ai_new_post_in_thread(thread_id):
    """Have the assistant draft a new discussion-starter post inside an
    existing thread — e.g. a weekly reflection prompt. It cannot create a
    brand new thread by itself; a moderator still has to have created the
    thread it lives in, which keeps the assistant a guest in spaces
    humans opened, not an independent author of the forum's structure."""
    thread = ForumThread.query.get_or_404(thread_id)
    if thread.is_locked:
        return error_response("This thread is locked", 403)

    data = request.get_json(silent=True) or {}
    instruction = (data.get("instruction") or "").strip()
    if not instruction:
        return error_response("instruction is required, e.g. 'Write a reflection prompt about patience'", 400)

    context = f"Thread: {thread.title}\n{thread.description or ''}"

    try:
        body_text = generate_assistant_reply(context=context, instruction=instruction)
    except AssistantError as e:
        return error_response(str(e), 502)

    bot = get_or_create_bot_user()
    title = (data.get("title") or instruction[:80]).strip()
    post = ForumPost(thread_id=thread.id, author_id=bot.id, title=title, content=body_text)
    db.session.add(post)
    db.session.commit()

    activity = Activity(
        title="Pensa Assistant shared a reflection",
        subtitle=(post.content or post.title)[:140],
        icon="forum",
        color="blue",
        user_id=bot.id,
        target_type="post",
        target_id=post.id,
        meta_data={"thread_id": post.thread_id, "is_bot": True},
    )
    db.session.add(activity)
    db.session.commit()
    broadcast_new_activity(activity)

    return success_response(post.to_dict(include_attachments=False), 201)


# ------------------------ ATTACHMENTS ------------------------

@forums_bp.route("/attachments/<int:attachment_id>", methods=["GET"])
def get_attachment(attachment_id):
    """
    Legacy path: serves attachments that were uploaded before the
    Supabase migration and still only exist on local disk. New
    attachments are served directly from their Supabase public URL
    (see ForumAttachment.to_dict) and never hit this route.

    as_attachment is False (not True, as it was before) so images
    render inline in <img> tags instead of the browser being told to
    download them — that was the bug behind the broken-image icon.
    """
    attachment = ForumAttachment.query.get_or_404(attachment_id)
    if not attachment.file_path or not os.path.exists(attachment.file_path):
        return error_response("Attachment file no longer available", 404)
    return send_file(
        attachment.file_path,
        as_attachment=False,
        download_name=attachment.file_name,
        mimetype=attachment.mime_type,
    )
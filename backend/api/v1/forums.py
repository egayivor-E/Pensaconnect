from math import ulp
import os
from datetime import datetime
from functools import wraps

from flask import Blueprint, request, send_file
from flask.views import MethodView
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename

from backend.extensions import db
from backend.models import (
    ForumThread,
    ForumPost,
    ForumComment,
    ForumAttachment,
    ForumCategory,
    ForumLike,
    User,
)
from .utils import success_response, error_response

forums_bp = Blueprint("forums", __name__, url_prefix="/forums")

UPLOAD_FOLDER = "uploads/forum"
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "pdf", "docx", "txt"}


# ------------------------ Helpers ------------------------

def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

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
    threads = ForumThread.query.order_by(ForumThread.created_at.desc()).all()
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
    )
    db.session.add(thread)
    db.session.commit()
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

        post = ForumPost(
            thread_id=thread.id,
            author_id=current_user.id,
            title=title,
            content=content,
        )
        db.session.add(post)
        db.session.flush()  # get post.id for attachments

        if "files" in request.files:
            os.makedirs(UPLOAD_FOLDER, exist_ok=True)
            for f in request.files.getlist("files"):
                if allowed_file(f.filename):
                    filename = secure_filename(f.filename)
                    # keep a unique stored path
                    stored_name = f"{datetime.utcnow().timestamp()}_{filename}"
                    file_path = os.path.join(UPLOAD_FOLDER, stored_name)
                    f.save(file_path)
                    attachment = ForumAttachment(
                        # NOTE: file_url is cosmetic (served by /attachments/<id>)
                        file_url=f"/forums/attachments/placeholder",
                        file_type=f.mimetype,
                        post_id=post.id,
                        file_path=file_path,
                        file_name=filename,
                        mime_type=f.mimetype,
                    )
                    db.session.add(attachment)

        db.session.commit()
        # FIX: Change from 200 to 201
        return success_response(post.to_dict(include_attachments=True), 201)  # ✅ Changed to 201

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

    post = ForumPost(
        thread_id=thread.id,
        author_id=current_user.id,
        title=title,
        content=content,
    )
    db.session.add(post)
    db.session.commit()
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
    ForumPost.query.get_or_404(post_id)
    current_user = get_current_user()

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

        if "files" in request.files:
            os.makedirs(UPLOAD_FOLDER, exist_ok=True)
            for f in request.files.getlist("files"):
                if allowed_file(f.filename):
                    filename = secure_filename(f.filename)
                    stored_name = f"{datetime.utcnow().timestamp()}_{filename}"
                    file_path = os.path.join(UPLOAD_FOLDER, stored_name)
                    f.save(file_path)
                    attachment = ForumAttachment(
                        file_url=f"/forums/attachments/placeholder",
                        file_type=f.mimetype,
                        comment_id=comment.id,
                        file_path=file_path,
                        file_name=filename,
                        mime_type=f.mimetype,
                    )
                    db.session.add(attachment)

        db.session.commit()
        # FIX: Change from 200 to 201
        return success_response(comment.to_dict(include_attachments=True), 201)  # ✅ Changed to 201

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


# ------------------------ ATTACHMENTS ------------------------

@forums_bp.route("/attachments/<int:attachment_id>", methods=["GET"])
def get_attachment(attachment_id):
    attachment = ForumAttachment.query.get_or_404(attachment_id)
    return send_file(
        attachment.file_path, as_attachment=True, download_name=attachment.file_name
    )

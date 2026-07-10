from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Post, PostCategory, ForumThread, User, Activity
from backend.extensions import db
from .utils import success_response, error_response
from datetime import datetime
posts_bp = Blueprint("posts", __name__, url_prefix="/posts")


# --- Helpers ---

def get_current_user() -> User:
    return User.query.get(get_jwt_identity())

def user_has_role(user: User, role_name: str) -> bool:
    return any(r.name == role_name for r in (user.roles or []))

def is_staff(user: User) -> bool:
    return user_has_role(user, "admin") or user_has_role(user, "moderator")

def can_manage(author_id: int, user: User) -> bool:
    # author can manage their own; staff can manage any
    return user and (author_id == user.id or is_staff(user))

def resolve_category_id(data: dict):
    """
    Post.category is a relationship to PostCategory, not a plain string
    column — Post.category_id is the real FK. Passing a raw string
    (e.g. the "general" default) straight into `category=` on the Post
    constructor, or via setattr in update_post, would break at
    flush/commit since SQLAlchemy expects a PostCategory instance there.

    Accepts either:
      - category_id (int): used directly
      - category (str, a name): looked up against PostCategory.name

    Unlike event_type_id, category_id is nullable — so an unmatched
    name (including the "general" fallback default, which may not
    exist as a real row) results in an uncategorized post rather than
    a hard failure. Returns None if neither key is present.
    """
    if data.get("category_id") is not None:
        return data["category_id"]

    name = data.get("category")
    if name:
        category = PostCategory.query.filter_by(name=name).first()
        if category:
            return category.id
        # Name given but no match — don't fail post creation over a
        # missing/misspelled category; just leave it uncategorized.
        return None

    return None

@posts_bp.route("/", methods=["GET"])
def list_posts():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    posts = Post.query.order_by(Post.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return success_response([p.to_dict() for p in posts.items])
@posts_bp.route("/<int:post_id>", methods=["GET"])
def get_post(post_id: int):
    post = Post.query.get_or_404(post_id)
    return success_response(post.to_dict())
@posts_bp.route("/", methods=["POST"])
@jwt_required()
def create_post():
    user_id = get_jwt_identity()
    data = request.get_json(silent=True) or {}

    if not data.get("title") or not data.get("content") or not data.get("thread_id"):
        return error_response("title, content and thread_id are required", 400)

    # Validate the thread exists before inserting — otherwise a bad
    # thread_id trips an unhandled IntegrityError (raw 500) instead of
    # a clean 400. Mirrors the check forums.py already does.
    thread = ForumThread.query.get(data["thread_id"])
    if not thread:
        return error_response("Thread does not exist", 400)

    try:
        post = Post(
            user_id=user_id,
            title=data["title"],
            content=data["content"],
            thread_id=data["thread_id"],
            category_id=resolve_category_id(data),
            created_at=datetime.utcnow(),
        )
        post.generate_slug()
        db.session.add(post)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to create post: {str(e)}", 400)

    # ✅ Log to the community activity feed. Wrapped in its own try/except
    # so a problem here (e.g. a bad icon/color value) can never roll back
    # or fail the post creation itself — the post is already committed
    # above by the time we get here.
    try:
        activity = Activity(
            title=f"New post: {post.title}",
            subtitle=(post.excerpt or post.content)[:140],
            icon="groups",
            color="orange",
            user_id=user_id,
        )
        db.session.add(activity)
        db.session.commit()
    except Exception:
        db.session.rollback()
    return success_response(post.to_dict(), "Post created", 201)
@posts_bp.route("/<int:post_id>", methods=["PATCH"])
@jwt_required()
def update_post(post_id: int):
    post = Post.query.get_or_404(post_id)
    current_user = get_current_user()

    # Ownership check — previously missing, meaning any authenticated
    # user could edit any post regardless of authorship.
    if not can_manage(post.user_id, current_user):
        return error_response("Unauthorized", 403)

    data = request.get_json(silent=True) or {}
    for key in ["title", "content"]:
        if key in data:
            setattr(post, key, data[key])
    # category is a relationship, not a plain column — resolve to the
    # FK instead of assigning a raw string onto it directly.
    if "category_id" in data or "category" in data:
        post.category_id = resolve_category_id(data)
    post.updated_at = datetime.utcnow()
    db.session.commit()
    return success_response(post.to_dict(), "Post updated")
@posts_bp.route("/<int:post_id>", methods=["DELETE"])
@jwt_required()
def delete_post(post_id: int):
    post = Post.query.get_or_404(post_id)
    current_user = get_current_user()

    # Ownership check — previously missing, meaning any authenticated
    # user could delete any post regardless of authorship.
    if not can_manage(post.user_id, current_user):
        return error_response("Unauthorized", 403)

    db.session.delete(post)
    db.session.commit()
    return success_response(message="Post deleted")

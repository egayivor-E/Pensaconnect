from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Post, Activity
from backend.extensions import db
from .utils import success_response, error_response
from datetime import datetime

posts_bp = Blueprint("posts", __name__, url_prefix="/posts")


@posts_bp.route("/", methods=["GET"])
def list_posts():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    posts = Post.query.order_by(Post.created_at.desc()).paginate(page, per_page, error_out=False)
    return success_response([p.to_dict() for p in posts.items])


@posts_bp.route("/<int:post_id>", methods=["GET"])
def get_post(post_id: int):
    post = Post.query.get_or_404(post_id)
    return success_response(post.to_dict())


@posts_bp.route("/", methods=["POST"])
@jwt_required()
def create_post():
    user_id = get_jwt_identity()
    data = request.get_json()
    post = Post(
        user_id=user_id,
        title=data["title"],
        content=data["content"],
        thread_id=data["thread_id"],
        category=data.get("category", "general"),
        created_at=datetime.utcnow(),
    )
    post.generate_slug()
    db.session.add(post)
    db.session.commit()

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
    data = request.get_json()
    for key in ["title", "content", "category"]:
        if key in data:
            setattr(post, key, data[key])
    post.updated_at = datetime.utcnow()
    db.session.commit()
    return success_response(post.to_dict(), "Post updated")


@posts_bp.route("/<int:post_id>", methods=["DELETE"])
@jwt_required()
def delete_post(post_id: int):
    post = Post.query.get_or_404(post_id)
    db.session.delete(post)
    db.session.commit()
    return success_response(message="Post deleted")

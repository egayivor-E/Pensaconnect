from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Comment
from backend.extensions import db
from .utils import success_response, error_response
from datetime import datetime

comments_bp = Blueprint("comments", __name__, url_prefix="/comments")

@comments_bp.route("/", methods=["GET"])
def list_comments():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    comments = Comment.query.order_by(Comment.created_at.desc()).paginate(page, per_page, error_out=False)
    return success_response([c.to_dict() for c in comments.items])

@comments_bp.route("/<int:comment_id>", methods=["GET"])
def get_comment(comment_id: int):
    comment = Comment.query.get_or_404(comment_id)
    return success_response(comment.to_dict())

@comments_bp.route("/", methods=["POST"])
@jwt_required()
def create_comment():
    user_id = get_jwt_identity()
    data = request.get_json()
    comment = Comment(
        user_id=user_id,
        post_id=data.get("post_id"),
        prayer_request_id=data.get("prayer_request_id"),
        event_id=data.get("event_id"),
        content=data["content"],
        created_at=datetime.utcnow()
    )
    db.session.add(comment)
    db.session.commit()
    return success_response(comment.to_dict(), "Comment created", 201)

@comments_bp.route("/<int:comment_id>", methods=["PATCH"])
@jwt_required()
def update_comment(comment_id: int):
    comment = Comment.query.get_or_404(comment_id)
    data = request.get_json()
    if "content" in data:
        comment.content = data["content"]
    comment.updated_at = datetime.utcnow()
    db.session.commit()
    return success_response(comment.to_dict(), "Comment updated")

@comments_bp.route("/<int:comment_id>", methods=["DELETE"])
@jwt_required()
def delete_comment(comment_id: int):
    comment = Comment.query.get_or_404(comment_id)
    db.session.delete(comment)
    db.session.commit()
    return success_response(message="Comment deleted")

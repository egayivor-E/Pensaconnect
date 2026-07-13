from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import TimelinePost, Activity
from .utils import broadcast_new_activity
import logging

logger = logging.getLogger(__name__)

# Blueprint registered under /api/v1/timeline-posts
timeline_posts_bp = Blueprint("timeline_posts", __name__, url_prefix="/timeline-posts")
timeline_posts_bp.strict_slashes = False


# ---------------------------
# Create a new timeline post
# ---------------------------
@timeline_posts_bp.route("/", methods=["POST"])
@jwt_required()
def create_timeline_post():
    data = request.get_json()
    user_id = get_jwt_identity()

    content = (data.get("content") or "").strip()
    if not content:
        return jsonify({"error": "Content is required"}), 400

    post = TimelinePost(
        content=content,
        image_url=data.get("image_url"),
        user_id=user_id,
    )
    db.session.add(post)
    db.session.commit()

    # ✅ Log to the community activity feed, same pattern as testimonies:
    # every timeline post also shows up in the global "Recent" feed via
    # an Activity row. meta_data.image_url lets the feed render the
    # post's image the same way it does for other activity types.
    try:
        activity = Activity(
            title="Shared a new post",
            subtitle=content[:140],
            icon="article",
            color="teal",
            user_id=user_id,
            target_type="timeline_post",
            target_id=post.id,
            meta_data={"image_url": post.image_url} if post.image_url else {},
        )
        db.session.add(activity)
        db.session.commit()
        broadcast_new_activity(activity)
    except Exception:
        logger.exception("Failed to log activity for timeline post %s", post.id)
        db.session.rollback()

    return jsonify(post.to_dict()), 201


# ---------------------------
# Get a user's timeline posts (for their profile)
# ---------------------------
@timeline_posts_bp.route("/user/<int:user_id>", methods=["GET"])
def get_user_timeline_posts(user_id):
    posts = (
        TimelinePost.query.filter_by(user_id=user_id)
        .order_by(TimelinePost.created_at.desc())
        .all()
    )
    return jsonify([p.to_dict() for p in posts])


# ---------------------------
# Delete a timeline post
# ---------------------------
@timeline_posts_bp.route("/<int:post_id>", methods=["DELETE"])
@jwt_required()
def delete_timeline_post(post_id):
    post = TimelinePost.query.get_or_404(post_id)
    user_id = get_jwt_identity()

    if post.user_id != user_id:
        return jsonify({"error": "Unauthorized"}), 403

    # ✅ "Delete everywhere": remove any Activity row(s) pointing at this
    # post so it also disappears from the global Recent feed, not just
    # the profile. Activity.target_type/target_id is a polymorphic
    # pointer with no FK/cascade (see the comment on Activity in
    # models.py), so this cleanup has to be done explicitly here.
    Activity.query.filter_by(
        target_type="timeline_post", target_id=post.id
    ).delete(synchronize_session=False)

    db.session.delete(post)
    db.session.commit()
    return jsonify({"message": "Post deleted"})
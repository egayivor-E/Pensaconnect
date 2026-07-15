import uuid
import logging

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity, verify_jwt_in_request
from sqlalchemy import func
from werkzeug.utils import secure_filename

from backend.extensions import db
from backend.models import TimelinePost, TimelinePostLike, TimelinePostComment, Activity
from backend.supabase_client import upload_file_to_supabase, TIMELINE_MEDIA_BUCKET
from .utils import broadcast_new_activity, success_response, error_response

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
        is_video=bool(data.get("is_video", False)),
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
            meta_data={
                "image_url": post.image_url,
                "is_video": post.is_video,
            } if post.image_url else {},
        )
        db.session.add(activity)
        db.session.commit()
        broadcast_new_activity(activity)
    except Exception:
        logger.exception("Failed to log activity for timeline post %s", post.id)
        db.session.rollback()

    # A freshly created post has no likes yet — include the fields so the
    # client's TimelinePost.fromJson always sees them, same shape as the
    # list endpoint below.
    data = post.to_dict()
    data["like_count"] = 0
    data["has_liked"] = False
    return jsonify(data), 201


# ---------------------------
# Upload media (photo or video) for a timeline post
# ---------------------------
IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
VIDEO_EXTENSIONS = {"mp4", "mov", "avi", "webm", "mkv", "m4v"}
ALLOWED_MEDIA_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS

CONTENT_TYPES = {
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "gif": "image/gif", "webp": "image/webp",
    "mp4": "video/mp4", "mov": "video/quicktime", "avi": "video/x-msvideo",
    "webm": "video/webm", "mkv": "video/x-matroska", "m4v": "video/x-m4v",
}


def _extension(filename: str) -> str:
    return filename.rsplit(".", 1)[1].lower() if "." in filename else ""


@timeline_posts_bp.route("/upload", methods=["POST"])
@jwt_required()
def upload_timeline_media():
    """
    Uploads a photo or video for a profile timeline post to Supabase
    Storage and returns its public URL. The client is expected to call
    this first, then pass the returned url/isVideo into the normal
    POST / (create_timeline_post) call as image_url/is_video.

    Requires the 'timeline-media' bucket to exist (public) in the
    Supabase project — create it the same way worship-media and
    forum-media were created.
    """
    user_id = get_jwt_identity()

    if "file" not in request.files:
        return error_response("No file uploaded. Please include a 'file' field.", 400)

    file = request.files["file"]
    if file.filename == "":
        return error_response("No selected file.", 400)

    filename = secure_filename(file.filename)
    ext = _extension(filename)
    if ext not in ALLOWED_MEDIA_EXTENSIONS:
        allowed = ", ".join(sorted(ALLOWED_MEDIA_EXTENSIONS))
        return error_response(f"Invalid file type. Allowed: {allowed}.", 400)

    content_type = CONTENT_TYPES.get(ext, file.mimetype or "application/octet-stream")
    unique_name = f"{uuid.uuid4()}_{filename}"
    destination_path = f"posts/{user_id}/{unique_name}"

    try:
        file_bytes = file.read()
        public_url = upload_file_to_supabase(
            file_bytes=file_bytes,
            destination_path=destination_path,
            content_type=content_type,
            bucket=TIMELINE_MEDIA_BUCKET,
        )
    except Exception as e:
        logger.exception("Timeline media upload failed for user %s", user_id)
        return error_response(f"Upload failed: {e}", 500)

    return success_response(
        {
            "url": public_url,
            "is_video": ext in VIDEO_EXTENSIONS,
        },
        "Media uploaded successfully",
        201,
    )


# ---------------------------
# Get a user's timeline posts (for their profile)
# ---------------------------
@timeline_posts_bp.route("/user/<int:user_id>", methods=["GET"])
def get_user_timeline_posts(user_id):
    # Optional auth: viewing a profile doesn't require being logged in,
    # but if the request does carry a valid token we use it to mark
    # which of these posts the *viewer* (not the profile owner) has
    # already liked — same idea as Activity.hasLiked on the home feed.
    current_user_id = None
    try:
        verify_jwt_in_request(optional=True)
        current_user_id = get_jwt_identity()
    except Exception:
        current_user_id = None

    posts = (
        TimelinePost.query.filter_by(user_id=user_id)
        .order_by(TimelinePost.created_at.desc())
        .all()
    )
    post_ids = [p.id for p in posts]

    # Single grouped query for all like counts, instead of one COUNT(*)
    # per post — avoids an N+1 query pattern as a profile's post list
    # grows.
    counts_by_post_id = {}
    if post_ids:
        rows = (
            db.session.query(
                TimelinePostLike.timeline_post_id,
                func.count(TimelinePostLike.id),
            )
            .filter(TimelinePostLike.timeline_post_id.in_(post_ids))
            .group_by(TimelinePostLike.timeline_post_id)
            .all()
        )
        counts_by_post_id = {row[0]: row[1] for row in rows}

    liked_post_ids = set()
    if current_user_id is not None and post_ids:
        liked_rows = (
            TimelinePostLike.query.filter(
                TimelinePostLike.user_id == current_user_id,
                TimelinePostLike.timeline_post_id.in_(post_ids),
            )
            .with_entities(TimelinePostLike.timeline_post_id)
            .all()
        )
        liked_post_ids = {row[0] for row in liked_rows}

    result = []
    for p in posts:
        d = p.to_dict()
        d["like_count"] = counts_by_post_id.get(p.id, 0)
        d["has_liked"] = p.id in liked_post_ids
        result.append(d)

    return jsonify(result)


# ---------------------------
# Get comments for a timeline post
# ---------------------------
@timeline_posts_bp.route("/<int:post_id>/comments", methods=["GET"])
def get_timeline_post_comments(post_id):
    # 404s if the post doesn't exist — same convention as like/delete.
    TimelinePost.query.get_or_404(post_id)

    comments = (
        TimelinePostComment.query.filter_by(timeline_post_id=post_id)
        .order_by(TimelinePostComment.created_at.asc())
        .all()
    )
    return jsonify([c.to_dict() for c in comments])


# ---------------------------
# Add a comment to a timeline post
# ---------------------------
@timeline_posts_bp.route("/<int:post_id>/comments", methods=["POST"])
@jwt_required()
def add_timeline_post_comment(post_id):
    post = TimelinePost.query.get_or_404(post_id)
    user_id = get_jwt_identity()

    data = request.get_json() or {}
    content = (data.get("content") or "").strip()
    if not content:
        return jsonify({"error": "Content is required"}), 400

    comment = TimelinePostComment(
        timeline_post_id=post_id,
        user_id=user_id,
        content=content,
    )
    db.session.add(comment)
    db.session.commit()

    # Note: comments intentionally do NOT create an Activity row. The
    # post itself already has one Activity (from create_timeline_post),
    # which is what should show up in the global "Recent" feed. Logging
    # every comment as its own Activity made each comment appear as a
    # separate, near-duplicate post in Recent — same reasoning as forum
    # comments (forums.py add_comment), which only notify the post
    # author and don't touch the Activity feed either.

    return jsonify(comment.to_dict()), 201

# ---------------------------
# Get a single timeline post by id
# ---------------------------
@timeline_posts_bp.route("/<int:post_id>", methods=["GET"])
def get_timeline_post(post_id):
    post = TimelinePost.query.get_or_404(post_id)

    current_user_id = None
    try:
        verify_jwt_in_request(optional=True)
        current_user_id = get_jwt_identity()
    except Exception:
        current_user_id = None

    data = post.to_dict()
    data["like_count"] = len(post.likes)
    data["has_liked"] = (
        current_user_id is not None
        and any(l.user_id == current_user_id for l in post.likes)
    )
    return jsonify(data)
# ---------------------------
# Toggle a like/reaction on a timeline post
# ---------------------------
@timeline_posts_bp.route("/<int:post_id>/like", methods=["POST"])
@jwt_required()
def toggle_timeline_post_like(post_id):
    user_id = get_jwt_identity()
    # 404s if the post doesn't exist, same behavior as delete below.
    TimelinePost.query.get_or_404(post_id)

    existing = TimelinePostLike.query.filter_by(
        user_id=user_id, timeline_post_id=post_id
    ).first()

    if existing:
        db.session.delete(existing)
        liked = False
    else:
        db.session.add(
            TimelinePostLike(user_id=user_id, timeline_post_id=post_id)
        )
        liked = True

    db.session.commit()

    like_count = TimelinePostLike.query.filter_by(
        timeline_post_id=post_id
    ).count()

    return success_response(
        {"liked": liked, "like_count": like_count},
        "Reaction updated",
    )


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
    # Both "timeline_post" (the post-creation activity) and
    # "timeline_post_comment" (any comment activities on this post)
    # need to be cleaned up so nothing dangling is left in the feed.
    Activity.query.filter(
        Activity.target_type.in_(["timeline_post", "timeline_post_comment"]),
        Activity.target_id == post.id,
    ).delete(synchronize_session=False)

    # ✅ Same reasoning for likes: TimelinePostLike rows reference this
    # post's id directly rather than through a cascading FK, so they'd
    # otherwise be orphaned (and could collide with a future post that
    # happens to reuse the id) if not cleaned up here.
    TimelinePostLike.query.filter_by(timeline_post_id=post.id).delete(
        synchronize_session=False
    )

    # ✅ Comments have a cascade="all, delete-orphan" relationship on
    # TimelinePost.comments (see models.py), so db.session.delete(post)
    # below already removes TimelinePostComment rows automatically. No
    # explicit cleanup query needed here, unlike likes/activities above.

    db.session.delete(post)
    db.session.commit()
    return jsonify({"message": "Post deleted"})
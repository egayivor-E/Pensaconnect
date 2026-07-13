import uuid
import logging

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename

from backend.extensions import db
from backend.models import TimelinePost, Activity
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

    return jsonify(post.to_dict()), 201


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
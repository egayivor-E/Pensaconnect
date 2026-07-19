from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import Testimony, TestimonyComment, TestimonyLike, User, Activity
from .utils import broadcast_new_activity
import logging

logger = logging.getLogger(__name__)

# Blueprint registered under /api/v1/testimonies
testimonies_bp = Blueprint("testimonies", __name__, url_prefix="/testimonies")
# Note: a bare `blueprint.strict_slashes = False` attribute is a no-op in
# Flask — it must be passed to each @route(...) call instead (see the
# "/" routes below), otherwise a caller that omits the trailing slash
# gets a 308 redirect that breaks CORS preflights. See notifications.py.


# ---------------------------
# Create a new testimony
# ---------------------------
@testimonies_bp.route("/", methods=["POST"], strict_slashes=False)
@jwt_required()
def create_testimony():
    data = request.get_json()
    user_id = get_jwt_identity()
    is_anonymous = data.get("is_anonymous", False)

    testimony = Testimony(
        title=data.get("title"),
        content=data.get("content"),
        image_url=data.get("image_url"),
        is_anonymous=is_anonymous,
        # ✅ Always record the real author. "Anonymous" only means the
        # identity is hidden from other users at display time (handled by
        # Testimony.to_dict()'s `is_anonymous` check below) — it should
        # never mean the author becomes untraceable for ownership/moderation
        # purposes. Storing None here was what broke delete/update auth
        # for anonymous testimonies.
        user_id=user_id,
    )

    db.session.add(testimony)
    db.session.commit()

    # ✅ Log to the community activity feed — but ONLY when not anonymous.
    # Activity.user_id is required (nullable=False) and the feed always
    # serializes with include_user=True, so logging this for an anonymous
    # testimony would leak exactly the identity the author asked to hide.
    if not is_anonymous:
        try:
            activity = Activity(
                title=f"Shared a testimony: {testimony.title}",
                subtitle=(testimony.content or "")[:140],
                icon="book",
                color="purple",
                user_id=user_id,
                target_type="testimony",
                target_id=testimony.id,
            )
            db.session.add(activity)
            db.session.commit()
            broadcast_new_activity(activity)
        except Exception:
            logger.exception("Failed to log activity for testimony %s", testimony.id)
            db.session.rollback()

    return jsonify(testimony.to_dict()), 201


# ---------------------------
# Get all testimonies
# ---------------------------
@testimonies_bp.route("/", methods=["GET"], strict_slashes=False)
def get_testimonies():
    # ✅ Was an unbounded `.all()` with no eager loading: this refetched
    # *every* testimony ever posted on every load (only getting slower
    # as the community grows) and to_dict() lazy-loaded self.user once
    # per row on top of that. Cap it and eager-load the author in the
    # same query — same pattern used for the forum threads/posts lists.
    query = Testimony.query.options(db.joinedload(Testimony.user))

    # ✅ FIX: user_id was already being sent by the frontend (see
    # testimony_repository.dart's countUserTestimonies), but this endpoint
    # silently ignored it and always returned the latest 100 testimonies
    # globally — so every profile screen showed the same global count
    # instead of that specific user's testimony count. When filtering to
    # one user's testimonies we also don't cap at 100, since this is used
    # to get a user's *full* count, not a paginated feed.
    user_id_filter = request.args.get("user_id", type=int)
    if user_id_filter:
        query = query.filter_by(user_id=user_id_filter)
        testimonies = query.order_by(Testimony.created_at.desc()).all()
    else:
        testimonies = query.order_by(Testimony.created_at.desc()).limit(100).all()

    return jsonify([t.to_dict() for t in testimonies])


# ---------------------------
# Get single testimony (with comments)
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>", methods=["GET"])
def get_testimony(testimony_id):
    testimony = Testimony.query.get_or_404(testimony_id)
    return jsonify(testimony.to_dict(include_comments=True))


# ---------------------------
# Update a testimony
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>", methods=["PUT"])
@jwt_required()
def update_testimony(testimony_id):
    testimony = Testimony.query.get_or_404(testimony_id)
    user_id = get_jwt_identity()

    if testimony.user_id != user_id:
        return jsonify({"error": "Unauthorized"}), 403

    data = request.get_json()
    testimony.title = data.get("title", testimony.title)
    testimony.content = data.get("content", testimony.content)
    testimony.image_url = data.get("image_url", testimony.image_url)

    db.session.commit()
    return jsonify(testimony.to_dict())


# ---------------------------
# Delete a testimony
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>", methods=["DELETE"])
@jwt_required()
def delete_testimony(testimony_id):
    testimony = Testimony.query.get_or_404(testimony_id)
    user_id = get_jwt_identity()

    # ✅ Now a plain ownership check. Works correctly for anonymous
    # testimonies too, since user_id is always stored (anonymity is
    # enforced only at display time in to_dict()). Previously, anonymous
    # testimonies had user_id=None, which made `testimony.user_id != user_id`
    # always False for the None case — letting ANY logged-in user delete
    # ANY anonymous testimony. That hole is closed now.
    #
    # Note: testimonies created before this fix may still have
    # user_id=None in the database. Those will now be blocked from
    # deletion by everyone (since no user_id will ever match None) rather
    # than open to everyone — safer default, but you may want a one-time
    # data migration or admin cleanup for that existing anonymous backlog.
    if testimony.user_id != user_id:
        return jsonify({"error": "Unauthorized"}), 403

    # ✅ "Delete everywhere": Activity is a polymorphic pointer with no
    # FK/cascade (see the comment on Activity in models.py), so deleting
    # the testimony alone left a dangling entry in the global Recent
    # feed. Clean it up explicitly here.
    Activity.query.filter_by(
        target_type="testimony", target_id=testimony.id
    ).delete(synchronize_session=False)

    db.session.delete(testimony)
    db.session.commit()
    return jsonify({"message": "Testimony deleted"})


# ---------------------------
# Add a comment
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>/comments", methods=["POST"])
@jwt_required()
def add_comment(testimony_id):
    data = request.get_json()
    user_id = get_jwt_identity()

    comment = TestimonyComment(
        testimony_id=testimony_id,
        user_id=user_id,
        content=data.get("content"),
    )

    db.session.add(comment)
    db.session.commit()
    return jsonify(comment.to_dict()), 201


# ---------------------------
# Get all comments for a testimony
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>/comments", methods=["GET"])
def get_comments(testimony_id):
    testimony = Testimony.query.get_or_404(testimony_id)
    # ✅ joinedload(user): to_dict() reads comment.user.*, so without
    # this every comment triggered its own lazy SELECT on users.
    comments = (
        TestimonyComment.query.options(db.joinedload(TestimonyComment.user))
        .filter_by(testimony_id=testimony.id)
        .order_by(TestimonyComment.created_at.desc())
        .all()
    )
    return jsonify([c.to_dict() for c in comments])


# ---------------------------
# Like / Unlike a testimony
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>/like", methods=["POST"])
@jwt_required()
def like_testimony(testimony_id):
    user_id = get_jwt_identity()
    existing_like = TestimonyLike.query.filter_by(
        testimony_id=testimony_id, user_id=user_id
    ).first()

    if existing_like:
        db.session.delete(existing_like)
        db.session.commit()
        return jsonify({"message": "Unliked"}), 200
    else:
        like = TestimonyLike(testimony_id=testimony_id, user_id=user_id)
        db.session.add(like)
        db.session.commit()
        return jsonify({"message": "Liked"}), 201
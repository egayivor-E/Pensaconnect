from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import Testimony, TestimonyComment, TestimonyLike, User

# Blueprint registered under /api/v1/testimonies
testimonies_bp = Blueprint("testimonies", __name__, url_prefix="/testimonies")
testimonies_bp.strict_slashes = False  # accept with or without trailing slash


# ---------------------------
# Create a new testimony
# ---------------------------
@testimonies_bp.route("/", methods=["POST"])
@jwt_required()
def create_testimony():
    data = request.get_json()
    user_id = get_jwt_identity()

    testimony = Testimony(
        title=data.get("title"),
        content=data.get("content"),
        image_url=data.get("image_url"),
        is_anonymous=data.get("is_anonymous", False),
        user_id=user_id if not data.get("is_anonymous", False) else None,
    )

    db.session.add(testimony)
    db.session.commit()
    return jsonify(testimony.to_dict()), 201


# ---------------------------
# Get all testimonies
# ---------------------------
@testimonies_bp.route("/", methods=["GET"])
def get_testimonies():
    testimonies = Testimony.query.order_by(Testimony.created_at.desc()).all()
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
# Delete a testimony - FIXED FOR ANONYMOUS
# ---------------------------
@testimonies_bp.route("/<int:testimony_id>", methods=["DELETE"])
@jwt_required()
def delete_testimony(testimony_id):
    testimony = Testimony.query.get_or_404(testimony_id)
    user_id = get_jwt_identity()

    # Allow deletion if testimony is anonymous OR user owns it
    if testimony.user_id is not None and testimony.user_id != user_id:
        return jsonify({"error": "Unauthorized"}), 403

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
    comments = (
        TestimonyComment.query.filter_by(testimony_id=testimony.id)
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
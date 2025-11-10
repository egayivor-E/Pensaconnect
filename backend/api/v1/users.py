import os
from flask import Blueprint, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from backend.models import User
from backend.extensions import db
from .utils import success_response, error_response

users_bp = Blueprint("users", __name__, url_prefix="/users")

# ======== CONFIG ========
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif"}
MAX_CONTENT_LENGTH = 2 * 1024 * 1024 # 2MB file size limit


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


# ======== ROUTES ========

# ✅ List all users
@users_bp.route("/", methods=["GET"])
@jwt_required()
def list_users():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    users = User.query.paginate(page=page, per_page=per_page, error_out=False)
    return success_response(
        [u.to_dict(exclude=["password_hash"]) for u in users.items]
    )


# ✅ Get specific user by ID
@users_bp.route("/<int:user_id>", methods=["GET"])
@jwt_required()
def get_user(user_id: int):
    user = User.query.get_or_404(user_id)
    return success_response(user.to_dict(exclude=["password_hash"]))


# ✅ Update user (Self only)
# NOTE: This route correctly uses PATCH (not PUT).
@users_bp.route("/<int:user_id>", methods=["PATCH"])
@jwt_required()
def update_user(user_id: int):
    current_user_id = get_jwt_identity()
    if user_id != current_user_id:
        return error_response("Unauthorized: You can only update your own profile.", 403)

    user = User.query.get_or_404(user_id)
    data = request.get_json() or {}

    allowed_fields = ["username", "email", "profile_picture"]
    for key in allowed_fields:
        if key in data and data[key] is not None:
            setattr(user, key, data[key])

    db.session.commit()
    return success_response(
        user.to_dict(exclude=["password_hash"]),
        "Profile updated successfully"
    )


# ✅ Delete user (Self only)
@users_bp.route("/<int:user_id>", methods=["DELETE"])
@jwt_required()
def delete_user(user_id: int):
    current_user_id = get_jwt_identity()
    if user_id != current_user_id:
        return error_response("Unauthorized: You can only delete your own account.", 403)

    user = User.query.get_or_404(user_id)
    db.session.delete(user)
    db.session.commit()
    return success_response(message="User deleted successfully")


# ✅ Get current user profile
@users_bp.route("/me", methods=["GET"])
@jwt_required()
def get_me():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)
    return success_response(user.to_dict(exclude=["password_hash"]))


# ✅ Update current user profile (for Flutter)
# NOTE: This route correctly uses PATCH (not PUT).
@users_bp.route("/me", methods=["PATCH"])
@jwt_required()
def update_me():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)
    data = request.get_json() or {}

    allowed_fields = ["username", "email", "profile_picture"]
    for key in allowed_fields:
        if key in data and data[key] is not None:
            setattr(user, key, data[key])

    db.session.commit()
    return success_response(
        user.to_dict(exclude=["password_hash"]),
        "Profile updated successfully"
    )


# ✅ Upload profile avatar (Multipart)
@users_bp.route("/me/avatar", methods=["POST"])
@jwt_required()
def upload_avatar():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    if "avatar" not in request.files:
        return error_response("No file uploaded. Please include an 'avatar' field.", 400)

    file = request.files["avatar"]

    if file.filename == "":
        return error_response("No selected file.", 400)

    if not allowed_file(file.filename):
        return error_response("Invalid file type. Allowed: png, jpg, jpeg, gif.", 400)

    filename = secure_filename(file.filename)

    # ✅ Always store files in the "uploads" folder inside your backend root
    upload_folder = os.path.join(current_app.root_path, "uploads")
    os.makedirs(upload_folder, exist_ok=True)

    # ✅ Save file to that folder
    file.save(os.path.join(upload_folder, filename))

    # ✅ Store only the public URL, not a filesystem path
    public_url = f"{request.host_url.rstrip('/')}/uploads/{filename}"

    # Save to DB
    user.profile_picture = public_url
    db.session.commit()

    return success_response(
        user.to_dict(exclude=["password_hash"]),
        "Avatar uploaded successfully"
    )

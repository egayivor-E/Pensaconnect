# backend/auth/routes.py
from flask import request, jsonify # type: ignore
from flask_jwt_extended import ( # type: ignore
    create_access_token,
    create_refresh_token,
    jwt_required,
    get_jwt_identity,
)
from flask_smorest import Blueprint, abort # type: ignore
from marshmallow import Schema, fields # type: ignore
from werkzeug.security import generate_password_hash, check_password_hash # type: ignore
from backend.models import User
from backend.extensions import db, limiter
from datetime import timedelta
from typing import Any, Dict
import secrets


# ---------------- Blueprint ----------------
auth_bp = Blueprint("auth", __name__, description="Authentication related operations")


# ---------------- Schemas ----------------
from marshmallow import Schema, fields # type: ignore

class RegisterSchema(Schema):
    username = fields.Str(required=True, metadata={"example": "john_doe"})
    email = fields.Email(required=True, metadata={"example": "john@example.com"})
    password = fields.Str(required=True, load_only=True)
    first_name = fields.Str(load_default="")
    last_name = fields.Str(load_default="")


class LoginSchema(Schema):
    username = fields.Str(required=True)
    password = fields.Str(required=True, load_only=True)


class ForgotPasswordSchema(Schema):
    email = fields.Email(required=True)


class ResetPasswordSchema(Schema):
    token = fields.Str(required=True)
    new_password = fields.Str(required=True, load_only=True)


class UserSchema(Schema):
    id = fields.Int(dump_only=True)
    username = fields.Str()
    email = fields.Email()
    role = fields.Str()


# ---------------- Helpers ----------------
def json_response(payload: Dict[str, Any], status: int = 200) -> Any:
    """Standardized JSON response helper."""
    return jsonify(payload), status


def validate_payload(data: Dict[str, Any], required_fields: list[str]) -> Dict[str, str] | None:
    """Validate required fields in request payload."""
    if not data:
        return {"error": "Request body must be JSON"}

    missing = [f for f in required_fields if not data.get(f)]
    if missing:
        return {"error": f"Missing required fields: {', '.join(missing)}"}
    if "email" in data and "@" not in data["email"]:
        return {"error": "Invalid email format"}
    return None


def generate_tokens(user: User) -> Dict[str, str]:
    """Generate access and refresh tokens for a user."""
    return {
        "access_token": create_access_token(identity=user.id, expires_delta=timedelta(hours=1)),
        "refresh_token": create_refresh_token(identity=user.id, expires_delta=timedelta(days=7)),
    }


# ---------------- Routes ----------------
@auth_bp.route("/")
def auth_base():
    return jsonify({"message": "Auth service is running and healthy."})


# ✅ Register
@auth_bp.route("/register", methods=["POST"])
@auth_bp.arguments(RegisterSchema)
@auth_bp.response(201, UserSchema)
@limiter.limit("5/minute")
def register_user(data):
    if User.query.filter_by(username=data["username"]).first():
        abort(409, message="Username already exists")
    if User.query.filter_by(email=data["email"].lower()).first():
        abort(409, message="Email already exists")

    user = User(
        username=data["username"].strip(),
        email=data["email"].strip().lower(),
        first_name=data.get("first_name", ""),
        last_name=data.get("last_name", ""),
    )
    user.set_password(data["password"])  # Use the set_password method

    db.session.add(user)
    db.session.commit()

    tokens = generate_tokens(user)
    return {
        **tokens,
        "user": {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role.value if user.role else "member",
        },
    }


# ✅ Login
@auth_bp.route("/login", methods=["POST"])
@auth_bp.arguments(LoginSchema)
@limiter.limit("10/minute")
def login_user(data):
    user = User.query.filter_by(username=data["username"]).first()
    if not user or not user.check_password(data["password"]):
        abort(401, message="Invalid credentials")

    tokens = generate_tokens(user)
    return {
        **tokens,
        "user": {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role.value if user.role else "member",
        },
    }


# ✅ Logout
@auth_bp.route("/logout", methods=["POST"])
@jwt_required()
def logout_user():
    return json_response({"message": "Successfully logged out"})


# ✅ Refresh
@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh_access_token():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return json_response({"error": "User not found"}, 404)

    new_token = create_access_token(identity=user.id, expires_delta=timedelta(hours=1))
    return json_response({"access_token": new_token})


# ✅ Current user
@auth_bp.route("/me", methods=["GET"])
@jwt_required()
def get_current_user():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return json_response({"error": "User not found"}, 404)

    return json_response(
        {
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "role": user.role.value if user.role else "member",
                "first_name": user.first_name,
                "last_name": user.last_name,
                "profile_picture": user.profile_picture,
            }
        }
    )


# ✅ Change password
@auth_bp.route("/change-password", methods=["POST"])
@jwt_required()
def change_password():
    data = request.get_json(silent=True)
    error = validate_payload(data, ["current_password", "new_password"])
    if error:
        return json_response(error, 400)

    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return json_response({"error": "User not found"}, 404)

    if not user.check_password(data["current_password"]):
        return json_response({"error": "Current password is incorrect"}, 401)

    user.set_password(data["new_password"])
    db.session.commit()
    return json_response({"message": "Password changed successfully"})


# ✅ Forgot password
@auth_bp.route("/forgot-password", methods=["POST"])
@auth_bp.arguments(ForgotPasswordSchema)
@limiter.limit("5/hour")
def forgot_password(data):
    user = User.query.filter_by(email=data["email"].lower()).first()
    if not user:
        abort(404, message="No account found with that email")

    # Generate a simple reset token (store in DB or cache in real app)
    reset_token = secrets.token_urlsafe(32)
    user.reset_token = reset_token
    db.session.commit()

    # Normally you'd send this via email
    return {"message": "Password reset token generated", "reset_token": reset_token}


# ✅ Reset password
@auth_bp.route("/reset-password", methods=["POST"])
@auth_bp.arguments(ResetPasswordSchema)
def reset_password(data):
    user = User.query.filter_by(reset_token=data["token"]).first()
    if not user:
        abort(400, message="Invalid or expired reset token")

    user.set_password(data["new_password"])
    user.reset_token = None
    db.session.commit()

    return {"message": "Password has been reset successfully"}
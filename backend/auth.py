from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token,
    jwt_required,
    get_jwt_identity,
    create_refresh_token
)
from backend.models import User
from backend.extensions import db
from typing import Any, Dict
from datetime import timedelta

auth_bp = Blueprint('auth', __name__)

# -------------------------
# Helper Functions
# -------------------------
def json_response(payload: Dict[str, Any], status: int = 200) -> Any:
    """Return a standardized JSON response."""
    return jsonify(payload), status

def validate_payload(data: Dict[str, Any], required_fields: list[str]) -> Dict[str, str] | None:
    """Validate required fields in a request payload."""
    missing = [f for f in required_fields if not data.get(f)]
    if missing:
        return {"error": f"Missing required fields: {', '.join(missing)}"}
    if "email" in data and data.get("email") and "@" not in data["email"]:
        return {"error": "Invalid email format"}
    return None

# -------------------------
# Routes
# -------------------------
@auth_bp.route("/register", methods=["POST"])
def register() -> Any:
    """
    Register a new user.
    Expects JSON with: username, email, password.
    Returns: JWT access token and user info.
    """
    data = request.get_json(silent=True) or {}

    # Validate required fields
    error = validate_payload(data, ["username", "email", "password"])
    if error:
        return json_response(error, 400)

    username = data["username"]
    email = data["email"]
    password = data["password"]

    # Check for existing users
    if User.query.filter_by(username=username).first():
        return json_response({"error": "Username already exists"}, 409)
    if User.query.filter_by(email=email).first():
        return json_response({"error": "Email already exists"}, 409)

    try:
        user = User(
            username=username,
            email=email,
            first_name=data.get("first_name", ""),
            last_name=data.get("last_name", ""),
        )
        user.set_password(password)

        db.session.add(user)
        db.session.commit()

        access_token = create_access_token(identity=user.id, expires_delta=timedelta(hours=1))
        refresh_token = create_refresh_token(identity=user.id)

        return json_response(
            {
                "message": "User registered successfully",
                "access_token": access_token,
                "refresh_token": refresh_token,
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "role": user.role.value if user.role else "member",
                },
            },
            201,
        )

    except Exception as e:
        db.session.rollback()
        return json_response({"error": f"Server error: {str(e)}"}, 500)


@auth_bp.route("/login", methods=["POST"])
def login() -> Any:
    """
    Authenticate a user.
    Expects JSON with: username OR email, password.
    Returns: JWT access token and user info.
    """
    data = request.get_json(silent=True) or {}

    if not data.get("password") or not (data.get("username") or data.get("email")):
        return json_response({"error": "Username/Email and password are required"}, 400)

    # Allow login with either username or email
    if data.get("username"):
        user = User.query.filter_by(username=data["username"]).first()
    else:
        user = User.query.filter_by(email=data["email"]).first()

    if not user or not user.check_password(data["password"]):
        return json_response({"error": "Invalid credentials"}, 401)

    access_token = create_access_token(identity=user.id, expires_delta=timedelta(hours=1))
    refresh_token = create_refresh_token(identity=user.id)

    return json_response(
        {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "role": user.role.value if user.role else "member",
            },
        }
    )


@auth_bp.route("/protected", methods=["GET"])
@jwt_required()
def protected() -> Any:
    """
    Protected route; requires valid JWT access token.
    Returns logged-in user info.
    """
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    if not user:
        return json_response({"error": "User not found"}, 404)

    return json_response(
        {
            "message": f"Logged in as {user.username}",
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "role": user.role.value if user.role else "member",
            },
        }
    )


@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh_token() -> Any:
    """Refresh JWT access token using refresh token."""
    user_id = get_jwt_identity()
    if not user_id:
        return json_response({"error": "User not found"}, 404)

    new_token = create_access_token(identity=user_id, expires_delta=timedelta(hours=1))
    return json_response({"access_token": new_token})


@auth_bp.route("/logout", methods=["POST"])
@jwt_required()
def logout() -> Any:
    """
    Logout endpoint.
    Client should discard token.
    """
    return json_response({"message": "Successfully logged out"})

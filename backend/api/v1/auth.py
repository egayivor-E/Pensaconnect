from flask import Blueprint, request
from backend.models import User
from backend.extensions import db
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    jwt_required,
    get_jwt_identity,
)
from datetime import timedelta
from .utils import success_response, error_response
import logging
from sqlalchemy import or_

logger = logging.getLogger(__name__)

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


def normalize_phone(phone):
    """Simple normalization: remove spaces, dashes, and parentheses."""
    if not phone:
        return None
    return "".join(c for c in phone if c.isdigit() or c == "+")


@auth_bp.route("/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    logger.info(f"Received registration request: {data}")

    try:
        email = (data.get("email") or "").strip()
        password = data.get("password")
        username = (
            data.get("username") or (email.split("@")[0] if email else "")
        ).strip()
        phone_number = normalize_phone(data.get("phone_number") or "")
        first_name = (data.get("first_name") or "").strip()
        last_name = (data.get("last_name") or "").strip()

        if not (email or phone_number) or not password:
            return error_response(
                "Email or phone number and password required", 400
            )

        # Check for existing user (case-insensitive)
        existing_user = User.query.filter(
            or_(
                User.email.ilike(email),
                User.username.ilike(username),
                User.phone_number.ilike(phone_number),
            )
        ).first()
        if existing_user:
            return error_response(
                "Email, username, or phone number already exists", 400
            )

        user = User(
            email=email.lower() if email else None,
            username=username.lower() if username else None,
            phone_number=phone_number if phone_number else None,
            first_name=first_name,
            last_name=last_name,
        )
        user.set_password(password)

        db.session.add(user)
        db.session.commit()

        return success_response(
            user.to_dict(exclude=["password_hash"]),
            "User registered",
            201,
        )

    except Exception as e:
        db.session.rollback()
        logger.error(f"Registration error: {e}")
        return error_response("Internal server error", 500)


@auth_bp.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    identifier = (
        data.get("identifier")
        or data.get("email")
        or data.get("username")
        or data.get("phone_number")
        or ""
    ).strip()
    password = data.get("password")

    logger.info(f"Login attempt for identifier: {identifier}")

    if not identifier or not password:
        return error_response(
            "Email, username, or phone number and password required", 400
        )

    # Normalize phone for login as well
    normalized_identifier = normalize_phone(identifier)

    # Case-insensitive query for email, username, or phone number
    user = User.query.filter(
        or_(
            User.email.ilike(identifier),
            User.username.ilike(identifier),
            User.phone_number.ilike(normalized_identifier),
        )
    ).first()

    if not user or not user.check_password(password):
        return error_response("Invalid credentials", 401)

    # ✅ Only store user.id in token
    access_token = create_access_token(
        identity=user.id, expires_delta=timedelta(hours=1)
    )
    refresh_token = create_refresh_token(
        identity=user.id, expires_delta=timedelta(days=30)
    )

    # ✅ Return full user data including roles
    user_data = user.to_dict(exclude=["password_hash"])
    user_data["roles"] = [r.name for r in user.roles]

    return success_response(
        {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": user_data,
        },
        "Login successful",
    )


@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)  # ✅ requires refresh token
def refresh():
    current_identity = get_jwt_identity()  # this is just user.id now

    # Issue new tokens (rotating refresh token strategy)
    new_access_token = create_access_token(
        identity=current_identity, expires_delta=timedelta(hours=1)
    )
    new_refresh_token = create_refresh_token(
        identity=current_identity, expires_delta=timedelta(days=30)
    )

    return success_response(
        {
            "access_token": new_access_token,
            "refresh_token": new_refresh_token,
        },
        "Tokens refreshed",
    )


@auth_bp.route("/me", methods=["GET"])
@jwt_required()
def me():
    """Return current user details with roles"""
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    if not user:
        return error_response("User not found", 404)

    user_data = user.to_dict(exclude=["password_hash"])
    user_data["roles"] = [r.name for r in user.roles]

    return success_response(user_data)

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

# ✅ ADD THESE IMPORTS
from backend.utils import (
    validate_user_registration, 
    validate_email, 
    validate_username,
    validate_password,
    validate_name,
    validate_phone_number,
    format_validation_errors,
    sanitize_input
)

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
        # ✅ SANITIZE INPUTS FIRST
        email = sanitize_input(data.get("email", "")).lower()
        password = data.get("password", "")
        username = sanitize_input(data.get("username", "")).lower()
        phone_number = normalize_phone(data.get("phone_number", ""))
        first_name = sanitize_input(data.get("first_name", ""))
        last_name = sanitize_input(data.get("last_name", ""))

        # ✅ COMPREHENSIVE VALIDATION
        validation_data = {
            'email': email,
            'username': username,
            'password': password,
            'first_name': first_name,
            'last_name': last_name,
            'phone': phone_number
        }
        
        validation_result = validate_user_registration(validation_data)
        if not validation_result.is_valid:
            logger.warning(f"Registration validation failed: {validation_result.errors}")
            return jsonify(format_validation_errors(validation_result)), 400

        # ✅ CHECK FOR EXISTING USER (case-insensitive)
        existing_user = User.query.filter(
            or_(
                User.email.ilike(email),
                User.username.ilike(username),
                User.phone_number.ilike(phone_number),
            )
        ).first()
        
        if existing_user:
            # Determine which field caused the conflict
            conflict_fields = []
            if existing_user.email.lower() == email.lower():
                conflict_fields.append("email")
            if existing_user.username.lower() == username.lower():
                conflict_fields.append("username")
            if existing_user.phone_number == phone_number:
                conflict_fields.append("phone_number")
                
            return error_response(
                f"{', '.join(conflict_fields)} already exists", 
                400
            )

        # ✅ CREATE USER WITH VALIDATED DATA
        user = User(
            email=email if email else None,
            username=username if username else None,
            phone_number=phone_number if phone_number else None,
            first_name=first_name,
            last_name=last_name,
        )
        user.set_password(password)

        db.session.add(user)
        db.session.commit()

        logger.info(f"User registered successfully: {user.username}")

        # ✅ GENERATE TOKENS
        access_token = create_access_token(
            identity=user.id, 
            expires_delta=timedelta(hours=1)
        )
        refresh_token = create_refresh_token(
            identity=user.id, 
            expires_delta=timedelta(days=30)
        )

        user_data = user.to_dict(exclude=["password_hash"])
        user_data["roles"] = [r.name for r in user.roles]

        return success_response(
            {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "user": user_data,
            },
            "User registered successfully",
            201,
        )

    except Exception as e:
        db.session.rollback()
        logger.error(f"Registration error: {e}")
        return error_response("Internal server error during registration", 500)


@auth_bp.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    
    # ✅ SANITIZE INPUTS
    identifier = sanitize_input(
        data.get("identifier") or 
        data.get("email") or 
        data.get("username") or 
        data.get("phone_number") or ""
    )
    password = data.get("password", "")

    logger.info(f"Login attempt for identifier: {identifier}")

    # ✅ BASIC VALIDATION
    if not identifier or not password:
        return error_response(
            "Identifier and password are required", 400
        )

    # ✅ RATE LIMITING CHECK (Add Redis-based rate limiting in production)
    # if is_rate_limited(request.remote_addr, 'login', 300, 5):  # 5 attempts per 5 minutes
    #     return error_response("Too many login attempts. Please try again later.", 429)

    # Normalize phone for login as well
    normalized_identifier = normalize_phone(identifier)

    # ✅ CASE-INSENSITIVE QUERY
    user = User.query.filter(
        or_(
            User.email.ilike(identifier),
            User.username.ilike(identifier),
            User.phone_number.ilike(normalized_identifier),
        )
    ).first()

    if not user or not user.check_password(password):
        logger.warning(f"Failed login attempt for identifier: {identifier}")
        return error_response("Invalid credentials", 401)

    # ✅ UPDATE LAST LOGIN
    try:
        user.update_last_login()
        db.session.commit()
    except Exception as e:
        logger.warning(f"Could not update last login: {e}")
        # Don't fail the login if this fails

    # ✅ GENERATE TOKENS
    access_token = create_access_token(
        identity=user.id, 
        expires_delta=timedelta(hours=1)
    )
    refresh_token = create_refresh_token(
        identity=user.id, 
        expires_delta=timedelta(days=30)
    )

    # ✅ RETURN USER DATA WITH ROLES
    user_data = user.to_dict(exclude=["password_hash"])
    user_data["roles"] = [r.name for r in user.roles]

    logger.info(f"Successful login for user: {user.username}")

    return success_response(
        {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": user_data,
        },
        "Login successful",
    )


@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    try:
        current_identity = get_jwt_identity()

        # ✅ VERIFY USER STILL EXISTS
        user = User.query.get(current_identity)
        if not user:
            return error_response("User no longer exists", 401)

        # ✅ ISSUE NEW TOKENS
        new_access_token = create_access_token(
            identity=current_identity, 
            expires_delta=timedelta(hours=1)
        )
        new_refresh_token = create_refresh_token(
            identity=current_identity, 
            expires_delta=timedelta(days=30)
        )

        logger.info(f"Tokens refreshed for user ID: {current_identity}")

        return success_response(
            {
                "access_token": new_access_token,
                "refresh_token": new_refresh_token,
            },
            "Tokens refreshed",
        )
        
    except Exception as e:
        logger.error(f"Token refresh error: {e}")
        return error_response("Token refresh failed", 401)


@auth_bp.route("/me", methods=["GET"])
@jwt_required()
def me():
    """Return current user details with roles"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)

        if not user:
            return error_response("User not found", 404)

        user_data = user.to_dict(exclude=["password_hash"])
        user_data["roles"] = [r.name for r in user.roles]

        return success_response(user_data)
        
    except Exception as e:
        logger.error(f"Error fetching user profile: {e}")
        return error_response("Failed to fetch user profile", 500)


# ✅ ADD PASSWORD RESET ENDPOINTS
@auth_bp.route("/forgot-password", methods=["POST"])
def forgot_password():
    """Initiate password reset process"""
    data = request.get_json(silent=True) or {}
    email = sanitize_input(data.get("email", "")).lower()
    
    if not email:
        return error_response("Email is required", 400)
    
    # Validate email format
    email_validation = validate_email(email)
    if not email_validation.is_valid:
        return error_response(email_validation.message, 400)
    
    user = User.query.filter_by(email=email).first()
    
    # Always return success to prevent email enumeration
    if user:
        logger.info(f"Password reset requested for: {email}")
        # TODO: Send password reset email
        # generate_reset_token_and_send_email(user)
    
    return success_response(
        message="If the email exists, a password reset link has been sent"
    )


@auth_bp.route("/reset-password", methods=["POST"])
def reset_password():
    """Reset password with token"""
    data = request.get_json(silent=True) or {}
    token = data.get("token")
    new_password = data.get("new_password")
    
    if not token or not new_password:
        return error_response("Token and new password are required", 400)
    
    # Validate password strength
    password_validation = validate_password(new_password)
    if not password_validation.is_valid:
        return jsonify(format_validation_errors(password_validation)), 400
    
    # TODO: Verify token and reset password
    # user = verify_reset_token(token)
    # if not user:
    #     return error_response("Invalid or expired reset token", 400)
    
    # user.set_password(new_password)
    # db.session.commit()
    
    return success_response(message="Password reset successfully")


# ✅ ADD PROFILE UPDATE ENDPOINT
@auth_bp.route("/profile", methods=["PUT"])
@jwt_required()
def update_profile():
    """Update user profile"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        
        if not user:
            return error_response("User not found", 404)
            
        data = request.get_json(silent=True) or {}
        
        # Only allow certain fields to be updated
        update_data = {}
        if 'first_name' in data:
            update_data['first_name'] = sanitize_input(data['first_name'])
        if 'last_name' in data:
            update_data['last_name'] = sanitize_input(data['last_name'])
        if 'phone_number' in data:
            update_data['phone_number'] = normalize_phone(data['phone_number'])
        
        # Validate update data
        from backend.utils import validate_user_profile_update
        validation_result = validate_user_profile_update(update_data)
        if not validation_result.is_valid:
            return jsonify(format_validation_errors(validation_result)), 400
        
        # Update user
        for field, value in update_data.items():
            setattr(user, field, value)
            
        db.session.commit()
        
        user_data = user.to_dict(exclude=["password_hash"])
        user_data["roles"] = [r.name for r in user.roles]
        
        return success_response(user_data, "Profile updated successfully")
        
    except Exception as e:
        db.session.rollback()
        logger.error(f"Profile update error: {e}")
        return error_response("Failed to update profile", 500)
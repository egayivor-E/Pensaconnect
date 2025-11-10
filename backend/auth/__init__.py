# backend/auth/__init__.py
from flask import Blueprint

# Create the authentication blueprint
auth_bp = Blueprint("auth", __name__, url_prefix="/auth")

# Import routes after blueprint creation to avoid circular imports
from backend.auth import routes  # noqa: E402

# Attach routes to blueprint
# The routes.py file already defines all endpoints with @auth_bp.route(...)
# So we just need to import it to register everything

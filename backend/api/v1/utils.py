from functools import wraps
from flask import jsonify, request, g # type: ignore

# ✅ Response helpers
def success_response(data=None, message="Success", status_code=200):
    return jsonify({"status": "success", "message": message, "data": data}), status_code

def error_response(message="Error", status_code=400):
    return jsonify({"status": "error", "message": message}), status_code

# ✅ Auth-only decorator
def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user = getattr(g, "user", None)
        if not user:
            return error_response("Authentication required", 401)
        return f(*args, **kwargs)
    return decorated_function

# ✅ Admin-only decorator
def require_admin(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user = getattr(g, "user", None)
        if not user:
            return error_response("Authentication required", 401)

        if not getattr(user, "is_admin", False):
            return error_response("Admin access required", 403)

        return f(*args, **kwargs)
    return decorated_function

# ✅ Healthcheck endpoint
from flask import Blueprint # type: ignore

health_bp = Blueprint("health", __name__)

@health_bp.route("/api/v1/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200

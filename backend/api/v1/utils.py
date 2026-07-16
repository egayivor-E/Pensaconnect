from functools import wraps
import logging
from flask import jsonify, request, g # type: ignore

logger = logging.getLogger(__name__)

# ✅ Response helpers
def success_response(data=None, message="Success", status_code=200, meta=None):
    # `meta` is optional and additive on purpose — e.g. pagination info
    # like {"has_more": bool, "next_cursor": ...}. Every existing caller
    # that only passes data/message keeps returning exactly the same
    # response shape as before; only endpoints that opt in by passing
    # `meta` get the extra key.
    payload = {"status": "success", "message": message, "data": data}
    if meta is not None:
        payload["meta"] = meta
    return jsonify(payload), status_code

def error_response(message="Error", status_code=400, errors=None):
    """
    `message` MUST be a plain string — it lands in the Flutter app's
    ApiException.message, which is strictly typed as `String`. Several
    call sites pass a ValidationResult's `.errors` dict (e.g.
    {"special": "Password must contain at least one special character"})
    — if that ever reaches here as `message` on its own, flatten it to a
    readable string as a safety net. Callers that already have a
    structured per-field errors dict should pass it via `errors=`
    instead, so `message` stays a clean summary and the structured
    detail still reaches clients that want it.
    """
    if isinstance(message, dict):
        errors = errors or message
        message = "; ".join(str(v) for v in message.values()) or "Validation failed"
    elif isinstance(message, (list, tuple)):
        message = "; ".join(str(v) for v in message) or "Validation failed"

    payload = {"status": "error", "message": message}
    if errors:
        payload["errors"] = errors
    return jsonify(payload), status_code

# ✅ Real-time feed push. Called exactly once, right after an Activity
# row is committed, so anyone already sitting on the Home feed sees it
# without pulling to refresh. Deliberately does NOT include per-user
# `hasLiked` (a broadcast has no single "requesting user" — every
# connected client gets the same payload) since the client already
# derives liked state from its own local target-keyed set, not from
# anything server-sent on the socket event.
#
# Best-effort and isolated on purpose: this runs after the real DB
# commit for the thing that triggered it, so a socket hiccup here must
# never surface as a failure of that already-successful request.
def broadcast_new_activity(activity):
    try:
        from backend import get_socketio
        socketio_instance = get_socketio()
        if socketio_instance is not None:
            socketio_instance.emit("new_activity", activity.to_dict(include_user=True))
    except Exception as e:
        logger.error(f"❌ Failed to broadcast new_activity for Activity#{activity.id}: {e}")

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
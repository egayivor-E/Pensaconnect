from functools import wraps
import logging
from flask import jsonify, request, g # type: ignore
from flask_jwt_extended import get_jwt_identity # type: ignore

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
    # `message` must reach the client as a plain string — Flutter's
    # ApiException.message is strictly typed `String`, so a dict/list
    # landing there crashes the app instead of showing the error. If a
    # caller passes a validation-errors dict/list as `message` (instead
    # of via `errors=`), flatten it here as a safety net rather than
    # letting that crash happen again.
    if isinstance(message, dict):
        errors = errors if errors is not None else message
        message = "; ".join(str(v) for v in message.values()) or "Validation failed"
    elif isinstance(message, (list, tuple)):
        message = "; ".join(str(v) for v in message) or "Validation failed"

    payload = {"status": "error", "message": message}
    if errors is not None:
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

# ✅ Admin check, called directly (not a decorator). This used to be
# defined as `def require_admin(f): ...` — a decorator checking
# g.user.is_admin, where nothing ever set g.user and User has no
# is_admin column, so it always fell through to "unauthenticated".
# Meanwhile bible.py calls it 6 times as `user, error = require_admin()`,
# a function call expecting a (user, error_response_or_None) tuple, which
# raised TypeError on every single call. Rewritten to match how it's
# actually used, on the real identity/role pattern used elsewhere in the
# app: get_jwt_identity() + User.has_role("admin") (see forums.py's
# get_current_user/roles_required for the same pattern).
#
# jwt_required() is NOT applied here since callers already sit behind
# their own @jwt_required() on the route; this only resolves + authorizes
# the user identity already established by that decorator.
def require_admin():
    from backend.models import User

    user_id = get_jwt_identity()
    user = User.query.get(user_id) if user_id is not None else None

    if not user:
        return None, error_response("Authentication required", 401)

    if not user.has_role("admin"):
        return None, error_response("Admin access required", 403)

    return user, None

# ✅ Healthcheck endpoint
from flask import Blueprint # type: ignore

health_bp = Blueprint("health", __name__)

@health_bp.route("/api/v1/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200
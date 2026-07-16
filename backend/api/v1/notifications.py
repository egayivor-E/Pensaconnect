from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from .utils import success_response
from datetime import datetime

# Lazy import to avoid circular imports
def get_notification_model():
    from backend.models import Notification
    return Notification


notifications_bp = Blueprint("notifications", __name__, url_prefix="/notifications")
# ✅ FIX: without this, GET /notifications (no trailing slash — what the
# frontend actually calls, see ApiService.get('notifications', ...)) hit
# a route registered as "/", so Flask 308-redirected it to "/notifications/".
# That redirect is harmless for a plain GET, but a CORS *preflight*
# (OPTIONS) response is not allowed to be a redirect — browsers reject it
# outright — so the real GET never went out and Flutter web saw
# "ClientException: Failed to fetch". Same pattern already used by
# testimonies_bp and timeline_posts_bp.
notifications_bp.strict_slashes = False


@notifications_bp.route("/", methods=["GET"])
@jwt_required()
def list_notifications():
    Notification = get_notification_model()
    user_id = get_jwt_identity()
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))

    pagination = (
        Notification.query
        .filter_by(user_id=user_id)
        .order_by(Notification.created_at.desc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )

    return success_response([n.to_dict() for n in pagination.items])


@notifications_bp.route("/unread-count", methods=["GET"])
@jwt_required()
def unread_count():
    Notification = get_notification_model()
    user_id = get_jwt_identity()
    count = Notification.query.filter_by(user_id=user_id, is_read=False).count()
    return success_response({"count": count})


@notifications_bp.route("/<int:notification_id>/read", methods=["POST"])
@jwt_required()
def mark_as_read(notification_id: int):
    Notification = get_notification_model()
    user_id = get_jwt_identity()
    notification = Notification.query.filter_by(id=notification_id, user_id=user_id).first_or_404()
    notification.mark_as_read()
    db.session.commit()
    return success_response(notification.to_dict(), "Notification marked as read")

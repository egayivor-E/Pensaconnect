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


@notifications_bp.route("/<int:notification_id>/read", methods=["POST"])
@jwt_required()
def mark_as_read(notification_id: int):
    Notification = get_notification_model()
    user_id = get_jwt_identity()
    notification = Notification.query.filter_by(id=notification_id, user_id=user_id).first_or_404()
    notification.mark_as_read()
    db.session.commit()
    return success_response(notification.to_dict(), "Notification marked as read")

from flask import Blueprint
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Activity
from backend.extensions import db
from .utils import success_response

activities_bp = Blueprint("activities", __name__, url_prefix="/activities")


@activities_bp.route("/recent", methods=["GET"])
@jwt_required()
def get_recent_activities():
    # ✅ Global community feed: recent activity from ALL users, not just
    # the logged-in one, so "Recent Activity" actually reads as a living
    # feed of what's happening in the community rather than a personal
    # log. Still requires a valid JWT to view (route stays @jwt_required),
    # it's just no longer filtered down to the caller's own rows.
    activities = (
        Activity.query.filter_by(is_active=True)
        .order_by(Activity.created_at.desc())
        .limit(20)
        .all()
    )

    # ✅ include_user=True so each activity carries the acting user's
    # id/username/fullName/profilePicture for the feed avatar.
    # ✅ current_user_id=<caller> so each activity also carries whether
    # *this* user already liked/prayed for its target, letting the
    # frontend hydrate like state on load instead of assuming everything
    # is unliked until interacted with this session.
    current_user_id = get_jwt_identity()
    return success_response(
        [
            a.to_dict(include_user=True, current_user_id=current_user_id)
            for a in activities
        ]
    )

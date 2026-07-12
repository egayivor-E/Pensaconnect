from flask import Blueprint, request
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
    #
    # ✅ Respects the `limit` the frontend already sends (previously
    # hardcoded to 20 regardless, so e.g. HomeScreen's `limit: 20` request
    # happened to match by coincidence but any other caller's chosen
    # limit was silently ignored). Clamped to keep a careless/malicious
    # caller from asking for the whole table in one request.
    try:
        limit = int(request.args.get("limit", 20))
    except (TypeError, ValueError):
        limit = 20
    limit = max(1, min(limit, 50))

    activities = (
        Activity.query.filter_by(is_active=True)
        .order_by(Activity.created_at.desc())
        .limit(limit)
        .all()
    )

    # ✅ include_user=True so each activity carries the acting user's
    # id/username/fullName/profilePicture for the feed avatar.
    return success_response([a.to_dict(include_user=True) for a in activities])

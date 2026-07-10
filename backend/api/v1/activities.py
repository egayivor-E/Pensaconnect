from flask import Blueprint
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Activity
from backend.extensions import db
from .utils import success_response

activities_bp = Blueprint("activities", __name__, url_prefix="/activities")


@activities_bp.route("/recent", methods=["GET"])
@jwt_required()
def get_recent_activities():
    current_user_id = get_jwt_identity()

    # NOTE: this still scopes activities to the logged-in user only.
    # If "Recent Activity" is meant to feel like a community feed rather
    # than a personal log, drop the filter_by(user_id=...) and instead
    # query across all users (optionally joined against group/forum
    # membership so people only see activity from spaces they're in).
    # Left as-is here since that's a product decision, not a bug fix.
    activities = (
        Activity.query.filter_by(user_id=current_user_id)
        .order_by(Activity.created_at.desc())
        .limit(10)
        .all()
    )

    # ✅ include_user=True so each activity carries the acting user's
    # id/username/fullName/profilePicture for the feed avatar.
    return success_response([a.to_dict(include_user=True) for a in activities])

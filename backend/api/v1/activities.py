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

    activities = (
        Activity.query.filter_by(user_id=current_user_id)
        .order_by(Activity.created_at.desc())
        .limit(10)
        .all()
    )

    return success_response([a.to_dict() for a in activities])

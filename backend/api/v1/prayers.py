from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import PrayerRequest, Prayer, PrayerStatus, Activity
from backend.extensions import db
from .utils import success_response, error_response
from datetime import datetime

prayers_bp = Blueprint("prayers", __name__, url_prefix="/prayers")

# ==================== CORS OPTIONS ====================
@prayers_bp.route("/", methods=["OPTIONS"])
@prayers_bp.route("/<int:prayer_id>", methods=["OPTIONS"])
@prayers_bp.route("/<int:prayer_id>/toggle_prayer", methods=["OPTIONS"])
def handle_options(prayer_id=None):
    return "", 200


# ==================== LIST PRAYERS ====================
@prayers_bp.route("", methods=["GET"])
@jwt_required(optional=True)
def list_prayers():
    try:
        page = int(request.args.get("page", 1))
        per_page = int(request.args.get("per_page", 20))
        filter_type = request.args.get("filter", "wall")
        current_user_id = get_jwt_identity()

        query = PrayerRequest.query

        if filter_type == "answered":
            status_instance = PrayerStatus.query.filter_by(name="answered").first()
            if status_instance:
                query = query.filter_by(status=status_instance).order_by(
                    PrayerRequest.updated_at.desc()
                )
        elif filter_type == "my_prayers":
            if not current_user_id:
                return error_response("Authentication required for My Prayers", 401)
            query = query.filter_by(user_id=current_user_id).order_by(
                PrayerRequest.created_at.desc()
            )
        else:  # wall
            query = query.order_by(PrayerRequest.created_at.desc())

        paginated = query.paginate(page=page, per_page=per_page, error_out=False)

        results = []
        for r in paginated.items:
            prayer_dict = r.to_dict(include_prayers=True, current_user_id=current_user_id)
            # Include has_prayed for current user
            if current_user_id:
                prayer_dict['has_prayed'] = Prayer.query.filter_by(
                    user_id=current_user_id, prayer_request_id=r.id
                ).first() is not None
            else:
                prayer_dict['has_prayed'] = False
            results.append(prayer_dict)

        return success_response(results)

    except Exception as e:
        return error_response(f"Failed to list prayer requests: {str(e)}", 500)


# ==================== GET SINGLE PRAYER ====================
@prayers_bp.route("/<int:prayer_id>", methods=["GET"])
def get_prayer(prayer_id: int):
    prayer = PrayerRequest.query.get_or_404(prayer_id)
    return success_response(prayer.to_dict(include_prayers=True))


# ==================== CREATE PRAYER ====================
@prayers_bp.route("/", methods=["POST"])
@jwt_required()
def create_prayer():
    try:
        user_id = get_jwt_identity()
        data = request.get_json(silent=True)

        if data is None:
            return error_response("Request body must be valid JSON", 400)

        title = data.get("title", "").strip()
        content = data.get("content", "").strip()
        category = data.get("category", "General").strip()

        if not title or not content:
            return error_response("Title and content cannot be empty", 400)

        status_name = data.get("status", "pending")
        status_instance = PrayerStatus.query.filter_by(name=status_name).first()
        if not status_instance:
            return error_response(f"Invalid status '{status_name}'", 400)

        is_anonymous = data.get("is_anonymous", False)

        prayer_instance = PrayerRequest(
            user_id=user_id,
            title=title,
            content=content,
            category=category,
            is_anonymous=is_anonymous,
            status=status_instance,
            created_at=datetime.utcnow(),
        )

        db.session.add(prayer_instance)
        db.session.commit()

        # Activity logging is skipped entirely when the request is anonymous.
        # Activity.user_id is non-nullable and Activity.to_dict(include_user=True)
        # would otherwise leak the identity of a user who asked to stay hidden.
        if not is_anonymous:
            activity = Activity(
                title="New Prayer Request",
                subtitle=title,
                icon="pray",
                color="blue",
                user_id=user_id,
                target_type="prayer_request",
                target_id=prayer_instance.id,
            )
            db.session.add(activity)
            db.session.commit()

        return success_response(prayer_instance.to_dict(), "Prayer request created", 201)
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to create prayer request: {str(e)}", 500)


# ==================== UPDATE PRAYER ====================
@prayers_bp.route("/<int:prayer_id>", methods=["PATCH"])
@jwt_required()
def update_prayer(prayer_id: int):
    try:
        prayer = PrayerRequest.query.get_or_404(prayer_id)

        # Ownership check: only the original author may edit their request.
        current_user_id = get_jwt_identity()
        if prayer.user_id != current_user_id:
            return error_response("You do not have permission to edit this prayer request", 403)

        data = request.get_json(silent=True)

        if data is None:
            return error_response("Request body must be valid JSON", 400)

        if "status" in data:
            status_name = data["status"].lower()
            status_instance = PrayerStatus.query.filter_by(name=status_name).first()
            if not status_instance:
                return error_response(f"Invalid status '{status_name}'", 400)
            prayer.status = status_instance

        for key in ["title", "content", "is_anonymous", "category"]:
            if key in data:
                setattr(prayer, key, data[key])

        prayer.updated_at = datetime.utcnow()
        db.session.commit()
        return success_response(prayer.to_dict(), "Prayer request updated")
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to update prayer request: {str(e)}", 500)


# ==================== DELETE PRAYER ====================
@prayers_bp.route("/<int:prayer_id>", methods=["DELETE"])
@jwt_required()
def delete_prayer(prayer_id: int):
    try:
        prayer = PrayerRequest.query.get_or_404(prayer_id)

        # Ownership check: only the original author may delete their request.
        current_user_id = get_jwt_identity()
        if prayer.user_id != current_user_id:
            return error_response("You do not have permission to delete this prayer request", 403)

        db.session.delete(prayer)
        db.session.commit()
        return success_response(message="Prayer request deleted")
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to delete prayer request: {str(e)}", 500)


# ==================== TOGGLE "I PRAYED" ====================
@prayers_bp.route("/<int:prayer_id>/toggle_prayer", methods=["POST"])
@jwt_required()
def toggle_prayer(prayer_id: int):
    try:
        user_id = get_jwt_identity()
        prayer_request = PrayerRequest.query.get_or_404(prayer_id)
        did_pray = False  # track which branch ran, so Activity only logs on "add"

        with db.session.begin_nested():
            existing_prayer = Prayer.query.filter_by(
                user_id=user_id, prayer_request_id=prayer_id
            ).first()

            if existing_prayer:
                db.session.delete(existing_prayer)
            else:
                new_prayer = Prayer(
                    user_id=user_id, prayer_request_id=prayer_id, message=""
                )
                db.session.add(new_prayer)
                did_pray = True

            db.session.flush()

            prayer_count = Prayer.query.filter_by(prayer_request_id=prayer_id).count()
            unique_count = db.session.query(Prayer.user_id).filter_by(
                prayer_request_id=prayer_id
            ).distinct().count()

            prayer_request.prayer_count = prayer_count
            prayer_request.unique_prayers = unique_count
            db.session.add(prayer_request)

        db.session.commit()

        # Log an Activity only when the user prayed (not when un-praying), so
        # toggling off doesn't spam the feed with removal events.
        #
        # ✅ Deduped per (user, prayer_request): without this check, toggling
        # prayed -> unprayed -> prayed again for the same request inserted a
        # fresh Activity row every time, so the global feed filled up with
        # multiple near-identical "Prayed for a Request" rows for the same
        # user+request. This also broke the frontend's like state, which
        # tracked "liked" by the Activity row's id — a new row on every
        # re-pray meant the old id's "liked" flag no longer matched anything
        # once the feed refreshed, making the like appear to vanish. Logging
        # at most once per user+request keeps the feed entry (and the id the
        # frontend keys off of) stable across repeated toggles.
        if did_pray:
            already_logged = Activity.query.filter_by(
                user_id=user_id,
                target_type="prayer_request",
                target_id=prayer_request.id,
            ).first()
            if not already_logged:
                activity = Activity(
                    title="Prayed for a Request",
                    subtitle=prayer_request.title,
                    icon="pray",
                    color="blue",
                    user_id=user_id,
                    target_type="prayer_request",
                    target_id=prayer_request.id,
                )
                db.session.add(activity)
                db.session.commit()

        updated_request = PrayerRequest.query.get(prayer_id)
        return success_response(
            updated_request.to_dict(include_prayers=True, current_user_id=user_id),
            "Prayer toggled",
            201
        )
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to toggle prayer: {str(e)}", 500)

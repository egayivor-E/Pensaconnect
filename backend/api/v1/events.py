from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
# Import the new EventReminder model
from backend.models import Event, EventAttendee, EventReminder 
from backend.extensions import db
from .utils import success_response, error_response
from datetime import datetime, timezone 
import json # Import json for JSON handling if needed

# ✅ Use url_prefix without trailing slash
events_bp = Blueprint("events", __name__, url_prefix="/events")


# --- EXISTING EVENT ROUTES (Keep as-is) ---

# ✅ GET /api/v1/events
@events_bp.route("", methods=["GET"])
def list_events():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))

    events = (
        Event.query.order_by(Event.start_time.desc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )

    return success_response([e.to_dict() for e in events.items])


# ✅ GET /api/v1/events/<event_id>
@events_bp.route("/<int:event_id>", methods=["GET"])
def get_event(event_id: int):
    event = Event.query.get_or_404(event_id)
    return success_response(event.to_dict())


# ✅ POST /api/v1/events
@events_bp.route("", methods=["POST"])
@jwt_required()
def create_event():
    user_id = get_jwt_identity()
    data = request.get_json()

    try:
        event = Event(
            user_id=user_id,
            title=data["title"],
            description=data["description"],
            # Assuming event_type in data is now just a string, 
            # but event_type_id is required for the FK.
            # If the data includes event_type (string), you should check your model.
            # For now, let's keep the original logic:
            event_type=data["event_type"], 
            start_time=datetime.fromisoformat(data["start_time"]),
            end_time=datetime.fromisoformat(data["end_time"]),
            location=data.get("location"),
            is_virtual=data.get("is_virtual", False),
            event_type_id=data["event_type_id"],
        )
        db.session.add(event)
        db.session.commit()
        return success_response(event.to_dict(), "Event created", 201)
    except KeyError as e:
        db.session.rollback()
        return error_response(f"Missing required field: {str(e)}", 400)
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to create event: {str(e)}", 400)

# ✅ PATCH /api/v1/events/<event_id>
@events_bp.route("/<int:event_id>", methods=["PATCH"])
@jwt_required()
def update_event(event_id: int):
    event = Event.query.get_or_404(event_id)
    data = request.get_json()

    try:
        for key in [
            "title", "description", "event_type", "start_time", "end_time", 
            "location", "is_virtual",
        ]:
            if key in data:
                if key in ["start_time", "end_time"]:
                    setattr(event, key, datetime.fromisoformat(data[key]))
                else:
                    setattr(event, key, data[key])

        event.updated_at = datetime.utcnow()
        db.session.commit()
        return success_response(event.to_dict(), "Event updated")
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to update event: {str(e)}", 400)


# ✅ DELETE /api/v1/events/<event_id>
@events_bp.route("/<int:event_id>", methods=["DELETE"])
@jwt_required()
def delete_event(event_id: int):
    event = Event.query.get_or_404(event_id)
    try:
        db.session.delete(event)
        db.session.commit()
        return success_response(message="Event deleted")
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to delete event: {str(e)}", 400)


# ✅ POST /api/v1/events/<event_id>/register
@events_bp.route("/<int:event_id>/register", methods=["POST"])
@jwt_required()
def register_event(event_id: int):
    user_id = get_jwt_identity()
    event = Event.query.get_or_404(event_id)

    try:
        attendee = EventAttendee(user_id=user_id, event_id=event_id)
        db.session.add(attendee)
        db.session.commit()
        return success_response(event.to_dict(), "Registered for event", 201)
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to register: {str(e)}", 400)


# ✅ GET /api/v1/events/<event_id>/attendees
@events_bp.route("/<int:event_id>/attendees", methods=["GET"])
@jwt_required()
def get_event_attendees(event_id: int):
    """Fetches all attendees for a specific event."""
    event = Event.query.get_or_404(event_id)
    
    # Assuming EventAttendee has a user relationship, 
    # and User model has a .to_dict() or a way to get necessary user info.
    attendees_data = [
        {'user_id': ea.user_id, 'status': ea.status} # Simplify, or use user.to_dict()
        for ea in event.attendees
    ]
    
    return success_response(attendees_data, "Event attendees fetched")


# --- NEW REMINDER ROUTES ---

# 🌟 NEW ENDPOINT: GET /api/v1/events/<event_id>/reminders
@events_bp.route("/<int:event_id>/reminders", methods=["GET"])
@jwt_required()
def get_user_event_reminders(event_id: int):
    """Fetches the current user's reminders for a specific event."""
    user_id = get_jwt_identity()
    Event.query.get_or_404(event_id) # Check if event exists
    
    reminders = EventReminder.query.filter_by(
        user_id=user_id, 
        event_id=event_id
    ).all()
    
    # You'll need to ensure your EventReminder model has a .to_dict() method
    # For now, we return placeholder dictionaries if .to_dict() isn't available
    try:
        reminders_data = [r.to_dict() for r in reminders]
    except AttributeError:
        # Fallback if to_dict() is missing, customize this to your needs
        reminders_data = [
            {
                'id': r.id, 
                'user_id': r.user_id, 
                'event_id': r.event_id, 
                'reminder_time': r.reminder_time.isoformat()
            } 
            for r in reminders
        ]

    return success_response(reminders_data, "Event reminders fetched")


# 🌟 NEW ENDPOINT: POST /api/v1/events/<event_id>/reminders
@events_bp.route("/<int:event_id>/reminders", methods=["POST"])
@jwt_required()
def create_event_reminder(event_id: int):
    """Creates a new reminder for the current user for an event."""
    user_id = get_jwt_identity()
    Event.query.get_or_404(event_id) # Check if event exists
    data = request.get_json()

    try:
        reminder_time_str = data["reminder_time"]
        
        # Ensure 'reminder_time' is a valid ISO format string for datetime conversion
        reminder_time = datetime.fromisoformat(reminder_time_str)

        reminder = EventReminder(
            user_id=user_id,
            event_id=event_id,
            reminder_time=reminder_time,
            message=data.get("message"),
            meta_data=data.get("meta_data", {}),
        )

        db.session.add(reminder)
        db.session.commit()

        # Assuming EventReminder.to_dict() exists
        return success_response(reminder.to_dict(), "Reminder created successfully", 201)

    except KeyError:
        db.session.rollback()
        return error_response("Missing required field: reminder_time", 400)
    except ValueError:
        db.session.rollback()
        return error_response("Invalid format for reminder_time. Use ISO 8601 format.", 400)
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to create reminder: {str(e)}", 400)
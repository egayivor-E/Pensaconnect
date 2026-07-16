from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
# Import the new EventReminder model
from backend.models import Event, EventAttendee, EventReminder, EventType, User, Activity, Notification
from backend.extensions import db
from .utils import success_response, error_response, broadcast_new_activity
# Reuse the notification-type helper already established by the forum
# reply-notification feature instead of duplicating it here.
from .forums import get_or_create_notification_type, roles_required
from datetime import datetime, timezone 
import json # Import json for JSON handling if needed
import logging

logger = logging.getLogger(__name__)

# Hard cap on how many users get a bulk notification row per event, so a
# very large church doesn't turn "create event" into a slow, giant insert.
MAX_EVENT_NOTIFICATION_RECIPIENTS = 3000

# ✅ Use url_prefix without trailing slash
events_bp = Blueprint("events", __name__, url_prefix="/events")


# --- Helpers ---

def resolve_event_type_id(data: dict) -> int:
    """
    Event.event_type is a relationship to EventType, not a plain string
    column — Event.event_type_id is the real FK. Older client code sent
    a raw string as `event_type`, which was being assigned straight to
    the relationship attribute and would break at flush/commit (or get
    silently clobbered) since SQLAlchemy expects an EventType instance
    there, not a string.

    This accepts either:
      - event_type_id (int): used directly
      - event_type (str, a name): looked up against EventType.name

    Raises KeyError if neither is present, ValueError if a name is
    given but doesn't match any known EventType.
    """
    if data.get("event_type_id") is not None:
        return data["event_type_id"]

    name = data.get("event_type")
    if name:
        event_type = EventType.query.filter_by(name=name).first()
        if not event_type:
            raise ValueError(f"Unknown event_type: {name!r}")
        return event_type.id

    raise KeyError("event_type_id")


def notify_new_event(event: "Event", creator: User):
    """Broadcast a notification to active users when a new event is
    created, so it surfaces in their notification bell. Best-effort and
    isolated in its own try/except + commit — same reasoning as
    notify_reply/broadcast_new_activity: a notification hiccup must
    never turn an already-successful event creation into an error
    response.

    Uses a bulk INSERT (session.bulk_insert_mappings) rather than one
    ORM object + commit per recipient, since this can fan out to
    thousands of users and per-row commits would make event creation
    unacceptably slow.
    """
    try:
        from uuid import uuid4

        nt = get_or_create_notification_type("new_event")

        recipients = (
            User.query
            .filter(User.status == "active", User.id != creator.id)
            .with_entities(User.id)
            .limit(MAX_EVENT_NOTIFICATION_RECIPIENTS)
            .all()
        )
        if not recipients:
            return

        now = datetime.now(timezone.utc)
        title = "New event: " + event.title
        message = f"{creator.get_full_name()} created a new event: {event.title}."

        rows = [
            {
                "uuid": str(uuid4()),
                "user_id": user_id,
                "notification_type_id": nt.id,
                "title": title,
                "message": message,
                "action_url": f"/events/{event.id}",
                "action_label": "View event",
                "source_id": event.id,
                "is_read": False,
                "is_delivered": False,
                "priority": 1,
                "notification_meta": {},
                "created_at": now,
                "updated_at": now,
                "is_active": True,
            }
            for (user_id,) in recipients
        ]
        db.session.bulk_insert_mappings(Notification, rows)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        logger.error(f"Failed to create event notifications for event {event.id}: {e}")


# --- EXISTING EVENT ROUTES (Keep as-is) ---

# ✅ GET /api/v1/events/types — populates the admin create-event dropdown
@events_bp.route("/types", methods=["GET"])
def list_event_types():
    types = EventType.query.order_by(EventType.name.asc()).all()
    return success_response([{"id": t.id, "name": t.name} for t in types])


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


# ✅ POST /api/v1/events — admin/moderator only, same gate the frontend's
# Add Event FAB uses (EventsScreen.isAdmin), now enforced server-side too.
@events_bp.route("", methods=["POST"])
@roles_required("admin", "moderator")
def create_event():
    user_id = get_jwt_identity()
    data = request.get_json()

    try:
        event_type_id = resolve_event_type_id(data)

        event = Event(
            user_id=user_id,
            title=data["title"],
            description=data["description"],
            start_time=datetime.fromisoformat(data["start_time"]),
            end_time=datetime.fromisoformat(data["end_time"]),
            location=data.get("location"),
            is_virtual=data.get("is_virtual", False),
            event_type_id=event_type_id,
        )
        db.session.add(event)
        db.session.commit()

        current_user = User.query.get(user_id)

        # Activity feed logging — same pattern as posts.py/testimonies.py/forums.py.
        # Runs in its own try/except and commit so a logging failure can't
        # turn an already-successful event creation into an error response.
        try:
            activity = Activity(
                title=f"{current_user.get_full_name()} created a new event",
                subtitle=(event.description or event.title)[:140],
                icon="event",
                color="blue",
                user_id=user_id,
                target_type="event",
                target_id=event.id,
            )
            db.session.add(activity)
            db.session.commit()
            broadcast_new_activity(activity)
        except Exception:
            logger.exception("Failed to log activity for event %s", event.id)
            db.session.rollback()

        # Notify users — same isolated best-effort pattern as the
        # activity log above.
        notify_new_event(event, current_user)

        return success_response(event.to_dict(), "Event created", 201)
    except KeyError as e:
        db.session.rollback()
        return error_response(f"Missing required field: {str(e)}", 400)
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to create event: {str(e)}", 400)

# ✅ PATCH /api/v1/events/<event_id> — admin/moderator only
@events_bp.route("/<int:event_id>", methods=["PATCH"])
@roles_required("admin", "moderator")
def update_event(event_id: int):
    event = Event.query.get_or_404(event_id)
    data = request.get_json()

    try:
        for key in [
            "title", "description", "start_time", "end_time",
            "location", "is_virtual",
        ]:
            if key in data:
                if key in ["start_time", "end_time"]:
                    setattr(event, key, datetime.fromisoformat(data[key]))
                else:
                    setattr(event, key, data[key])

        # event_type is a relationship, not a plain column — resolve to
        # the FK instead of assigning a raw string/dict onto it directly.
        if "event_type_id" in data or "event_type" in data:
            event.event_type_id = resolve_event_type_id(data)

        event.updated_at = datetime.utcnow()
        db.session.commit()
        return success_response(event.to_dict(), "Event updated")
    except Exception as e:
        db.session.rollback()
        return error_response(f"Failed to update event: {str(e)}", 400)


# ✅ DELETE /api/v1/events/<event_id> — admin/moderator only
@events_bp.route("/<int:event_id>", methods=["DELETE"])
@roles_required("admin", "moderator")
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

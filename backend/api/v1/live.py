# backend/routes/messages.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import Message, User
from datetime import datetime, timezone
from uuid import uuid4

live_bp = Blueprint("live_messages", __name__, url_prefix="/live/messages")

# --- Utility responses ---
def success_response(data=None, message="Success", status=200):
    return jsonify({"status": "success", "message": message, "data": data}), status

def error_response(message="Error", status=400):
    return jsonify({"status": "error", "message": message}), status


# --- Live Messages ---
@live_bp.route("/", methods=["GET"])
@jwt_required()
def get_live_messages():
    # You can customize live messages filtering by "group_id='live'" or other logic
    messages = Message.query.filter_by(group_id="live", is_active=True).order_by(Message.timestamp.asc()).all()
    return success_response([msg.to_dict() for msg in messages])

@live_bp.route("/", methods=["POST"])
@jwt_required()
def send_live_message():
    user_id = get_jwt_identity()
    data = request.get_json()
    content = data.get("content", "").strip()

    if not content:
        return error_response("Message content cannot be empty")

    message = Message(
        uuid=str(uuid4()),
        group_id="live",
        sender_id=user_id,
        content=content,
        timestamp=datetime.now(timezone.utc)
    )
    db.session.add(message)
    db.session.commit()
    return success_response(message.to_dict(), "Live message sent", 201)

# backend/routes/messages.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import Message, User
from datetime import datetime, timezone
from uuid import uuid4

messages_bp = Blueprint("messages", __name__, url_prefix="/messages")


# --- Utility responses ---
def success_response(data=None, message="Success", status=200):
    return jsonify({"status": "success", "message": message, "data": data}), status

def error_response(message="Error", status=400):
    return jsonify({"status": "error", "message": message}), status

# --- Messages by Group ---
@messages_bp.route("/<group_id>", methods=["GET"])
@jwt_required()
def get_group_messages(group_id):
    messages = Message.query.filter_by(group_id=group_id, is_active=True).order_by(Message.timestamp.asc()).all()
    return success_response([msg.to_dict() for msg in messages])

@messages_bp.route("/<group_id>", methods=["POST"])
@jwt_required()
def send_group_message(group_id):
    user_id = get_jwt_identity()
    data = request.get_json()
    content = data.get("content", "").strip()

    if not content:
        return error_response("Message content cannot be empty")

    message = Message(
        uuid=str(uuid4()),
        group_id=group_id,
        sender_id=user_id,
        content=content,
        timestamp=datetime.now(timezone.utc)
    )
    db.session.add(message)
    db.session.commit()
    return success_response(message.to_dict(), "Message sent", 201)


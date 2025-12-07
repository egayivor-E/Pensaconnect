# backend/routes/messages.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import GroupMessage, User, GroupChat
from datetime import datetime, timezone
from uuid import uuid4
import logging

logger = logging.getLogger(__name__)

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
    """Get messages for a specific group"""
    try:
        # ✅ CONVERT GROUP_ID TO INTEGER
        try:
            group_id_int = int(group_id)
        except ValueError:
            return error_response("Invalid group ID format", 400)
            
        current_user_id = get_jwt_identity()
        
        # Verify group exists and user has access
        group = GroupChat.query.get(group_id_int)  # ✅ USE INTEGER
        if not group:
            return error_response("Group not found", 404)
        
        # Get messages with pagination
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)
        
        messages = GroupMessage.query.filter_by(
            group_chat_id=group_id_int,  # ✅ USE INTEGER
            is_active=True
        ).order_by(GroupMessage.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        # Format response with sender information
        formatted_messages = []
        for msg in messages.items:
            message_data = msg.to_dict()
            
            # Add sender information
            sender = User.query.get(msg.sender_id)
            if sender:
                message_data['sender'] = {
                    'id': sender.id,
                    'username': sender.username,
                    'full_name': getattr(sender, 'full_name', sender.username),
                    'profile_picture': getattr(sender, 'profile_picture', None)
                }
            
            formatted_messages.append(message_data)
        
        response_data = {
            'messages': formatted_messages,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': messages.total,
                'pages': messages.pages
            }
        }
        
        logger.info(f"User {current_user_id} retrieved {len(formatted_messages)} messages from group {group_id_int}")
        return success_response(response_data, "Messages retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving messages for group {group_id}: {str(e)}")
        return error_response(f"Failed to retrieve messages: {str(e)}", 500)

@messages_bp.route("/<group_id>", methods=["POST"])
@jwt_required()
def send_group_message(group_id):
    """Send a message to a specific group"""
    try:
        # ✅ CONVERT GROUP_ID TO INTEGER
        try:
            group_id_int = int(group_id)
        except ValueError:
            return error_response("Invalid group ID format", 400)
            
        user_id = get_jwt_identity()
        data = request.get_json()
        
        content = data.get("content", "").strip()
        message_type = data.get("message_type", "text")

        if not content:
            return error_response("Message content cannot be empty")
        
        # Validate content length
        if len(content) > 1000:
            return error_response("Message too long. Maximum 1000 characters allowed.")
        
        # Verify group exists and user has access
        group = GroupChat.query.get(group_id_int)  # ✅ USE INTEGER
        if not group:
            return error_response("Group not found", 404)
        
        # Create the message
        message = GroupMessage(
            group_chat_id=group_id_int,  # ✅ USE INTEGER
            sender_id=user_id,
            content=content,
            message_type=message_type,
            attachments=data.get('attachments', []),
            read_by=[user_id],
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
            is_active=True
        )
        
        db.session.add(message)
        db.session.commit()
        
        # Format response with sender information
        message_data = message.to_dict()
        sender = User.query.get(user_id)
        if sender:
            message_data['sender'] = {
                'id': sender.id,
                'username': sender.username,
                'full_name': getattr(sender, 'full_name', sender.username),
                'profile_picture': getattr(sender, 'profile_picture', None)
            }
        
        logger.info(f"User {user_id} sent message to group {group_id_int}: {content[:50]}...")
        return success_response(message_data, "Message sent successfully", 201)
        
    except Exception as e:
        logger.error(f"Error sending message to group {group_id}: {str(e)}")
        db.session.rollback()
        return error_response(f"Failed to send message: {str(e)}", 500)

# --- Group Members ---
@messages_bp.route("/<group_id>/members", methods=["GET"])
@jwt_required()
def get_group_members(group_id):
    """Get members of a specific group"""
    try:
        # ✅ CONVERT GROUP_ID TO INTEGER
        try:
            group_id_int = int(group_id)
        except ValueError:
            return error_response("Invalid group ID format", 400)
            
        current_user_id = get_jwt_identity()
        
        # Verify group exists
        group = GroupChat.query.get(group_id_int)  # ✅ USE INTEGER
        if not group:
            return error_response("Group not found", 404)
        
        # Get group members (this would depend on your group membership model)
        # For now, return all users as a simple implementation
        # You should replace this with your actual group membership logic
        members = User.query.filter_by(is_active=True).limit(100).all()
        
        formatted_members = []
        for member in members:
            member_data = {
                'id': member.id,
                'username': member.username,
                'full_name': getattr(member, 'full_name', member.username),
                'profile_picture': getattr(member, 'profile_picture', None),
                'is_online': True,  # You would track online status separately
                'last_seen': datetime.now(timezone.utc).isoformat()
            }
            formatted_members.append(member_data)
        
        logger.info(f"User {current_user_id} retrieved {len(formatted_members)} members from group {group_id_int}")
        return success_response(formatted_members, "Group members retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving members for group {group_id}: {str(e)}")
        return error_response(f"Failed to retrieve group members: {str(e)}", 500)

# --- Message Actions ---
@messages_bp.route("/<message_id>/read", methods=["POST"])
@jwt_required()
def mark_message_read(message_id):
    """Mark a message as read by the current user"""
    try:
        # ✅ CONVERT MESSAGE_ID TO INTEGER
        try:
            message_id_int = int(message_id)
        except ValueError:
            return error_response("Invalid message ID format", 400)
            
        user_id = get_jwt_identity()
        
        message = GroupMessage.query.get(message_id_int)  # ✅ USE INTEGER
        if not message:
            return error_response("Message not found", 404)
        
        # Add user to read_by list if not already there
        if user_id not in message.read_by:
            message.read_by.append(user_id)
            message.updated_at = datetime.now(timezone.utc)
            db.session.commit()
            
            logger.info(f"User {user_id} marked message {message_id_int} as read")
            return success_response(None, "Message marked as read")
        else:
            return success_response(None, "Message already read")
            
    except Exception as e:
        logger.error(f"Error marking message {message_id} as read: {str(e)}")
        db.session.rollback()
        return error_response(f"Failed to mark message as read: {str(e)}", 500)

# --- Group Statistics ---
@messages_bp.route("/<group_id>/stats", methods=["GET"])
@jwt_required()
def get_group_stats(group_id):
    """Get statistics for a group"""
    try:
        # ✅ CONVERT GROUP_ID TO INTEGER
        try:
            group_id_int = int(group_id)
        except ValueError:
            return error_response("Invalid group ID format", 400)
            
        current_user_id = get_jwt_identity()
        
        # Verify group exists
        group = GroupChat.query.get(group_id_int)  # ✅ USE INTEGER
        if not group:
            return error_response("Group not found", 404)
        
        # Get message count
        message_count = GroupMessage.query.filter_by(
            group_chat_id=group_id_int,  # ✅ USE INTEGER
            is_active=True
        ).count()
        
        # Get member count (replace with actual group membership count)
        member_count = User.query.filter_by(is_active=True).count()
        
        # Get last activity
        last_message = GroupMessage.query.filter_by(
            group_chat_id=group_id_int,  # ✅ USE INTEGER
            is_active=True
        ).order_by(GroupMessage.created_at.desc()).first()
        
        stats = {
            'message_count': message_count,
            'member_count': member_count,
            'last_activity': last_message.created_at.isoformat() if last_message else None
        }
        
        logger.info(f"User {current_user_id} retrieved stats for group {group_id_int}")
        return success_response(stats, "Group statistics retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving stats for group {group_id}: {str(e)}")
        return error_response(f"Failed to retrieve group statistics: {str(e)}", 500)
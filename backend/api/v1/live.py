# backend/routes/live.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import Message, User, GroupChat, GroupMember
from backend.config import Config
from datetime import datetime, timezone
from uuid import uuid4
import logging

logger = logging.getLogger(__name__)

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
    """Get messages for live stream"""
    try:
        # Use configurable live stream group ID
        group_id = Config.LIVE_STREAM_GROUP_ID
        
        # Optional: Add pagination
        limit = request.args.get('limit', 100, type=int)
        
        messages = Message.query.filter_by(
            group_id=group_id, 
            is_active=True
        ).order_by(Message.timestamp.asc()).limit(limit).all()
        
        # Include sender information
        messages_data = []
        for msg in messages:
            msg_data = msg.to_dict()
            # Add sender details
            sender = User.query.get(msg.sender_id)
            if sender:
                msg_data['sender'] = {
                    'id': sender.id,
                    'username': sender.username,
                    'profile_picture': getattr(sender, 'profile_picture', None)
                }
            messages_data.append(msg_data)
        
        return success_response(messages_data, "Live messages retrieved")
        
    except Exception as e:
        logger.error(f"Error retrieving live messages: {str(e)}")
        return error_response("Failed to retrieve messages", 500)

@live_bp.route("/", methods=["POST"])
@jwt_required()
def send_live_message():
    """Send message to live stream"""
    try:
        user_id = get_jwt_identity()
        data = request.get_json()
        
        if not data:
            return error_response("No JSON data provided")
            
        content = data.get("content", "").strip()

        if not content:
            return error_response("Message content cannot be empty")
            
        # Content validation
        if len(content) > 1000:
            return error_response("Message too long. Maximum 1000 characters.")
            
        # Check rate limiting (you might want to implement this)
        # if is_rate_limited(user_id):
        #     return error_response("Message rate limit exceeded", 429)

        message = Message(
            uuid=str(uuid4()),
            group_id=Config.LIVE_STREAM_GROUP_ID,  # Configurable
            sender_id=user_id,
            content=content,
            timestamp=datetime.now(timezone.utc)
        )
        
        db.session.add(message)
        db.session.commit()
        
        # Prepare response with sender info
        response_data = message.to_dict()
        sender = User.query.get(user_id)
        if sender:
            response_data['sender'] = {
                'id': sender.id,
                'username': sender.username,
                'profile_picture': getattr(sender, 'profile_picture', None)
            }
        
        logger.info(f"Live message sent by user {user_id}")
        return success_response(response_data, "Live message sent", 201)
        
    except Exception as e:
        logger.error(f"Error sending live message: {str(e)}")
        db.session.rollback()
        return error_response("Failed to send message", 500)

# --- Live Stream Members ---
@live_bp.route("/members", methods=["GET"])
@jwt_required()
def get_live_members():
    """Get members for the live stream"""
    try:
        current_user_id = get_jwt_identity()
        
        # Use the live stream group ID from config
        group_id = Config.LIVE_STREAM_GROUP_ID
        
        # Verify the live stream group exists
        group = GroupChat.query.get(group_id)
        if not group:
            return error_response("Live stream group not found", 404)
        
        # Get actual group members (replace with your membership logic)
        # This depends on your group membership model structure
        group_members = GroupMember.query.filter_by(
            group_chat_id=group_id,
            is_active=True
        ).all()
        
        formatted_members = []
        for group_member in group_members:
            member = group_member.user  # Assuming you have a relationship
            if member and member.is_active:
                member_data = {
                    'id': member.id,
                    'username': member.username,
                    'full_name': getattr(member, 'full_name', member.username),
                    'profile_picture': getattr(member, 'profile_picture', None),
                    'is_online': getattr(member, 'is_online', False),
                    'last_seen': getattr(member, 'last_seen', datetime.now(timezone.utc)).isoformat()
                }
                formatted_members.append(member_data)
        
        logger.info(f"User {current_user_id} retrieved {len(formatted_members)} live stream members")
        return success_response(formatted_members, "Live stream members retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving live stream members: {str(e)}")
        return error_response(f"Failed to retrieve live stream members: {str(e)}", 500)

# --- Live Stream Statistics ---
@live_bp.route("/stats", methods=["GET"])
@jwt_required()
def get_live_stats():
    """Get live stream statistics"""
    try:
        current_user_id = get_jwt_identity()
        group_id = Config.LIVE_STREAM_GROUP_ID
        
        # Get message count for live stream
        message_count = Message.query.filter_by(
            group_id=group_id,
            is_active=True
        ).count()
        
        # Get member count
        member_count = GroupMember.query.filter_by(
            group_chat_id=group_id,
            is_active=True
        ).count()
        
        # Get last activity
        last_message = Message.query.filter_by(
            group_id=group_id,
            is_active=True
        ).order_by(Message.timestamp.desc()).first()
        
        stats = {
            'message_count': message_count,
            'member_count': member_count,
            'last_activity': last_message.timestamp.isoformat() if last_message else None,
            'is_live': True,  # You can add live stream status logic here
            'group_id': group_id
        }
        
        logger.info(f"User {current_user_id} retrieved live stream stats")
        return success_response(stats, "Live stream stats retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving live stream stats: {str(e)}")
        return error_response(f"Failed to retrieve live stream stats: {str(e)}", 500)

# --- Live Stream Info ---
@live_bp.route("/info", methods=["GET"])
@jwt_required()
def get_live_info():
    """Get live stream information"""
    try:
        current_user_id = get_jwt_identity()
        group_id = Config.LIVE_STREAM_GROUP_ID
        
        # Get live stream group info
        group = GroupChat.query.get(group_id)
        if not group:
            return error_response("Live stream group not found", 404)
        
        # Get basic info
        info = {
            'group_id': group_id,
            'group_name': getattr(group, 'name', 'Live Stream'),
            'description': getattr(group, 'description', 'Live Stream Chat'),
            'is_active': True,
            'created_at': getattr(group, 'created_at', datetime.now(timezone.utc)).isoformat(),
            'total_messages': Message.query.filter_by(group_id=group_id, is_active=True).count(),
            'total_members': GroupMember.query.filter_by(group_chat_id=group_id, is_active=True).count()
        }
        
        logger.info(f"User {current_user_id} retrieved live stream info")
        return success_response(info, "Live stream info retrieved successfully")
        
    except Exception as e:
        logger.error(f"Error retrieving live stream info: {str(e)}")
        return error_response(f"Failed to retrieve live stream info: {str(e)}", 500)

# --- Check Live Stream Status ---
@live_bp.route("/status", methods=["GET"])
@jwt_required()
def get_live_status():
    """Check if live stream is active"""
    try:
        group_id = Config.LIVE_STREAM_GROUP_ID
        
        # Check if live stream group exists and is active
        group = GroupChat.query.get(group_id)
        if not group:
            return success_response({'is_active': False, 'reason': 'Group not found'})
        
        # You can add more sophisticated live stream status logic here
        # For example, check if there's been recent activity, etc.
        last_message = Message.query.filter_by(
            group_id=group_id,
            is_active=True
        ).order_by(Message.timestamp.desc()).first()
        
        is_active = True  # Default to active, add your logic here
        
        status_info = {
            'is_active': is_active,
            'group_id': group_id,
            'last_activity': last_message.timestamp.isoformat() if last_message else None,
            'total_viewers': GroupMember.query.filter_by(group_chat_id=group_id, is_active=True).count()
        }
        
        return success_response(status_info, "Live stream status retrieved")
        
    except Exception as e:
        logger.error(f"Error checking live stream status: {str(e)}")
        return error_response(f"Failed to check live stream status: {str(e)}", 500)
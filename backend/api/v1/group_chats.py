from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import GroupChat, GroupMember, GroupMessage, User, GroupMemberRole

# Blueprint registered under /api/v1/group-chats
group_chats_bp = Blueprint("group_chats", __name__, url_prefix="/group-chats")

# ---------------------------
# Create a new group chat
# ---------------------------
@group_chats_bp.route("/", methods=["POST"])
@jwt_required()
def create_group_chat():
    data = request.get_json()
    user_id = get_jwt_identity()

    group_chat = GroupChat(
        name=data.get("name"),
        description=data.get("description"),
        avatar=data.get("avatar"),
        is_public=data.get("is_public", True),
        max_members=data.get("max_members", 100),
        tags=data.get("tags", []),
        created_by_id=user_id,
    )

    db.session.add(group_chat)
    db.session.flush()  # Get ID without committing

    # Add creator as admin member
    group_member = GroupMember(
        group_chat_id=group_chat.id,
        user_id=user_id,
        group_role="admin"
    )
    db.session.add(group_member)
    db.session.commit()

    return jsonify(group_chat.to_dict()), 201


# ---------------------------
# Get all group chats user belongs to
# ---------------------------
@group_chats_bp.route("/", methods=["GET"])
@jwt_required()
def get_group_chats():
    user_id = get_jwt_identity()
    
    # Get user's active group memberships
    memberships = GroupMember.query.filter_by(
        user_id=user_id, 
        is_active=True
    ).all()
    
    group_ids = [membership.group_chat_id for membership in memberships]
    
    # Get the actual group chats
    group_chats = GroupChat.query.filter(
        GroupChat.id.in_(group_ids),
        GroupChat.is_active == True
    ).order_by(GroupChat.created_at.desc()).all()
    
    # ❌ PREVIOUS: return jsonify([gc.to_dict() for gc in group_chats])
    # ✅ FIX: Wrap the list in a dictionary with 'data', 'message', and 'status' keys
    return jsonify({
        "data": [gc.to_dict() for gc in group_chats],
        "message": "Groups fetched successfully",
        "status": "success"
    }), 200 # Ensure the status code is 200

# ---------------------------
# Get single group chat with members
# ---------------------------
@group_chats_bp.route("/<int:group_id>", methods=["GET"])
@jwt_required()
def get_group_chat(group_id):
    user_id = get_jwt_identity()
    
    # Check if user is member of the group
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership:
        return jsonify({"error": "Access denied or group not found"}), 403
    
    group_chat = GroupChat.query.get_or_404(group_id)
    return jsonify(group_chat.to_dict(include_members=True))




# Update a group chat
# ---------------------------
@group_chats_bp.route("/<int:group_id>", methods=["PUT"])
@jwt_required()
def update_group_chat(group_id):
    group_chat = GroupChat.query.get_or_404(group_id)
    user_id = get_jwt_identity()

    # Check if user is admin of the group - ✅ FIXED: Use string comparison
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership or membership.group_role != "admin":  # ✅ Use string
        return jsonify({"error": "Unauthorized - Admin access required"}), 403

    data = request.get_json()
    group_chat.name = data.get("name", group_chat.name)
    group_chat.description = data.get("description", group_chat.description)
    group_chat.avatar = data.get("avatar", group_chat.avatar)
    group_chat.is_public = data.get("is_public", group_chat.is_public)
    group_chat.max_members = data.get("max_members", group_chat.max_members)
    group_chat.tags = data.get("tags", group_chat.tags)

    db.session.commit()
    return jsonify(group_chat.to_dict())


# ---------------------------
# Delete a group chat
# ---------------------------
@group_chats_bp.route("/<int:group_id>", methods=["DELETE"])
@jwt_required()
def delete_group_chat(group_id):
    group_chat = GroupChat.query.get_or_404(group_id)
    user_id = get_jwt_identity()

    # Check if user is admin of the group - ✅ FIXED: Use string comparison
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership or membership.group_role != "admin":  # ✅ Use string
        return jsonify({"error": "Unauthorized - Admin access required"}), 403

    # Soft delete the group chat
    group_chat.is_active = False
    db.session.commit()
    
    return jsonify({"message": "Group chat deleted"})


# ---------------------------
# Join a group chat
# ---------------------------
@group_chats_bp.route("/<int:group_id>/join", methods=["POST"])
@jwt_required()
def join_group_chat(group_id):
    group_chat = GroupChat.query.get_or_404(group_id)
    user_id = get_jwt_identity()

    # Check if group is public
    if not group_chat.is_public:
        return jsonify({"error": "This group is private"}), 403

    # Check if already a member
    existing_member = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id
    ).first()

    if existing_member:
        if existing_member.is_active:
            return jsonify({"error": "Already a member of this group"}), 400
        else:
            # Reactivate membership - ✅ FIXED: Use string
            existing_member.is_active = True
            existing_member.group_role = "member"  # ✅ Use string
    else:
        # Check if group is full
        active_members = GroupMember.query.filter_by(
            group_chat_id=group_id,
            is_active=True
        ).count()
        
        if active_members >= group_chat.max_members:
            return jsonify({"error": "Group is full"}), 400
        
        # Create new membership - ✅ FIXED: Use string
        group_member = GroupMember(
            group_chat_id=group_id,
            user_id=user_id,
            group_role="member"  # ✅ Use string
        )
        db.session.add(group_member)

    db.session.commit()
    return jsonify({"message": "Successfully joined group"}), 200


# ---------------------------
# Leave a group chat
# ---------------------------
@group_chats_bp.route("/<int:group_id>/leave", methods=["POST"])
@jwt_required()
def leave_group_chat(group_id):
    user_id = get_jwt_identity()

    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()

    if not membership:
        return jsonify({"error": "Not a member of this group"}), 400

    # If user is the last admin, don't allow leaving - ✅ FIXED: Use string comparison
    if membership.group_role == "admin":  # ✅ Use string
        admin_count = GroupMember.query.filter_by(
            group_chat_id=group_id,
            group_role="admin",  # ✅ Use string
            is_active=True
        ).count()
        
        if admin_count == 1:
            return jsonify({"error": "Cannot leave as the only admin. Transfer admin rights first."}), 400

    # Soft delete membership
    membership.is_active = False
    db.session.commit()
    
    return jsonify({"message": "Successfully left group"}), 200


# ---------------------------
# Get group members
# ---------------------------
@group_chats_bp.route("/<int:group_id>/members", methods=["GET"])
@jwt_required()
def get_group_members(group_id):
    user_id = get_jwt_identity()
    
    # Check if user is member of the group
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership:
        return jsonify({"error": "Access denied"}), 403
    
    members = GroupMember.query.filter_by(
        group_chat_id=group_id,
        is_active=True
    ).order_by(GroupMember.group_role.desc(), GroupMember.joined_at).all()
    
    return jsonify([member.to_dict() for member in members])


# ---------------------------
# Update member role (Admin only)
# ---------------------------
@group_chats_bp.route("/<int:group_id>/members/<int:member_id>/role", methods=["PUT"])
@jwt_required()
def update_member_role(group_id, member_id):
    user_id = get_jwt_identity()
    data = request.get_json()
    new_role = data.get("role")

    # Check if requester is admin - ✅ FIXED: Use string comparison
    requester_membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not requester_membership or requester_membership.group_role != "admin":  # ✅ Use string
        return jsonify({"error": "Unauthorized - Admin access required"}), 403

    # Find target member
    target_membership = GroupMember.query.filter_by(
        id=member_id,
        group_chat_id=group_id,
        is_active=True
    ).first_or_404()

    # Validate role - ✅ FIXED: Check against string values
    valid_roles = ["admin", "moderator", "member"]
    if new_role not in valid_roles:
        return jsonify({"error": "Invalid role"}), 400

    # ✅ FIXED: Assign string directly
    target_membership.group_role = new_role
    db.session.commit()
    
    return jsonify(target_membership.to_dict())


# ---------------------------
# Remove member from group (Admin only)
# ---------------------------
@group_chats_bp.route("/<int:group_id>/members/<int:member_id>", methods=["DELETE"])
@jwt_required()
def remove_member(group_id, member_id):
    user_id = get_jwt_identity()

    # Check if requester is admin - ✅ FIXED: Use string comparison
    requester_membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not requester_membership or requester_membership.group_role != "admin":  # ✅ Use string
        return jsonify({"error": "Unauthorized - Admin access required"}), 403

    # Find target member
    target_membership = GroupMember.query.filter_by(
        id=member_id,
        group_chat_id=group_id
    ).first_or_404()

    # Prevent removing yourself as admin - ✅ FIXED: Use string comparison
    if target_membership.user_id == user_id and target_membership.group_role == "admin":  # ✅ Use string
        admin_count = GroupMember.query.filter_by(
            group_chat_id=group_id,
            group_role="admin",  # ✅ Use string
            is_active=True
        ).count()
        
        if admin_count == 1:
            return jsonify({"error": "Cannot remove yourself as the only admin"}), 400

    target_membership.is_active = False
    db.session.commit()
    
    return jsonify({"message": "Member removed from group"}), 200


# ---------------------------
# Send a message to group
# ---------------------------
@group_chats_bp.route("/<int:group_id>/messages", methods=["POST"])
@jwt_required()
def send_message(group_id):
    data = request.get_json()
    user_id = get_jwt_identity()

    # Check if user is member of the group
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership:
        return jsonify({"error": "Access denied or group not found"}), 403

    message = GroupMessage(
        group_chat_id=group_id,
        sender_id=user_id,
        content=data.get("content"),
        message_type=data.get("message_type", "text"),
        attachments=data.get("attachments", []),
        replied_to_id=data.get("replied_to_id")
    )

    db.session.add(message)
    db.session.commit()
    return jsonify(message.to_dict()), 201


# ---------------------------
# Get group messages
# ---------------------------
@group_chats_bp.route("/<int:group_id>/messages", methods=["GET"])
@jwt_required()
def get_messages(group_id):
    user_id = get_jwt_identity()
    
    # Check if user is member of the group
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership:
        return jsonify({"error": "Access denied"}), 403
    
    messages = GroupMessage.query.filter_by(
        group_chat_id=group_id,
        is_active=True
    ).order_by(GroupMessage.created_at.asc()).all()
    
    return jsonify([message.to_dict() for message in messages])


# ---------------------------
# Delete a message (sender or admin only)
# ---------------------------
@group_chats_bp.route("/<int:group_id>/messages/<int:message_id>", methods=["DELETE"])
@jwt_required()
def delete_message(group_id, message_id):
    user_id = get_jwt_identity()

    # Check if user is member of the group
    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True
    ).first()
    
    if not membership:
        return jsonify({"error": "Access denied"}), 403

    message = GroupMessage.query.filter_by(
        id=message_id,
        group_chat_id=group_id
    ).first_or_404()

    # Check if user is message sender or admin - ✅ FIXED: Use string comparison
    if message.sender_id != user_id and membership.group_role != "admin":  # ✅ Use string
        return jsonify({"error": "Unauthorized"}), 403

    message.is_active = False
    db.session.commit()
    
    return jsonify({"message": "Message deleted"}), 200
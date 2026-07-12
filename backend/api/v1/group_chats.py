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
        chat_type="group",
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
# Get-or-create a direct (1:1) chat with another user
# ---------------------------
@group_chats_bp.route("/direct/<int:other_user_id>", methods=["POST"])
@jwt_required()
def get_or_create_direct_chat(other_user_id):
    user_id = get_jwt_identity()

    # get_jwt_identity() is a string; compare as int consistently so the
    # self-DM check below (and the set-equality check further down) is
    # comparing like types either way.
    current_user_id = int(user_id)

    if current_user_id == other_user_id:
        return jsonify({"error": "Cannot start a direct chat with yourself"}), 400

    other_user = User.query.get(other_user_id)
    if not other_user:
        return jsonify({"error": "User not found"}), 404

    # A direct chat is just a GroupChat with chat_type='direct' and exactly
    # these two members — look for one that already exists between this
    # pair before creating a new one, so repeated taps on the same person
    # always land in the same conversation instead of forking a new one.
    candidate_chats = (
        db.session.query(GroupChat)
        .join(GroupMember, GroupMember.group_chat_id == GroupChat.id)
        .filter(
            GroupChat.chat_type == "direct",
            GroupChat.is_active == True,
            GroupMember.user_id == current_user_id,
            GroupMember.is_active == True,
        )
        .all()
    )
    for chat in candidate_chats:
        member_ids = {m.user_id for m in chat.members if m.is_active}
        if member_ids == {current_user_id, other_user_id}:
            return jsonify({
                "data": chat.to_dict(include_members=True),
                "message": "Direct chat already exists",
                "status": "success",
            }), 200

    group_chat = GroupChat(
        name=f"dm-{min(current_user_id, other_user_id)}-{max(current_user_id, other_user_id)}",
        description=None,
        is_public=False,
        max_members=2,
        chat_type="direct",
        created_by_id=current_user_id,
    )
    db.session.add(group_chat)
    db.session.flush()

    db.session.add(GroupMember(
        group_chat_id=group_chat.id, user_id=current_user_id, group_role="member"
    ))
    db.session.add(GroupMember(
        group_chat_id=group_chat.id, user_id=other_user_id, group_role="member"
    ))
    db.session.commit()

    return jsonify({
        "data": group_chat.to_dict(include_members=True),
        "message": "Direct chat created",
        "status": "success",
    }), 201


# ---------------------------
# Get all group chats user belongs to
# ---------------------------
@group_chats_bp.route("/", methods=["GET"])
@jwt_required()
def get_group_chats():
    user_id = get_jwt_identity()

    # Optional ?type=group or ?type=direct to fetch just one flavor —
    # e.g. the Group Chats screen wants only 'group', a DM inbox wants
    # only 'direct'. Omit it to get both, as before.
    chat_type = request.args.get("type")

    # Get user's active group memberships
    memberships = GroupMember.query.filter_by(
        user_id=user_id, 
        is_active=True
    ).all()
    
    group_ids = [membership.group_chat_id for membership in memberships]
    
    # Get the actual group chats
    query = GroupChat.query.filter(
        GroupChat.id.in_(group_ids),
        GroupChat.is_active == True
    )
    if chat_type in ("group", "direct"):
        query = query.filter(GroupChat.chat_type == chat_type)

    group_chats = query.order_by(GroupChat.created_at.desc()).all()
    
    # ❌ PREVIOUS: return jsonify([gc.to_dict() for gc in group_chats])
    # ✅ FIX: Wrap the list in a dictionary with 'data', 'message', and 'status' keys
    return jsonify({
        "data": [gc.to_dict() for gc in group_chats],
        "message": "Groups fetched successfully",
        "status": "success"
    }), 200 # Ensure the status code is 200


# ---------------------------
# Discover public groups the user hasn't joined yet
# ---------------------------
@group_chats_bp.route("/discover", methods=["GET"])
@jwt_required()
def discover_group_chats():
    user_id = get_jwt_identity()

    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)

    # Groups this user is already an active member of — excluded below so
    # "discover" only ever surfaces groups there's actually something to
    # join, instead of also listing groups already sitting in "my groups".
    joined_ids = [
        m.group_chat_id
        for m in GroupMember.query.filter_by(user_id=user_id, is_active=True).all()
    ]

    query = GroupChat.query.filter(
        GroupChat.chat_type == "group",
        GroupChat.is_public == True,
        GroupChat.is_active == True,
    )
    if joined_ids:
        query = query.filter(~GroupChat.id.in_(joined_ids))

    pagination = query.order_by(GroupChat.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    return jsonify({
        "data": [gc.to_dict() for gc in pagination.items],
        "page": pagination.page,
        "pages": pagination.pages,
        "total": pagination.total,
        "message": "Discoverable groups fetched successfully",
        "status": "success",
    }), 200

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

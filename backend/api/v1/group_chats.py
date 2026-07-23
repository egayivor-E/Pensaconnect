import logging
from datetime import datetime, timezone
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from backend.models import GroupChat, GroupMember, GroupMessage, User, GroupMemberRole

logger = logging.getLogger(__name__)

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
    query = GroupChat.query.options(db.joinedload(GroupChat.created_by)).filter(
        GroupChat.id.in_(group_ids),
        GroupChat.is_active == True
    )
    if chat_type in ("group", "direct"):
        query = query.filter(GroupChat.chat_type == chat_type)

    group_chats = query.order_by(GroupChat.created_at.desc()).all()

    # ✅ Batched member counts: to_dict() used to len() the full
    # `members` collection per group chat (a full row fetch just to
    # count), plus a lazy created_by query per row above without the
    # joinedload. One GROUP BY here covers every group on the list.
    chat_ids = [gc.id for gc in group_chats]
    member_counts = {}
    unread_counts = {}
    if chat_ids:
        member_counts = dict(
            db.session.query(GroupMember.group_chat_id, db.func.count(GroupMember.id))
            .filter(GroupMember.group_chat_id.in_(chat_ids), GroupMember.is_active == True)
            .group_by(GroupMember.group_chat_id)
            .all()
        )
        unread_counts = _batched_unread_counts(current_user_id=user_id, chat_ids=chat_ids)

    # ❌ PREVIOUS: return jsonify([gc.to_dict() for gc in group_chats])
    # ✅ FIX: Wrap the list in a dictionary with 'data', 'message', and 'status' keys
    return jsonify({
        "data": [
            gc.to_dict(
                member_count=member_counts.get(gc.id, 0),
                unread_count=unread_counts.get(gc.id, 0),
            )
            for gc in group_chats
        ],
        "message": "Groups fetched successfully",
        "status": "success"
    }), 200 # Ensure the status code is 200


def _batched_unread_counts(current_user_id, chat_ids=None):
    """Count of messages, per group chat, sent after this user's
    last_read_at watermark for that chat and not sent by the user
    themselves — one GROUP BY covering every chat in `chat_ids` (or every
    chat the user belongs to, if omitted), instead of a query per chat.
    Used for both the per-chat badges on the list endpoint and the
    all-chats total on /group-chats/unread-count.
    """
    query = (
        db.session.query(GroupMessage.group_chat_id, db.func.count(GroupMessage.id))
        .join(
            GroupMember,
            db.and_(
                GroupMember.group_chat_id == GroupMessage.group_chat_id,
                GroupMember.user_id == current_user_id,
                GroupMember.is_active == True,
            ),
        )
        .filter(
            GroupMessage.is_active == True,
            GroupMessage.sender_id != current_user_id,
            GroupMessage.created_at > GroupMember.last_read_at,
        )
    )
    if chat_ids is not None:
        if not chat_ids:
            return {}
        query = query.filter(GroupMessage.group_chat_id.in_(chat_ids))

    return dict(query.group_by(GroupMessage.group_chat_id).all())


# ---------------------------
# Total unread message count across all of the user's group chats —
# powers the badge on the floating chat button (mirrors
# /notifications/unread-count's shape: {"count": N}).
# ---------------------------
@group_chats_bp.route("/unread-count", methods=["GET"])
@jwt_required()
def unread_count():
    user_id = get_jwt_identity()
    counts = _batched_unread_counts(current_user_id=user_id)
    return jsonify({
        "data": {"count": sum(counts.values())},
        "message": "Unread count fetched successfully",
        "status": "success",
    }), 200


# ---------------------------
# Mark a chat as read for the current user — advances their read
# watermark to now, clearing its unread badge (mirrors POST
# /notifications/<id>/read).
# ---------------------------
@group_chats_bp.route("/<int:group_id>/read", methods=["POST"])
@jwt_required()
def mark_group_read(group_id):
    user_id = get_jwt_identity()

    membership = GroupMember.query.filter_by(
        group_chat_id=group_id,
        user_id=user_id,
        is_active=True,
    ).first()

    if not membership:
        return jsonify({"error": "Access denied or group not found"}), 403

    membership.last_read_at = datetime.now(timezone.utc)
    db.session.commit()

    return jsonify({
        "data": {"group_id": group_id, "last_read_at": membership.last_read_at.isoformat()},
        "message": "Chat marked as read",
        "status": "success",
    }), 200


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

    query = GroupChat.query.options(db.joinedload(GroupChat.created_by)).filter(
        GroupChat.chat_type == "group",
        GroupChat.is_public == True,
        GroupChat.is_active == True,
    )
    if joined_ids:
        query = query.filter(~GroupChat.id.in_(joined_ids))

    pagination = query.order_by(GroupChat.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    chat_ids = [gc.id for gc in pagination.items]
    member_counts = {}
    if chat_ids:
        member_counts = dict(
            db.session.query(GroupMember.group_chat_id, db.func.count(GroupMember.id))
            .filter(GroupMember.group_chat_id.in_(chat_ids), GroupMember.is_active == True)
            .group_by(GroupMember.group_chat_id)
            .all()
        )

    return jsonify({
        "data": [
            gc.to_dict(member_count=member_counts.get(gc.id, 0))
            for gc in pagination.items
        ],
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
    
    # ✅ joinedload(GroupMember.user): to_dict() reads member.user.*, so
    # without this every member in the list triggered its own lazy
    # SELECT on users — N+1 on a screen that's opened constantly.
    members = (
        GroupMember.query.options(db.joinedload(GroupMember.user))
        .filter_by(group_chat_id=group_id, is_active=True)
        .order_by(GroupMember.group_role.desc(), GroupMember.joined_at)
        .all()
    )
    
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

    _notify_new_message(group_id, message, sender_id=user_id)

    return jsonify(message.to_dict()), 201


def _notify_new_message(group_id: int, message, sender_id: int):
    """Push-notifies every other active member of the group about a new
    message. Best-effort and fully isolated from send_message() itself —
    a slow member list or a push failure must never fail the send that
    already succeeded and committed above. See
    backend/services/push_service.py.

    Sends to *every* other member regardless of whether they're
    currently connected over the socket — a push while the app is
    foregrounded/connected is a harmless no-op duplicate of what
    real-time already shows; the whole point is reaching members who
    aren't connected right now (app closed/backgrounded)."""
    try:
        from backend.services.push_service import send_push_to_user

        group = GroupChat.query.get(group_id)
        if not group:
            return

        sender = User.query.get(sender_id)
        sender_name = (
            sender.get_full_name()
            if sender and hasattr(sender, "get_full_name")
            else (sender.username if sender else "Someone")
        )

        body = (message.content or "Sent an attachment").strip()
        if len(body) > 120:
            body = body[:117] + "..."

        is_direct = group.chat_type == "direct"
        title = sender_name if is_direct else group.name
        push_body = body if is_direct else f"{sender_name}: {body}"

        recipients = GroupMember.query.filter(
            GroupMember.group_chat_id == group_id,
            GroupMember.is_active == True,  # noqa: E712
            GroupMember.user_id != sender_id,
        ).all()

        for member in recipients:
            recipient = User.query.get(member.user_id)
            send_push_to_user(
                recipient,
                title=title,
                body=push_body,
                data={
                    "type": "group_message",
                    "group_id": group_id,
                    "group_name": group.name,
                },
            )
    except Exception as e:
        logger.error(f"Failed to send group message push notifications: {e}")


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
    
    # ✅ Was an unbounded `.all()` with no eager loading: every open of a
    # chat re-fetched the group's *entire* message history (slower every
    # day the group is alive) and to_dict() triggered two extra lazy
    # queries per message (sender + replied_to) — 2N round trips for N
    # messages. Cap to the most recent page worth of history (matches
    # the per_page default in the paginated /messages/<group_id> route)
    # and eager-load both relationships in the single initial query.
    # Fetched newest-first so the LIMIT actually gets the *latest*
    # messages, then reversed back to chronological order for display.
    limit = request.args.get("limit", default=200, type=int)
    messages = (
        GroupMessage.query.options(
            db.joinedload(GroupMessage.sender),
            db.joinedload(GroupMessage.replied_to),
        )
        .filter_by(group_chat_id=group_id, is_active=True)
        .order_by(GroupMessage.created_at.desc())
        .limit(limit)
        .all()
    )
    messages.reverse()

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
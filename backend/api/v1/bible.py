import json
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy import or_
from datetime import datetime

from backend.models import db, User, Devotion, StudyPlan, StudyPlanProgress, Archive
from .utils import success_response, error_response, require_admin
from .forums import roles_required, get_current_user
from .document_extract import extract_text, DocumentExtractError
from .ai_assistant import generate_study_plan_draft, AssistantError

bible_bp = Blueprint("bible", __name__, url_prefix="/bible")

# ======================================================
# ---------------- Devotions ---------------------------
# ======================================================
@bible_bp.route("/devotions", methods=["GET"])
def list_devotions():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    date = request.args.get("date")

    # ✅ joinedload(author): to_dict(include_author=True) below reads
    # devotion.author.*, so without this every devotion on the page
    # triggered its own lazy SELECT on users.
    query = Devotion.query.options(db.joinedload(Devotion.author)).filter_by(is_active=True)

    if date:
        try:
            parsed = datetime.fromisoformat(date).date()
            query = query.filter(Devotion.date == parsed)
        except Exception:
            return error_response("Invalid date format. Use YYYY-MM-DD.", 400)

    pagination = query.order_by(Devotion.date.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    return success_response(
        {
            "items": [d.to_dict(include_author=True) for d in pagination.items],
            "total": pagination.total,
            "page": pagination.page,
            "pages": pagination.pages,
        }
    )


@bible_bp.route("/devotions/<int:devotion_id>", methods=["GET"])
def get_devotion(devotion_id):
    devotion = Devotion.query.get_or_404(devotion_id)
    return success_response(devotion.to_dict(include_author=True))


@bible_bp.route("/devotions", methods=["POST"])
@jwt_required()
def create_devotion():
    user, error = require_admin()
    if error:
        return error

    data = request.get_json()
    if not data or "title" not in data or "verse" not in data or "content" not in data:
        return error_response("Missing required fields: title, verse, content", 400)

    devotion = Devotion(
        title=data["title"],
        verse=data["verse"],
        content=data["content"],
        reflection=data.get("reflection"),
        prayer=data.get("prayer"),
        author_id=user.id,
    )
    db.session.add(devotion)
    db.session.commit()
    return success_response(devotion.to_dict(include_author=True), "Devotion created", 201)


@bible_bp.route("/devotions/<int:devotion_id>", methods=["PATCH"])
@jwt_required()
def update_devotion(devotion_id):
    user, error = require_admin()
    if error:
        return error

    devotion = Devotion.query.get_or_404(devotion_id)
    data = request.get_json()

    for field in ["title", "verse", "content", "reflection", "prayer"]:
        if field in data:
            setattr(devotion, field, data[field])

    db.session.commit()
    return success_response(devotion.to_dict(include_author=True), "Devotion updated")


@bible_bp.route("/devotions/<int:devotion_id>", methods=["DELETE"])
@jwt_required()
def delete_devotion(devotion_id):
    user, error = require_admin()
    if error:
        return error

    devotion = Devotion.query.get_or_404(devotion_id)
    db.session.delete(devotion)
    db.session.commit()
    return success_response({}, "Devotion deleted")


# ======================================================
# ---------------- Study Plans -------------------------
# ======================================================
@bible_bp.route("/plans", methods=["GET"])
@jwt_required(optional=True)
def list_plans():
    user_id = get_jwt_identity()

    # ✅ joinedload(author): to_dict(include_author=True) reads
    # plan.author.*, so without this every plan triggered its own lazy
    # SELECT on users (N+1). Also cap the previously-unbounded `.all()`
    # so this doesn't turn into a full table scan as plans accumulate —
    # matches the safety limit already used on the forum threads list.
    query = StudyPlan.query.options(db.joinedload(StudyPlan.author)).filter_by(is_active=True)

    if user_id:
        # Authenticated: show all public plans + user's own private plans
        query = query.filter(
            or_(StudyPlan.is_public == True, StudyPlan.author_id == user_id)
        )
    else:
        # Guests: only public plans
        query = query.filter(StudyPlan.is_public == True)

    plans = query.order_by(StudyPlan.created_at.desc()).limit(200).all()
    return success_response({"items": [p.to_dict(include_author=True) for p in plans]})


@bible_bp.route("/plans/<int:plan_id>", methods=["GET"])
def get_plan(plan_id):
    plan = StudyPlan.query.get_or_404(plan_id)
    return success_response(plan.to_dict(include_author=True))


@bible_bp.route("/plans", methods=["POST"])
@jwt_required()
def create_plan():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    data = request.get_json()
    if not data or "title" not in data:
        return error_response("Missing required field: title", 400)
    
    # FIX: Ensure level is uppercase to match enum
    level = data.get("level", "BEGINNER")
    if level:
        level = level.upper()  # Convert to uppercase
    
    # Validate level is one of the allowed values
    allowed_levels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'ALL_LEVELS']
    if level not in allowed_levels:
        level = 'BEGINNER'  # Default to BEGINNER if invalid

    # FIX: Check if user has admin role using 'roles' instead of 'role'
    is_public = data.get("is_public", False)
    
    # Check if user has admin role in their roles
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    
    if not is_admin:  # Only admins can create public plans
        is_public = False

    plan = StudyPlan(
        title=data["title"],
        description=data.get("description", ""),
        level=level,  # difficulty -> level
        total_days=data.get("total_days", data.get("day_count", 7)),  # Support both
        is_public=is_public,
        author_id=user.id,
    )
    
    # Handle verses if provided
    if "verses" in data and isinstance(data["verses"], list):
        plan.verses_json = json.dumps(data["verses"])

    # Handle per-day content if provided (e.g. from the AI document
    # importer, or hand-authored days from the create-plan screen).
    if "days" in data and isinstance(data["days"], list):
        plan.set_days(data["days"])

    db.session.add(plan)
    db.session.commit()
    return success_response(plan.to_dict(include_author=True), "Study plan created", 201)


@bible_bp.route("/plans/<int:plan_id>", methods=["PATCH"])
@jwt_required()
def update_plan(plan_id):
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    plan = StudyPlan.query.get_or_404(plan_id)

    # FIX: Check admin using roles
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    
    # Only admin or plan author can edit
    if not is_admin and plan.author_id != user.id:
        return error_response("Not authorized to update this plan", 403)

    data = request.get_json()
    for field in ["title", "description", "level", "total_days", "is_public", "is_active"]:
        if field in data:
            # only admins may toggle is_public
            if field == "is_public" and not is_admin:
                continue
            setattr(plan, field, data[field])

    if "verses" in data and isinstance(data["verses"], list):
        plan.verses_json = json.dumps(data["verses"])

    if "days" in data and isinstance(data["days"], list):
        plan.set_days(data["days"])

    db.session.commit()
    return success_response(plan.to_dict(include_author=True), "Study plan updated")


@bible_bp.route("/plans/<int:plan_id>/days", methods=["GET"])
def list_plan_days(plan_id):
    plan = StudyPlan.query.get_or_404(plan_id)
    return success_response(plan.get_days())


@bible_bp.route("/plans/<int:plan_id>/days/<int:day_number>", methods=["PATCH"])
@jwt_required()
def update_plan_day(plan_id, day_number):
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    plan = StudyPlan.query.get_or_404(plan_id)
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    if not is_admin and plan.author_id != user.id:
        return error_response("Not authorized to update this plan", 403)

    data = request.get_json() or {}
    days = plan.get_days()
    day = next((d for d in days if d.get("dayNumber") == day_number), None)
    if day is None:
        return error_response(f"Day {day_number} not found on this plan", 404)

    for field in ["title", "content", "verses", "isCompleted"]:
        if field in data:
            day[field] = data[field]

    plan.set_days(days)
    db.session.commit()
    return success_response(day, "Day updated")


# ======================================================
# ---------------- AI Document Import -------------------
# ======================================================
# Lets an admin/moderator upload a source document (a devotional guide
# they already wrote in Word, exported as PDF, or pasted from WhatsApp
# into a .txt) and have Gemini turn it into a draft multi-day study
# plan. This is deliberately a *draft* endpoint: it does not touch the
# database. It hands back JSON shaped exactly like the payload
# `POST /bible/plans` expects (title/description/level/total_days/
# verses/days), so the admin app can prefill the create-plan screen,
# let the admin review/edit each day, and only then call the normal
# create endpoint. Reuses the same Gemini plumbing as the forum
# assistant (see ai_assistant.py) — just a different system prompt and
# response_mime_type=json instead of free text.
@bible_bp.route("/ai/extract-study-plan", methods=["POST"])
@roles_required("admin", "moderator")
def ai_extract_study_plan():
    if "file" not in request.files:
        return error_response("No file provided. Attach it as multipart form field 'file'.", 400)

    file = request.files["file"]
    if not file or file.filename == "":
        return error_response("No file selected", 400)

    try:
        source_text = extract_text(file)
    except DocumentExtractError as e:
        return error_response(str(e), 400)

    instruction = (request.form.get("instruction") or "").strip()

    try:
        draft = generate_study_plan_draft(source_text=source_text, instruction=instruction)
    except AssistantError as e:
        return error_response(str(e), 502)

    # Light normalization so a slightly-off model response still slots
    # cleanly into the create-plan form instead of erroring the UI.
    days = draft.get("days") if isinstance(draft.get("days"), list) else []
    normalized_days = []
    for i, day in enumerate(days, start=1):
        if not isinstance(day, dict):
            continue
        normalized_days.append({
            "dayNumber": day.get("dayNumber", i),
            "title": day.get("title", f"Day {i}"),
            "content": day.get("content", ""),
            "verses": day.get("verses") if isinstance(day.get("verses"), list) else [],
        })

    level = str(draft.get("level", "BEGINNER")).upper()
    if level not in ("BEGINNER", "INTERMEDIATE", "ADVANCED", "ALL_LEVELS"):
        level = "BEGINNER"

    result = {
        "title": draft.get("title", "").strip() or "Untitled Study Plan",
        "description": draft.get("description", "").strip(),
        "level": level,
        "total_days": draft.get("total_days") or len(normalized_days) or 1,
        "verses": draft.get("verses") if isinstance(draft.get("verses"), list) else [],
        "days": normalized_days,
    }

    return success_response(result, "Draft generated — review before saving")


@bible_bp.route("/plans/<int:plan_id>", methods=["DELETE"])
@jwt_required()
def delete_plan(plan_id):
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    plan = StudyPlan.query.get_or_404(plan_id)

    # FIX: Check admin using roles
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    
    if not is_admin and plan.author_id != user.id:
        return error_response("Not authorized to delete this plan", 403)

    db.session.delete(plan)
    db.session.commit()
    return success_response({}, "Study plan deleted")


# ======================================================
# ---------------- Progress Endpoints ------------------
# ======================================================

# ======================================================
# ---------------- Devotion Progress -------------------
# ======================================================
@bible_bp.route("/progress/devotion/<int:devotion_id>", methods=["GET"])
@jwt_required()
def get_devotion_progress(devotion_id):
    """Get user's progress for a specific devotion"""
    user_id = get_jwt_identity()
    
    # Check if devotion exists
    devotion = Devotion.query.get(devotion_id)
    if not devotion:
        return error_response("Devotion not found", 404)
    
    # In a real implementation, you might have a DevotionProgress model
    # For now, return a default structure
    return success_response({
        "devotion_id": devotion_id,
        "user_id": user_id,
        "completed": False,
        "last_read": None,
        "notes": "",
        "progress": 0
    })


@bible_bp.route("/progress/devotion/<int:devotion_id>", methods=["POST"])
@jwt_required()
def update_devotion_progress(devotion_id):
    """Update user's progress for a devotion"""
    user_id = get_jwt_identity()
    data = request.get_json()
    
    # Check if devotion exists
    devotion = Devotion.query.get(devotion_id)
    if not devotion:
        return error_response("Devotion not found", 404)
    
    # In a real implementation, you'd save this to a DevotionProgress model
    response_data = {
        "devotion_id": devotion_id,
        "user_id": user_id,
        "completed": data.get("completed", False),
        "last_read": datetime.utcnow().isoformat(),
        "notes": data.get("notes", ""),
        "progress": data.get("progress", 100 if data.get("completed") else 50)
    }
    
    return success_response(response_data, "Devotion progress updated")


# ======================================================
# ---------------- Study Plan Progress -----------------
# ======================================================
@bible_bp.route("/progress/study_plan/<int:plan_id>", methods=["GET"])
@jwt_required()
def get_study_plan_progress(plan_id):
    """Get user's progress for a specific study plan"""
    user_id = get_jwt_identity()
    
    # Check if plan exists
    plan = StudyPlan.query.get(plan_id)
    if not plan:
        return error_response("Study plan not found", 404)
    
    progress = StudyPlanProgress.query.filter_by(
        user_id=user_id, plan_id=plan_id
    ).first()
    
    if progress:
        return success_response(progress.to_dict(include_user=True))
    else:
        # Return default progress if none exists
        return success_response({
            "plan_id": plan_id,
            "user_id": user_id,
            "current_day": 1,
            "completed": False,
            "started_at": None,
            "last_updated": None,
            "progress_percentage": 0
        })


@bible_bp.route("/progress/study_plan/<int:plan_id>", methods=["POST"])
@jwt_required()
def update_study_plan_progress(plan_id):
    """Update user's progress for a study plan"""
    user_id = get_jwt_identity()
    data = request.get_json()
    
    if not data or "current_day" not in data:
        return error_response("Missing required field: current_day", 400)

    # Check if plan exists
    plan = StudyPlan.query.get(plan_id)
    if not plan:
        return error_response("Study plan not found", 404)

    progress = StudyPlanProgress.query.filter_by(
        user_id=user_id, plan_id=plan_id
    ).first()

    if progress:
        progress.current_day = data["current_day"]
        progress.completed = data.get("completed", progress.completed)
        progress.last_updated = datetime.utcnow()
    else:
        progress = StudyPlanProgress(
            user_id=user_id,
            plan_id=plan_id,
            current_day=data["current_day"],
            completed=data.get("completed", False),
            started_at=datetime.utcnow(),
            last_updated=datetime.utcnow()
        )
        db.session.add(progress)

    db.session.commit()
    return success_response(progress.to_dict(include_user=True), "Progress updated")


# ======================================================
# ---------------- Legacy Progress Routes (for compatibility) --
# ======================================================
@bible_bp.route("/plans/<int:plan_id>/progress", methods=["GET"])
@jwt_required()
def get_plan_progress_legacy(plan_id):
    """Legacy endpoint for study plan progress"""
    return get_study_plan_progress(plan_id)


@bible_bp.route("/plans/<int:plan_id>/progress", methods=["POST"])
@jwt_required()
def update_plan_progress_legacy(plan_id):
    """Legacy endpoint for updating study plan progress"""
    return update_study_plan_progress(plan_id)


# ======================================================
# ---------------- Archives ----------------------------
# ======================================================
@bible_bp.route("/plans/<int:plan_id>/archive", methods=["POST"])
@jwt_required()
def archive_study_plan(plan_id):
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    plan = StudyPlan.query.get_or_404(plan_id)

    # Check if user is admin or plan author
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    if not is_admin and plan.author_id != user.id:
        return error_response("Not authorized to archive this plan", 403)

    # Create archive entry
    archive = Archive(
        title=f"Study Plan: {plan.title}",
        notes=plan.description,
        category="study_plan",
        author_id=user.id,
    )
    
    # Mark the plan as inactive
    plan.is_active = False
    
    db.session.add(archive)
    db.session.commit()
    
    return success_response(archive.to_dict(include_author=True), "Study plan archived", 201)


@bible_bp.route("/devotions/<int:devotion_id>/archive", methods=["POST"])
@jwt_required()
def archive_devotion(devotion_id):
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    devotion = Devotion.query.get_or_404(devotion_id)

    # Check if user is admin or devotion author
    is_admin = any(role.name == 'admin' for role in user.roles) if user.roles else False
    if not is_admin and devotion.author_id != user.id:
        return error_response("Not authorized to archive this devotion", 403)

    # Create archive entry
    archive = Archive(
        title=f"Devotion: {devotion.verse}",
        notes=devotion.content,
        category="devotion",
        author_id=user.id,
    )
    
    # Mark the devotion as inactive
    devotion.is_active = False
    
    db.session.add(archive)
    db.session.commit()
    
    return success_response(archive.to_dict(include_author=True), "Devotion archived", 201)


@bible_bp.route("/archives", methods=["GET"])
def list_archives():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    category = request.args.get("category")

    # ✅ joinedload(author): to_dict(include_author=True) reads
    # archive.author.*, so without this every archive on the page did
    # its own lazy SELECT on users.
    query = Archive.query.options(db.joinedload(Archive.author)).filter_by(is_active=True)
    if category:
        query = query.filter(Archive.category == category)

    pagination = query.order_by(Archive.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    return success_response(
        {
            "items": [a.to_dict(include_author=True) for a in pagination.items],
            "total": pagination.total,
            "page": pagination.page,
            "pages": pagination.pages,
        }
    )


@bible_bp.route("/archives/<int:archive_id>", methods=["GET"])
def get_archive(archive_id):
    archive = Archive.query.get_or_404(archive_id)
    return success_response(archive.to_dict(include_author=True))


@bible_bp.route("/archives", methods=["POST"])
@jwt_required()
def create_archive():
    user, error = require_admin()
    if error:
        return error

    data = request.get_json()
    if not data or "title" not in data:
        return error_response("Missing required field: title", 400)

    archive = Archive(
        title=data["title"],
        notes=data.get("notes"),
        category=data.get("category", "general"),
        author_id=user.id,
    )
    db.session.add(archive)
    db.session.commit()
    return success_response(archive.to_dict(include_author=True), "Archive created", 201)


@bible_bp.route("/archives/<int:archive_id>", methods=["PATCH"])
@jwt_required()
def update_archive(archive_id):
    user, error = require_admin()
    if error:
        return error

    archive = Archive.query.get_or_404(archive_id)
    data = request.get_json()

    for field in ["title", "notes", "category"]:
        if field in data:
            setattr(archive, field, data[field])

    db.session.commit()
    return success_response(archive.to_dict(include_author=True), "Archive updated")


@bible_bp.route("/archives/<int:archive_id>", methods=["DELETE"])
@jwt_required()
def delete_archive(archive_id):
    user, error = require_admin()
    if error:
        return error

    archive = Archive.query.get_or_404(archive_id)
    db.session.delete(archive)
    db.session.commit()
    return success_response({}, "Archive deleted")
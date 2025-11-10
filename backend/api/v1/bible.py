import json
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy import or_
from datetime import datetime

from backend.models import db, User, Devotion, StudyPlan, StudyPlanProgress, Archive
from .utils import success_response, error_response, require_admin

bible_bp = Blueprint("bible", __name__, url_prefix="/bible")

# ======================================================
# ---------------- Devotions ---------------------------
# ======================================================
@bible_bp.route("/devotions", methods=["GET"])
def list_devotions():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    date = request.args.get("date")

    query = Devotion.query.filter_by(is_active=True)

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

    query = StudyPlan.query.filter_by(is_active=True)

    if user_id:
        # Authenticated: show all public plans + user’s own private plans
        query = query.filter(
            or_(StudyPlan.is_public == True, StudyPlan.author_id == user_id)
        )
    else:
        # Guests: only public plans
        query = query.filter(StudyPlan.is_public == True)

    plans = query.order_by(StudyPlan.created_at.desc()).all()
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

    db.session.commit()
    return success_response(plan.to_dict(include_author=True), "Study plan updated")


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
# ---------------- Study Plan Progress -----------------
# ======================================================
@bible_bp.route("/plans/<int:plan_id>/progress", methods=["GET"])
@jwt_required()
def get_progress(plan_id):
    user_id = get_jwt_identity()
    progress = StudyPlanProgress.query.filter_by(
        user_id=user_id, plan_id=plan_id
    ).first()
    return success_response(progress.to_dict(include_user=True) if progress else {})


@bible_bp.route("/plans/<int:plan_id>/progress", methods=["POST"])
@jwt_required()
def update_progress(plan_id):
    user_id = get_jwt_identity()
    data = request.get_json()
    if not data or "current_day" not in data:
        return error_response("Missing required field: current_day", 400)

    progress = StudyPlanProgress.query.filter_by(
        user_id=user_id, plan_id=plan_id
    ).first()

    if progress:
        progress.current_day = data["current_day"]
        progress.completed = data.get("completed", progress.completed)
    else:
        progress = StudyPlanProgress(
            user_id=user_id,
            plan_id=plan_id,
            current_day=data["current_day"],
            completed=data.get("completed", False),
        )
        db.session.add(progress)

    db.session.commit()
    return success_response(progress.to_dict(include_user=True), "Progress updated")


# ======================================================
# ---------------- Archives ----------------------------
# ======================================================
# ======================================================
# ---------------- Study Plan Archive ------------------
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

    query = Archive.query.filter_by(is_active=True)
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
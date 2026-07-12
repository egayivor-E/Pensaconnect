from flask import Blueprint
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Activity, Prayer, TestimonyLike, ForumLike
from backend.extensions import db
from .utils import success_response

activities_bp = Blueprint("activities", __name__, url_prefix="/activities")


def _build_liked_target_keys(activities, current_user_id):
    # ✅ Batched replacement for querying "did the user like this?" once
    # per activity (an N+1 query pattern). Instead: group the feed's
    # target ids by type, run at most one `IN (...)` query per type
    # (prayer_request / testimony / forum_thread), and hand back a set
    # of (target_type, target_id) tuples for O(1) lookup in
    # Activity.to_dict(). Regardless of how many activities are in the
    # feed, this is always exactly 3 queries or fewer — not one per row.
    prayer_ids = set()
    testimony_ids = set()
    thread_ids = set()

    for a in activities:
        if a.target_id is None:
            continue
        if a.target_type == "prayer_request":
            prayer_ids.add(a.target_id)
        elif a.target_type == "testimony":
            testimony_ids.add(a.target_id)
        elif a.target_type == "forum_thread":
            thread_ids.add(a.target_id)

    liked_target_keys = set()

    if prayer_ids:
        rows = Prayer.query.filter(
            Prayer.user_id == current_user_id,
            Prayer.prayer_request_id.in_(prayer_ids),
        ).all()
        liked_target_keys.update(
            ("prayer_request", r.prayer_request_id) for r in rows
        )

    if testimony_ids:
        rows = TestimonyLike.query.filter(
            TestimonyLike.user_id == current_user_id,
            TestimonyLike.testimony_id.in_(testimony_ids),
        ).all()
        liked_target_keys.update(
            ("testimony", r.testimony_id) for r in rows
        )

    if thread_ids:
        rows = ForumLike.query.filter(
            ForumLike.user_id == current_user_id,
            ForumLike.thread_id.in_(thread_ids),
            ForumLike.reaction_type == "like",
        ).all()
        liked_target_keys.update(
            ("forum_thread", r.thread_id) for r in rows
        )

    return liked_target_keys


@activities_bp.route("/recent", methods=["GET"])
@jwt_required()
def get_recent_activities():
    # ✅ Global community feed: recent activity from ALL users, not just
    # the logged-in one, so "Recent Activity" actually reads as a living
    # feed of what's happening in the community rather than a personal
    # log. Still requires a valid JWT to view (route stays @jwt_required),
    # it's just no longer filtered down to the caller's own rows.
    activities = (
        Activity.query.filter_by(is_active=True)
        .order_by(Activity.created_at.desc())
        .limit(20)
        .all()
    )

    # ✅ Precompute which of this page's targets the requesting user has
    # already liked/prayed for, in a handful of batched queries (see
    # _build_liked_target_keys), instead of Activity.to_dict() querying
    # the DB itself once per row.
    current_user_id = get_jwt_identity()
    liked_target_keys = _build_liked_target_keys(activities, current_user_id)

    # ✅ include_user=True so each activity carries the acting user's
    # id/username/fullName/profilePicture for the feed avatar.
    # ✅ liked_target_keys so each activity also carries whether *this*
    # user already liked/prayed for its target, letting the frontend
    # hydrate like state on load instead of assuming everything is
    # unliked until interacted with this session.
    return success_response(
        [
            a.to_dict(include_user=True, liked_target_keys=liked_target_keys)
            for a in activities
        ]
    )

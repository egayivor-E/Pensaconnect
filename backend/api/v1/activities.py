from flask import Blueprint, request
from sqlalchemy import func
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import (
    Activity,
    Prayer,
    TestimonyLike,
    ForumLike,
    ForumComment,
    TimelinePostLike,
    TimelinePostComment,
)
from backend.extensions import db
from .utils import success_response

# Hard ceiling on page size regardless of what a client asks for — a
# `?limit=5000` from a misbehaving/compromised client shouldn't be able
# to force one query to pull the whole activity table.
_MAX_PAGE_SIZE = 50
_DEFAULT_PAGE_SIZE = 20

activities_bp = Blueprint("activities", __name__, url_prefix="/activities")


def _build_liked_target_keys(activities, current_user_id):
    # ✅ Batched replacement for querying "did the user like this?" once
    # per activity (an N+1 query pattern). Instead: group the feed's
    # target ids by type, run at most one `IN (...)` query per type
    # (prayer_request / testimony / forum_thread / timeline_post), and
    # hand back a set of (target_type, target_id) tuples for O(1) lookup
    # in Activity.to_dict(). Regardless of how many activities are in
    # the feed, this is always exactly 4 queries or fewer — not one per
    # row.
    prayer_ids = set()
    testimony_ids = set()
    thread_ids = set()
    timeline_post_ids = set()

    for a in activities:
        if a.target_id is None:
            continue
        if a.target_type == "prayer_request":
            prayer_ids.add(a.target_id)
        elif a.target_type == "testimony":
            testimony_ids.add(a.target_id)
        elif a.target_type == "forum_thread":
            thread_ids.add(a.target_id)
        elif a.target_type == "timeline_post":
            timeline_post_ids.add(a.target_id)

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

    if timeline_post_ids:
        rows = TimelinePostLike.query.filter(
            TimelinePostLike.user_id == current_user_id,
            TimelinePostLike.timeline_post_id.in_(timeline_post_ids),
        ).all()
        liked_target_keys.update(
            ("timeline_post", r.timeline_post_id) for r in rows
        )

    return liked_target_keys


def _build_target_counts(activities):
    # ✅ Batched like/comment counts for post and timeline_post
    # activities, same shape and reasoning as _build_liked_target_keys
    # above: group target ids by type, run one grouped-count query per
    # type, and hand back a dict keyed by (target_type, target_id) for
    # O(1) lookup in Activity.to_dict().
    post_ids = set()
    timeline_post_ids = set()
    for a in activities:
        if a.target_id is None:
            continue
        if a.target_type == "post":
            post_ids.add(a.target_id)
        elif a.target_type == "timeline_post":
            timeline_post_ids.add(a.target_id)

    target_counts = {}

    if post_ids:
        like_rows = (
            db.session.query(ForumLike.post_id, func.count(ForumLike.id))
            .filter(ForumLike.post_id.in_(post_ids))
            .group_by(ForumLike.post_id)
            .all()
        )
        like_counts = {post_id: count for post_id, count in like_rows}

        comment_rows = (
            db.session.query(ForumComment.post_id, func.count(ForumComment.id))
            .filter(ForumComment.post_id.in_(post_ids))
            .group_by(ForumComment.post_id)
            .all()
        )
        comment_counts = {post_id: count for post_id, count in comment_rows}

        for post_id in post_ids:
            target_counts[("post", post_id)] = (
                like_counts.get(post_id, 0),
                comment_counts.get(post_id, 0),
            )

    if timeline_post_ids:
        like_rows = (
            db.session.query(
                TimelinePostLike.timeline_post_id, func.count(TimelinePostLike.id)
            )
            .filter(TimelinePostLike.timeline_post_id.in_(timeline_post_ids))
            .group_by(TimelinePostLike.timeline_post_id)
            .all()
        )
        like_counts = {tp_id: count for tp_id, count in like_rows}

        comment_rows = (
            db.session.query(
                TimelinePostComment.timeline_post_id,
                func.count(TimelinePostComment.id),
            )
            .filter(TimelinePostComment.timeline_post_id.in_(timeline_post_ids))
            .group_by(TimelinePostComment.timeline_post_id)
            .all()
        )
        comment_counts = {tp_id: count for tp_id, count in comment_rows}

        for tp_id in timeline_post_ids:
            target_counts[("timeline_post", tp_id)] = (
                like_counts.get(tp_id, 0),
                comment_counts.get(tp_id, 0),
            )

    return target_counts


@activities_bp.route("/recent", methods=["GET"])
@jwt_required()
def get_recent_activities():
    # ✅ Real pagination. This used to be a flat `.limit(20)` — the
    # frontend already sent a `limit` query param, but it was silently
    # ignored, and there was no way to ask for anything *older* than the
    # newest 20 rows at all, so scrolling to the bottom of the home feed
    # could never load more.
    #
    # Cursor-based (before_id) rather than offset-based on purpose: this
    # feed gets new rows pushed into it live (see the socket broadcast in
    # utils.py), and offset pagination silently skips/duplicates rows
    # once the underlying set has shifted under it mid-scroll. A cursor
    # keyed off the last row's own id doesn't have that problem — it
    # just asks for "everything older than this specific row".
    try:
        limit = int(request.args.get("limit", _DEFAULT_PAGE_SIZE))
    except (TypeError, ValueError):
        limit = _DEFAULT_PAGE_SIZE
    limit = max(1, min(limit, _MAX_PAGE_SIZE))

    before_id = request.args.get("before_id", type=int)

    query = Activity.query.options(db.joinedload(Activity.user)).filter_by(
        is_active=True
    )
    if before_id is not None:
        query = query.filter(Activity.id < before_id)

    # Tie-broken by id (not just created_at) so rows sharing a timestamp
    # — bulk-seeded data, or several activities in the same second —
    # still come back in a single, stable order across pages instead of
    # being able to land on either side of a page boundary differently
    # each request.
    activities = (
        query.order_by(Activity.created_at.desc(), Activity.id.desc())
        # Fetch one extra row purely to answer "is there more after
        # this page?" without a second COUNT query — sliced back off
        # before returning.
        .limit(limit + 1)
        .all()
    )

    has_more = len(activities) > limit
    activities = activities[:limit]

    current_user_id = get_jwt_identity()
    liked_target_keys = _build_liked_target_keys(activities, current_user_id)
    target_counts = _build_target_counts(activities)

    return success_response(
        [
            a.to_dict(
                include_user=True,
                liked_target_keys=liked_target_keys,
                target_counts=target_counts,
            )
            for a in activities
        ],
        meta={
            "has_more": has_more,
            "next_cursor": activities[-1].id if activities else None,
        },
    )
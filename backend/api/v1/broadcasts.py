# backend/api/v1/broadcasts.py
"""Multi-user, multi-platform "go live" feature.

Replaces the old single hardcoded Config.YOUTUBE_VIDEO_ID model with a
per-user LiveBroadcast row. Any number of granted users (plus admins) can
be live at the same time, each on their own platform:

  - youtube:  admin/user pastes a YouTube video ID; playback via the
              existing YouTube iframe player.
  - facebook: admin/user pastes a public Facebook video URL; playback via
              Facebook's public embed in a WebView (no Graph API/app-review
              needed just to *play* it — only true automatic "is it live"
              detection would need that, which Facebook doesn't otherwise
              expose).
  - native:   in-app streaming via Mux (mux.com). We create a Mux live
              stream, hand the RTMP ingest URL + stream key to the
              broadcaster's own device, and take the playback ID for
              viewers. Mux's webhook (see /mux/webhook below) is the only
              thing allowed to flip a native broadcast's is_live to True —
              a user requesting to "go live" doesn't mean their camera is
              actually sending video yet.

Permissions: a user can start a broadcast if they're an admin OR they've
been explicitly granted `can_go_live` by an admin (see the
PATCH /users/<id>/broadcast-permission endpoint in users.py).
"""
from datetime import datetime, timezone
import hmac
import hashlib
import logging

import requests
from flask import Blueprint, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from backend.extensions import db
from backend.models import LiveBroadcast, User
from backend.config import Config
from .utils import success_response, error_response

logger = logging.getLogger(__name__)

broadcasts_bp = Blueprint("broadcasts", __name__, url_prefix="/live/broadcasts")

MUX_API_BASE = "https://api.mux.com"


def _get_current_user():
    user_id = get_jwt_identity()
    return User.query.get(user_id) if user_id else None


def _can_start_broadcast(user: User) -> bool:
    return bool(user) and (user.has_role("admin") or bool(getattr(user, "can_go_live", False)))


# --------------------------------------------------------------------------
# Public / any authenticated user
# --------------------------------------------------------------------------

@broadcasts_bp.route("", methods=["GET"])
@jwt_required()
def list_broadcasts():
    """Everyone logged in can see who is currently live, on any platform."""
    try:
        broadcasts = (
            LiveBroadcast.query.filter_by(is_live=True, is_active=True)
            .order_by(LiveBroadcast.started_at.desc())
            .all()
        )
        return success_response([b.to_dict() for b in broadcasts], "Live broadcasts retrieved")
    except Exception as e:
        logger.error(f"Error listing live broadcasts: {e}")
        return error_response("Failed to load live broadcasts", 500)


@broadcasts_bp.route("/mine", methods=["GET"])
@jwt_required()
def my_broadcasts():
    """The requesting user's own recent broadcasts, including RTMP stream
    key details for native ones — never exposed via the public list."""
    try:
        user = _get_current_user()
        if not user:
            return error_response("Authentication required", 401)

        broadcasts = (
            LiveBroadcast.query.filter_by(user_id=user.id)
            .order_by(LiveBroadcast.created_at.desc())
            .limit(20)
            .all()
        )
        return success_response([b.to_broadcaster_dict() for b in broadcasts])
    except Exception as e:
        logger.error(f"Error loading own broadcasts: {e}")
        return error_response("Failed to load your broadcasts", 500)


@broadcasts_bp.route("/permission", methods=["GET"])
@jwt_required()
def my_permission():
    """Lets the Flutter app decide whether to show the 'Go Live' button
    without needing to guess from role data alone."""
    user = _get_current_user()
    if not user:
        return error_response("Authentication required", 401)
    return success_response({"can_go_live": _can_start_broadcast(user)})


# --------------------------------------------------------------------------
# Starting / managing a broadcast
# --------------------------------------------------------------------------

@broadcasts_bp.route("", methods=["POST"])
@jwt_required()
def start_broadcast():
    """Start a broadcast. Requires admin, or a user explicitly granted
    can_go_live permission by an admin."""
    user = _get_current_user()
    if not user:
        return error_response("Authentication required", 401)

    if not _can_start_broadcast(user):
        return error_response("You don't have permission to go live", 403)

    data = request.get_json(silent=True) or {}
    platform = (data.get("platform") or "").strip().lower()

    if platform not in LiveBroadcast.PLATFORMS:
        return error_response(f"platform must be one of {list(LiveBroadcast.PLATFORMS)}", 422)

    title = (data.get("title") or "").strip() or f"{user.get_full_name()}'s Live Stream"

    try:
        broadcast = LiveBroadcast(
            user_id=user.id,
            platform=platform,
            title=title,
            started_at=datetime.now(timezone.utc),
        )

        if platform == LiveBroadcast.PLATFORM_NATIVE:
            try:
                mux_data = _create_mux_live_stream()
            except MuxConfigMissing:
                return error_response(
                    "Native streaming isn't configured on this server yet "
                    "(missing MUX_TOKEN_ID/MUX_TOKEN_SECRET)",
                    503,
                )
            except MuxRequestFailed as e:
                return error_response(
                    f"Mux rejected the live stream request: {e}",
                    502,
                )
            broadcast.mux_stream_id = mux_data["stream_id"]
            broadcast.mux_stream_key = mux_data["stream_key"]
            broadcast.mux_playback_id = mux_data["playback_id"]
            # A native broadcast isn't actually live until Mux's webhook
            # confirms real incoming video — see mux_webhook() below, which
            # is the only code path allowed to set is_live=True for these.
            broadcast.is_live = False
        else:
            stream_ref = (data.get("stream_ref") or data.get("stream_url") or "").strip()
            if not stream_ref:
                return error_response("stream_ref is required for youtube/facebook broadcasts", 422)
            broadcast.stream_ref = stream_ref
            broadcast.is_live = True

        db.session.add(broadcast)
        db.session.commit()

        logger.info(f"User {user.id} started a {platform} broadcast (#{broadcast.id})")
        return success_response(broadcast.to_broadcaster_dict(), "Broadcast created", 201)

    except Exception as e:
        db.session.rollback()
        logger.error(f"Error starting broadcast: {e}")
        return error_response("Failed to start broadcast", 500)


@broadcasts_bp.route("/<int:broadcast_id>", methods=["PATCH"])
@jwt_required()
def update_broadcast(broadcast_id):
    """End a broadcast, or edit its title/stream_ref. Owner or admin only."""
    user = _get_current_user()
    if not user:
        return error_response("Authentication required", 401)

    broadcast = LiveBroadcast.query.get_or_404(broadcast_id)

    if broadcast.user_id != user.id and not user.has_role("admin"):
        return error_response("You can only manage your own broadcast", 403)

    data = request.get_json(silent=True) or {}

    try:
        if "title" in data:
            new_title = (data.get("title") or "").strip()
            if new_title:
                broadcast.title = new_title

        if "stream_ref" in data and broadcast.platform != LiveBroadcast.PLATFORM_NATIVE:
            broadcast.stream_ref = (data.get("stream_ref") or "").strip()

        if data.get("is_live") is False and broadcast.is_live:
            broadcast.is_live = False
            broadcast.ended_at = datetime.now(timezone.utc)
            if broadcast.platform == LiveBroadcast.PLATFORM_NATIVE and broadcast.mux_stream_id:
                _disable_mux_live_stream(broadcast.mux_stream_id)

        db.session.commit()
        return success_response(broadcast.to_broadcaster_dict(), "Broadcast updated")

    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating broadcast #{broadcast_id}: {e}")
        return error_response("Failed to update broadcast", 500)


# --------------------------------------------------------------------------
# Mux webhook (server-to-server, not a user-facing route)
# --------------------------------------------------------------------------

@broadcasts_bp.route("/mux/webhook", methods=["POST"])
def mux_webhook():
    """Mux calls this when a native stream's actual ingest state changes.
    Deliberately not @jwt_required() — Mux can't send a user JWT — instead
    verified via the shared webhook signing secret in the Mux-Signature
    header, the same way Stripe/most webhook providers work."""
    if not _verify_mux_signature(request):
        return error_response("Invalid signature", 401)

    payload = request.get_json(silent=True) or {}
    event_type = payload.get("type")
    stream_id = (payload.get("data") or {}).get("id")

    if not stream_id:
        return success_response(None, "Ignored (no stream id)")

    broadcast = LiveBroadcast.query.filter_by(mux_stream_id=stream_id).first()
    if not broadcast:
        return success_response(None, "Ignored (unknown stream)")

    try:
        if event_type == "video.live_stream.active":
            broadcast.is_live = True
            broadcast.started_at = broadcast.started_at or datetime.now(timezone.utc)
        elif event_type in ("video.live_stream.idle", "video.live_stream.disconnected"):
            broadcast.is_live = False
            broadcast.ended_at = datetime.now(timezone.utc)

        db.session.commit()
        return success_response(None, "OK")
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error handling Mux webhook (stream {stream_id}): {e}")
        return error_response("Webhook processing failed", 500)


# --------------------------------------------------------------------------
# Mux helpers
# --------------------------------------------------------------------------

def _mux_auth():
    token_id = Config.MUX_TOKEN_ID
    token_secret = Config.MUX_TOKEN_SECRET
    if not token_id or not token_secret:
        return None
    return (token_id, token_secret)


class MuxConfigMissing(Exception):
    """Raised only when MUX_TOKEN_ID/MUX_TOKEN_SECRET are absent."""
    pass


class MuxRequestFailed(Exception):
    """Raised when credentials were present but Mux rejected the request."""
    pass


def _create_mux_live_stream():
    auth = _mux_auth()
    if not auth:
        # Credentials genuinely missing/empty on this server.
        raise MuxConfigMissing("MUX_TOKEN_ID/MUX_TOKEN_SECRET not set")
    try:
        resp = requests.post(
            f"{MUX_API_BASE}/video/v1/live-streams",
            auth=auth,
            json={
                "playback_policy": ["public"],
                "new_asset_settings": {"playback_policy": ["public"]},
                "latency_mode": "standard",
            },
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()["data"]
        return {
            "stream_id": data["id"],
            "stream_key": data["stream_key"],
            "playback_id": data["playback_ids"][0]["id"],
        }
    except requests.exceptions.HTTPError as e:
        # Credentials WERE present and a request WAS sent to Mux — this is
        # NOT a "missing keys" situation. Log Mux's actual error body so we
        # can see why it was rejected (bad payload, token not scoped for
        # live streams, wrong Mux environment, etc).
        body = e.response.text if e.response is not None else "<no body>"
        logger.error(f"Mux create live stream failed: {e} — response body: {body}")
        raise MuxRequestFailed(body) from e
    except Exception as e:
        logger.error(f"Mux create live stream failed (network/other error): {e}")
        raise MuxRequestFailed(str(e)) from e


def _disable_mux_live_stream(stream_id):
    auth = _mux_auth()
    if not auth:
        return
    try:
        requests.put(
            f"{MUX_API_BASE}/video/v1/live-streams/{stream_id}/disable",
            auth=auth,
            timeout=10,
        )
    except Exception as e:
        logger.error(f"Mux disable live stream failed for {stream_id}: {e}")


def _verify_mux_signature(req) -> bool:
    """Verifies Mux's `Mux-Signature: t=<timestamp>,v1=<hmac>` header against
    the raw request body using MUX_WEBHOOK_SECRET. If no secret is
    configured, requests are rejected in production and allowed through in
    dev/test so the route can still be smoke-tested without a live Mux
    account."""
    secret = Config.MUX_WEBHOOK_SECRET
    if not secret:
        return current_app.config.get("ENV") != "production"

    header = req.headers.get("Mux-Signature", "")
    parts = dict(p.split("=", 1) for p in header.split(",") if "=" in p)
    timestamp, signature = parts.get("t"), parts.get("v1")
    if not timestamp or not signature:
        return False

    signed_payload = f"{timestamp}.{req.get_data(as_text=True)}"
    expected = hmac.new(secret.encode(), signed_payload.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)
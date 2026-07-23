"""
Push notification delivery via Firebase Cloud Messaging (FCM).

This module is intentionally isolated from the rest of the app: every
call here is best-effort and never raises — a push failure (missing
credentials, an expired token, FCM being unreachable) must never break
the request that triggered it, the same way notify_reply() in
api/v1/forums.py already treats in-app notifications as best-effort and
wraps them in their own try/except.

--------------------------------------------------------------------
Setup required (one-time, not done by this file — see
docs/PUSH_NOTIFICATIONS_SETUP.md for the full walkthrough):

  1. Create a Firebase project (console.firebase.google.com) and add an
     Android/iOS/Web app to it.
  2. Generate a service account key: Firebase Console → Project Settings
     → Service Accounts → "Generate new private key". This downloads a
     JSON file.
  3. Make that JSON available to the backend via ONE of:
       - FIREBASE_SERVICE_ACCOUNT_JSON — the entire file's contents,
         as a single-line env var (recommended for most hosts, e.g.
         Render's environment variable UI).
       - FIREBASE_SERVICE_ACCOUNT_PATH — a filesystem path to the .json
         file (useful for local dev / Docker with a mounted secret).
  4. pip install firebase-admin (already added to requirements.txt).

Until one of those env vars is set, every function below logs a single
warning and no-ops — the rest of the app (including in-app
notifications) works exactly as it does today. Nothing here is
required for the app to run; it only *adds* push delivery on top of
what already exists once configured.
--------------------------------------------------------------------
"""
import json
import logging
import os
import threading
from typing import Optional

logger = logging.getLogger(__name__)

_init_lock = threading.Lock()
_firebase_app = None
_init_attempted = False


def _get_firebase_app():
    """Lazily initializes the firebase_admin app exactly once per process.
    Returns None (logging why, only the first time) if it can't be set
    up yet — callers treat that as "push isn't configured", not an
    error to surface anywhere."""
    global _firebase_app, _init_attempted
    if _firebase_app is not None or _init_attempted:
        return _firebase_app

    with _init_lock:
        if _init_attempted:
            return _firebase_app
        _init_attempted = True

        try:
            import firebase_admin
            from firebase_admin import credentials
        except ImportError:
            logger.warning(
                "firebase-admin isn't installed — push notifications are "
                "disabled. Run `pip install firebase-admin` (see "
                "requirements.txt) to enable them."
            )
            return None

        service_account_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        service_account_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH")

        try:
            if service_account_json:
                cred = credentials.Certificate(json.loads(service_account_json))
            elif service_account_path:
                cred = credentials.Certificate(service_account_path)
            else:
                logger.warning(
                    "Neither FIREBASE_SERVICE_ACCOUNT_JSON nor "
                    "FIREBASE_SERVICE_ACCOUNT_PATH is set — push "
                    "notifications are disabled until one is configured. "
                    "See docs/PUSH_NOTIFICATIONS_SETUP.md."
                )
                return None

            _firebase_app = firebase_admin.initialize_app(cred)
            logger.info("✅ Firebase Admin initialized — push notifications enabled.")
        except Exception as e:
            logger.error(f"❌ Failed to initialize Firebase Admin: {e}")
            _firebase_app = None

        return _firebase_app


def send_push_notification(
    push_token: Optional[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Sends a single push notification to one device token.

    Returns True if the send call succeeded, False otherwise (no token,
    Firebase not configured, or the send failed for any reason). Callers
    should treat False as "nothing happened" — never surface it to the
    end user or let it affect the response of whatever action triggered
    the notification (a reply, a new message, etc.).
    """
    if not push_token:
        return False

    app = _get_firebase_app()
    if app is None:
        return False

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            token=push_token,
            notification=messaging.Notification(title=title, body=body),
            # FCM data payloads must be flat string->string maps.
            data={str(k): str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(aps=messaging.Aps(sound="default"))
            ),
        )
        messaging.send(message, app=app)
        return True
    except Exception as e:
        # An expired/unregistered token is routine (uninstalled app,
        # cleared local storage, etc.) — log at debug so it doesn't read
        # like an outage every time someone uninstalls the app.
        logger.debug(f"Push send failed: {e}")
        return False


def send_push_to_user(
    user,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Convenience wrapper — reads the token straight off a User row
    (backend/models.py's User.push_token) so call sites don't need to
    reach into it themselves."""
    if user is None:
        return False
    return send_push_notification(
        getattr(user, "push_token", None), title, body, data=data
    )
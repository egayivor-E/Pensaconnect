"""
backend/supabase_client.py

Singleton Supabase client for server-side file uploads.

Requires these environment variables to be set (e.g. in Render's
Environment tab, or in your local .env):

    SUPABASE_URL              - your Supabase project URL
    SUPABASE_SERVICE_ROLE_KEY - the service_role key (NOT the anon key)

The service_role key bypasses Row Level Security, which is what lets
the backend upload on behalf of users without needing a signed
per-user session. Never expose this key to Flutter/client code -
it is server-only.
"""

import os
import logging

from supabase import create_client, Client

logger = logging.getLogger(__name__)

_supabase_client: Client | None = None

# Name of the public storage bucket created in the Supabase dashboard
WORSHIP_MEDIA_BUCKET = "worship-media"

# Bucket for forum post/comment attachments (images, videos, docs).
# Create this as a public bucket in the Supabase dashboard, same as
# worship-media.
FORUM_MEDIA_BUCKET = "forum-media"

# Bucket for a user's own profile timeline posts (images/videos attached
# via POST /timeline-posts/upload). Create this as a public bucket in
# the Supabase dashboard, same as worship-media and forum-media.
TIMELINE_MEDIA_BUCKET = "timeline-media"


def get_supabase_client() -> Client:
    """
    Returns a cached Supabase client, creating it on first use.
    Raises RuntimeError with a clear message if env vars are missing,
    instead of letting a cryptic KeyError/AttributeError bubble up.
    """
    global _supabase_client

    if _supabase_client is not None:
        return _supabase_client

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

    if not url or not key:
        missing = []
        if not url:
            missing.append("SUPABASE_URL")
        if not key:
            missing.append("SUPABASE_SERVICE_ROLE_KEY")
        raise RuntimeError(
            f"Supabase is not configured. Missing environment variable(s): "
            f"{', '.join(missing)}. Set these in Render's Environment tab "
            f"(or your local .env) before uploading files."
        )

    _supabase_client = create_client(url, key)
    logger.info("Supabase client initialized")
    return _supabase_client


def upload_file_to_supabase(
    file_bytes: bytes,
    destination_path: str,
    content_type: str,
    bucket: str = WORSHIP_MEDIA_BUCKET,
) -> str:
    """
    Uploads raw bytes to the given bucket/path and returns the public URL.

    destination_path example: 'audios/<uuid>_song.mp3'
    """
    client = get_supabase_client()

    try:
        client.storage.from_(bucket).upload(
            path=destination_path,
            file=file_bytes,
            file_options={"content-type": content_type, "upsert": "true"},
        )
    except Exception as e:
        logger.error(f"Supabase upload failed for {destination_path}: {e}")
        raise

    public_url = client.storage.from_(bucket).get_public_url(destination_path)
    return public_url


def delete_file_from_supabase(
    destination_path: str,
    bucket: str = WORSHIP_MEDIA_BUCKET,
) -> None:
    """Deletes a file from the bucket. Used for cleanup on failed uploads."""
    client = get_supabase_client()
    try:
        client.storage.from_(bucket).remove([destination_path])
    except Exception as e:
        # Don't let cleanup failures mask the original error
        logger.warning(f"Failed to clean up {destination_path} from Supabase: {e}")
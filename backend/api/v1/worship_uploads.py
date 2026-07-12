from flask import Blueprint, request, jsonify
import uuid
import logging

from backend.models import db, WorshipSong
from backend.supabase_client import (
    upload_file_to_supabase,
    delete_file_from_supabase,
    WORSHIP_MEDIA_BUCKET,
)

logger = logging.getLogger(__name__)

worship_uploads_bp = Blueprint('worship_uploads', __name__, url_prefix='/worship-uploads')

# Allowed file extensions
ALLOWED_VIDEO_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv'}
ALLOWED_AUDIO_EXTENSIONS = {'mp3', 'wav', 'm4a', 'ogg'}

# Basic content-type map so Supabase serves files with the right headers
CONTENT_TYPES = {
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'm4a': 'audio/mp4', 'ogg': 'audio/ogg',
}


def _get_extension(filename: str) -> str | None:
    if '.' not in filename:
        return None
    return filename.rsplit('.', 1)[1].lower()


def _allowed_file(filename: str, allowed_extensions: set[str]) -> bool:
    ext = _get_extension(filename)
    return ext is not None and ext in allowed_extensions


def _handle_upload(allowed_extensions: set[str], folder: str, media_type: str):
    """
    Shared logic for video/audio upload. Reads the file into memory,
    uploads it to Supabase Storage, and returns the resulting public URL.
    """
    if 'file' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file provided'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'status': 'error', 'message': 'No file selected'}), 400

    if not _allowed_file(file.filename, allowed_extensions):
        allowed_str = ', '.join(sorted(allowed_extensions))
        return jsonify({
            'status': 'error',
            'message': f'Invalid file type. Allowed: {allowed_str}'
        }), 400

    ext = _get_extension(file.filename)
    unique_filename = f"{uuid.uuid4()}.{ext}"
    destination_path = f"{folder}/{unique_filename}"
    content_type = CONTENT_TYPES.get(ext, 'application/octet-stream')

    try:
        file_bytes = file.read()
        file_size = len(file_bytes)

        if file_size == 0:
            return jsonify({'status': 'error', 'message': 'Uploaded file is empty'}), 400

        public_url = upload_file_to_supabase(
            file_bytes=file_bytes,
            destination_path=destination_path,
            content_type=content_type,
        )

        return jsonify({
            'status': 'success',
            'message': f'{media_type.capitalize()} uploaded successfully',
            'data': {
                'fileUrl': public_url,
                'fileName': file.filename,
                'fileSize': file_size,
                'mediaType': media_type,
                'storagePath': destination_path,  # keep this so we can delete later if needed
            }
        })

    except RuntimeError as e:
        # Raised by supabase_client when env vars are missing - config issue, not a client error
        logger.error(f"Supabase config error during {media_type} upload: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

    except Exception as e:
        logger.error(f"{media_type.capitalize()} upload failed: {e}")
        # Best-effort cleanup in case the file partially uploaded before failing
        try:
            delete_file_from_supabase(destination_path)
        except Exception:
            pass
        return jsonify({
            'status': 'error',
            'message': f'Upload failed: {str(e)}'
        }), 500


@worship_uploads_bp.route('/upload-video', methods=['POST'])
def upload_video():
    """Upload video file to Supabase Storage"""
    return _handle_upload(ALLOWED_VIDEO_EXTENSIONS, 'videos', 'video')


@worship_uploads_bp.route('/upload-audio', methods=['POST'])
def upload_audio():
    """Upload audio file to Supabase Storage"""
    return _handle_upload(ALLOWED_AUDIO_EXTENSIONS, 'audios', 'audio')


@worship_uploads_bp.route('/download/<int:song_id>', methods=['POST'])
def increment_download_count(song_id):
    """Increment download count when user downloads a file"""
    try:
        song = WorshipSong.query.get(song_id)
        if not song:
            return jsonify({'status': 'error', 'message': 'Song not found'}), 404

        song.download_count += 1
        db.session.commit()

        return jsonify({
            'status': 'success',
            'downloadCount': song.download_count
        })

    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

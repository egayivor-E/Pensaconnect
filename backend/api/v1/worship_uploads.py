from flask import Blueprint, request, jsonify, current_app
from werkzeug.utils import secure_filename
import os
import uuid
from datetime import datetime
from backend.models import db, WorshipSong

worship_uploads_bp = Blueprint('worship_uploads', __name__, url_prefix='/worship-uploads')

# Allowed file extensions
ALLOWED_VIDEO_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv'}
ALLOWED_AUDIO_EXTENSIONS = {'mp3', 'wav', 'm4a', 'ogg'}

def allowed_file(filename, allowed_extensions):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in allowed_extensions

def get_file_size(file_path):
    return os.path.getsize(file_path)

@worship_uploads_bp.route('/upload-video', methods=['POST'])
def upload_video():
    """Upload video file"""
    try:
        if 'file' not in request.files:
            return jsonify({'status': 'error', 'message': 'No file provided'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'status': 'error', 'message': 'No file selected'}), 400
        
        if file and allowed_file(file.filename, ALLOWED_VIDEO_EXTENSIONS):
            # Generate unique filename
            filename = secure_filename(file.filename)
            unique_filename = f"{uuid.uuid4()}_{filename}"
            
            # Create uploads directory if it doesn't exist
            upload_folder = os.path.join(current_app.config['UPLOAD_FOLDER'], 'videos')
            os.makedirs(upload_folder, exist_ok=True)
            
            file_path = os.path.join(upload_folder, unique_filename)
            file.save(file_path)
            
            # Get file size
            file_size = get_file_size(file_path)
            
            # Return file URL and info
            file_url = f"/uploads/videos/{unique_filename}"
            
            return jsonify({
                'status': 'success',
                'message': 'Video uploaded successfully',
                'data': {
                    'fileUrl': file_url,
                    'fileName': filename,
                    'fileSize': file_size,
                    'mediaType': 'video'
                }
            })
        else:
            return jsonify({
                'status': 'error', 
                'message': 'Invalid file type. Allowed: mp4, mov, avi, mkv'
            }), 400
            
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Upload failed: {str(e)}'
        }), 500

@worship_uploads_bp.route('/upload-audio', methods=['POST'])
def upload_audio():
    """Upload audio file"""
    try:
        if 'file' not in request.files:
            return jsonify({'status': 'error', 'message': 'No file provided'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'status': 'error', 'message': 'No file selected'}), 400
        
        if file and allowed_file(file.filename, ALLOWED_AUDIO_EXTENSIONS):
            # Generate unique filename
            filename = secure_filename(file.filename)
            unique_filename = f"{uuid.uuid4()}_{filename}"
            
            # Create uploads directory if it doesn't exist
            upload_folder = os.path.join(current_app.config['UPLOAD_FOLDER'], 'audios')
            os.makedirs(upload_folder, exist_ok=True)
            
            file_path = os.path.join(upload_folder, unique_filename)
            file.save(file_path)
            
            # Get file size
            file_size = get_file_size(file_path)
            
            # Return file URL and info
            file_url = f"/uploads/audios/{unique_filename}"
            
            return jsonify({
                'status': 'success',
                'message': 'Audio uploaded successfully',
                'data': {
                    'fileUrl': file_url,
                    'fileName': filename,
                    'fileSize': file_size,
                    'mediaType': 'audio'
                }
            })
        else:
            return jsonify({
                'status': 'error', 
                'message': 'Invalid file type. Allowed: mp3, wav, m4a, ogg'
            }), 400
            
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Upload failed: {str(e)}'
        }), 500

@worship_uploads_bp.route('/download/<int:song_id>', methods=['POST'])
def increment_download_count(song_id):
    """Increment download count when user downloads a file"""
    try:
        from backend.models import WorshipSong, db
        
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
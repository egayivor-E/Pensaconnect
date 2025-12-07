# backend/routes/worship_songs.py
from flask import Blueprint, request, jsonify
from backend.models import db, WorshipSong

# Add these imports at the top of worship_songs.py
import os
import tempfile
from flask import send_file, send_from_directory
from werkzeug.utils import safe_join
import yt_dlp  # For YouTube downloads


worship_songs_bp = Blueprint('worship_songs', __name__, url_prefix='/worship-songs')

@worship_songs_bp.route('/', methods=['GET'])
def get_worship_songs():
    """Get all worship songs"""
    try:
        songs = WorshipSong.query.order_by(WorshipSong.created_at.desc()).all()
        return jsonify({
            'status': 'success',
            'data': [song.to_dict() for song in songs],
            'count': len(songs)
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Failed to fetch songs: {str(e)}'
        }), 500

@worship_songs_bp.route('/', methods=['POST'])
def create_worship_song():
    """Create a new worship song (YouTube, video, or audio)"""
    try:
        data = request.get_json()
        
        # Validate required fields
        if not data.get('title') or not data.get('artist'):
            return jsonify({
                'status': 'error',
                'message': 'Title and artist are required'
            }), 400
        
        media_type = data.get('mediaType', 'youtube')
        
        # Validate based on media type
        if media_type == 'youtube' and not data.get('videoId'):
            return jsonify({
                'status': 'error', 
                'message': 'YouTube video ID is required for YouTube songs'
            }), 400
        
        if media_type == 'video' and not data.get('videoUrl'):
            return jsonify({
                'status': 'error',
                'message': 'Video URL is required for video songs'
            }), 400
            
        if media_type == 'audio' and not data.get('audioUrl'):
            return jsonify({
                'status': 'error',
                'message': 'Audio URL is required for audio songs'
            }), 400
        
        new_song = WorshipSong(
            title=data['title'],
            artist=data['artist'],
            video_id=data.get('videoId'),
            video_url=data.get('videoUrl'),
            audio_url=data.get('audioUrl'),
            thumbnail_url=data.get('thumbnailUrl'),
            category=data.get('category', 0),
            media_type=media_type,
            lyrics=data.get('lyrics'),
            duration=data.get('duration', 0),
            file_size=data.get('fileSize', 0),
            allow_download=data.get('allowDownload', True)
        )
        
        db.session.add(new_song)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'Song created successfully',
            'data': new_song.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'status': 'error',
            'message': f'Failed to create song: {str(e)}'
        }), 500

@worship_songs_bp.route('/youtube', methods=['POST'])
def create_youtube_song():
    """Create a YouTube worship song"""
    try:
        data = request.get_json(silent=True) or request.form.to_dict()

        
        if not data.get('title') or not data.get('artist') or not data.get('videoId'):
            return jsonify({
                'status': 'error',
                'message': 'Title, artist, and videoId are required'
            }), 400
        
        new_song = WorshipSong(
            title=data['title'],
            artist=data['artist'],
            video_id=data['videoId'],
            thumbnail_url=data.get('thumbnailUrl', f'https://img.youtube.com/vi/{data["videoId"]}/hqdefault.jpg'),
            category=data.get('category', 0),
            media_type='youtube',
            lyrics=data.get('lyrics'),
            duration=data.get('duration', 0),
            allow_download=data.get('allowDownload', True)
        )
        
        db.session.add(new_song)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'YouTube song added successfully',
            'data': new_song.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'status': 'error',
            'message': f'Failed to add YouTube song: {str(e)}'
        }), 500

@worship_songs_bp.route('/audio', methods=['POST'])
def create_audio_song():
    """Create an audio worship song"""
    try:
        data = request.get_json()
        
        if not data.get('title') or not data.get('artist') or not data.get('audioUrl'):
            return jsonify({
                'status': 'error',
                'message': 'Title, artist, and audioUrl are required'
            }), 400
        
        new_song = WorshipSong(
            title=data['title'],
            artist=data['artist'],
            audio_url=data['audioUrl'],
            thumbnail_url=data.get('thumbnailUrl', 'assets/images/worship_icon.jpeg'),
            category=data.get('category', 0),
            media_type='audio',
            lyrics=data.get('lyrics'),
            duration=data.get('duration', 0),
            file_size=data.get('fileSize', 0),
            allow_download=data.get('allowDownload', True)
        )
        
        db.session.add(new_song)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'Audio song added successfully',
            'data': new_song.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'status': 'error',
            'message': f'Failed to add audio song: {str(e)}'
        }), 500

@worship_songs_bp.route('/video', methods=['POST'])
def create_video_song():
    """Create a video worship song"""
    try:
        data = request.get_json()
        
        if not data.get('title') or not data.get('artist') or not data.get('videoUrl'):
            return jsonify({
                'status': 'error',
                'message': 'Title, artist, and videoUrl are required'
            }), 400
        
        new_song = WorshipSong(
            title=data['title'],
            artist=data['artist'],
            video_url=data['videoUrl'],
            thumbnail_url=data.get('thumbnailUrl', 'assets/images/worship_icon.jpeg'),
            category=data.get('category', 0),
            media_type='video',
            lyrics=data.get('lyrics'),
            duration=data.get('duration', 0),
            file_size=data.get('fileSize', 0),
            allow_download=data.get('allowDownload', True)
        )
        
        db.session.add(new_song)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'Video song added successfully',
            'data': new_song.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'status': 'error',
            'message': f'Failed to add video song: {str(e)}'
        }), 500

@worship_songs_bp.route('/<int:song_id>', methods=['GET'])
def get_song(song_id):
    """Get a specific worship song"""
    try:
        song = WorshipSong.query.get(song_id)
        if not song:
            return jsonify({
                'status': 'error',
                'message': 'Song not found'
            }), 404
        
        return jsonify({
            'status': 'success',
            'data': song.to_dict()
        })
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Failed to fetch song: {str(e)}'
        }), 500

@worship_songs_bp.route('/<int:song_id>', methods=['DELETE'])
def delete_song(song_id):
    """Delete a worship song"""
    try:
        song = WorshipSong.query.get(song_id)
        if not song:
            return jsonify({
                'status': 'error',
                'message': 'Song not found'
            }), 404
        
        db.session.delete(song)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'Song deleted successfully'
        })
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'status': 'error',
            'message': f'Failed to delete song: {str(e)}'
        }), 500
        
        


# Add this route to your existing worship_songs_bp blueprint
@worship_songs_bp.route('/<int:song_id>/download', methods=['GET'])
def download_song(song_id):
    """Download a song for offline playback"""
    try:
        song = WorshipSong.query.get(song_id)
        if not song:
            return jsonify({
                'status': 'error',
                'message': 'Song not found'
            }), 404
        
        # Check if downloads are allowed for this song
        if not song.allow_download:
            return jsonify({
                'status': 'error',
                'message': 'Downloads are not allowed for this song'
            }), 403
        
        # Different download logic based on media type
        if song.media_type == 'youtube':
            return _download_youtube_song(song)
        elif song.media_type == 'audio' and song.audio_url:
            return _download_audio_song(song)
        elif song.media_type == 'video' and song.video_url:
            return _download_video_song(song)
        else:
            return jsonify({
                'status': 'error',
                'message': 'No downloadable content available'
            }), 400
            
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Download failed: {str(e)}'
        }), 500


def _download_youtube_song(song):
    """Download YouTube video as audio"""
    try:
        # Create temp directory for downloads
        temp_dir = tempfile.gettempdir()
        download_dir = safe_join(temp_dir, 'pensa_downloads')
        
        if not os.path.exists(download_dir):
            os.makedirs(download_dir)
        
        # YouTube download options
        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': safe_join(download_dir, f'{song.id}_{song.title}.%(ext)s'),
            'quiet': True,
            'no_warnings': True,
            'extract_audio': True,
            'audio_format': 'mp3',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '192',
            }],
        }
        
        # Download from YouTube
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f'https://youtu.be/{song.video_id}', download=True)
            
            # Find the downloaded file
            downloaded_file = ydl.prepare_filename(info)
            if downloaded_file.endswith('.webm'):
                downloaded_file = downloaded_file[:-5] + '.mp3'
            elif downloaded_file.endswith('.m4a'):
                downloaded_file = downloaded_file[:-4] + '.mp3'
            
            # Sanitize filename for download
            safe_filename = f"{song.title.replace(' ', '_')}_{song.id}.mp3"
            safe_filename = "".join(c for c in safe_filename if c.isalnum() or c in "._- ")
            
            # Send file to client
            return send_file(
                downloaded_file,
                as_attachment=True,
                download_name=safe_filename,
                mimetype='audio/mpeg'
            )
            
    except Exception as e:
        raise Exception(f"YouTube download failed: {str(e)}")


def _download_audio_song(song):
    """Serve already uploaded audio file"""
    if not song.audio_url:
        raise Exception("No audio URL available")
    
    # Extract filename from URL
    filename = song.audio_url.split('/')[-1]
    
    # If it's a local file
    if song.audio_url.startswith('/'):
        return send_file(
            song.audio_url,
            as_attachment=True,
            download_name=filename or f"{song.title}.mp3"
        )
    
    # For external URLs, we'd need to download first
    # For now, redirect to the URL (client handles download)
    return jsonify({
        'status': 'success',
        'message': 'Use direct URL for download',
        'download_url': song.audio_url
    })


def _download_video_song(song):
    """Serve already uploaded video file"""
    if not song.video_url:
        raise Exception("No video URL available")
    
    # Extract filename from URL
    filename = song.video_url.split('/')[-1]
    
    # If it's a local file
    if song.video_url.startswith('/'):
        return send_file(
            song.video_url,
            as_attachment=True,
            download_name=filename or f"{song.title}.mp4"
        )
    
    # For external URLs
    return jsonify({
        'status': 'success',
        'message': 'Use direct URL for download',
        'download_url': song.video_url
    })


# Also add this endpoint to check download availability
@worship_songs_bp.route('/<int:song_id>/download-info', methods=['GET'])
def get_download_info(song_id):
    """Get information about song download availability"""
    try:
        song = WorshipSong.query.get(song_id)
        if not song:
            return jsonify({
                'status': 'error',
                'message': 'Song not found'
            }), 404
        
        return jsonify({
            'status': 'success',
            'data': {
                'id': song.id,
                'title': song.title,
                'artist': song.artist,
                'can_download': song.allow_download,
                'media_type': song.media_type,
                'file_size': song.file_size,
                'estimated_download_size': _get_estimated_size(song),
                'is_youtube': song.media_type == 'youtube',
                'has_audio': bool(song.audio_url),
                'has_video': bool(song.video_url),
            }
        })
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Failed to get download info: {str(e)}'
        }), 500


def _get_estimated_size(song):
    """Get estimated file size for download"""
    if song.file_size and song.file_size > 0:
        return song.file_size
    
    # Estimate based on media type
    if song.media_type == 'youtube':
        return 5000000  # ~5MB for audio
    elif song.media_type == 'audio':
        return 8000000  # ~8MB for audio
    elif song.media_type == 'video':
        return 30000000  # ~30MB for video
    
    return 0
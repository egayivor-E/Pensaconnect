import os
import uuid
from datetime import datetime
from flask import Blueprint, request, current_app, send_from_directory, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from backend.models import User
from backend.extensions import db
from .utils import success_response, error_response
from backend.config import Config

users_bp = Blueprint("users", __name__, url_prefix="/users")

# ======== CONFIG ========
# Use config-based settings instead of hardcoded values
def allowed_file(filename):
    return Config.is_allowed_file(filename)


# ======== ROUTES ========

# ✅ List all users
@users_bp.route("/", methods=["GET"])
@jwt_required()
def list_users():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    users = User.query.paginate(page=page, per_page=per_page, error_out=False)
    return success_response(
        [u.to_dict(exclude=["password_hash"]) for u in users.items]
    )


# ✅ Get specific user by ID
@users_bp.route("/<int:user_id>", methods=["GET"])
@jwt_required()
def get_user(user_id: int):
    user = User.query.get_or_404(user_id)
    return success_response(user.to_dict(exclude=["password_hash"]))


# ✅ Update user (Self only)
@users_bp.route("/<int:user_id>", methods=["PATCH"])
@jwt_required()
def update_user(user_id: int):
    current_user_id = get_jwt_identity()
    if user_id != current_user_id:
        return error_response("Unauthorized: You can only update your own profile.", 403)

    user = User.query.get_or_404(user_id)
    data = request.get_json() or {}

    allowed_fields = ["username", "email", "profile_picture"]
    for key in allowed_fields:
        if key in data and data[key] is not None:
            setattr(user, key, data[key])

    db.session.commit()
    return success_response(
        user.to_dict(exclude=["password_hash"]),
        "Profile updated successfully"
    )


# ✅ Delete user (Self only)
@users_bp.route("/<int:user_id>", methods=["DELETE"])
@jwt_required()
def delete_user(user_id: int):
    current_user_id = get_jwt_identity()
    if user_id != current_user_id:
        return error_response("Unauthorized: You can only delete your own account.", 403)

    user = User.query.get_or_404(user_id)
    
    # Delete user's profile picture if it exists
    if user.profile_picture and user.profile_picture.startswith('/uploads/'):
        _delete_old_avatar(user.profile_picture)
    
    db.session.delete(user)
    db.session.commit()
    return success_response(message="User deleted successfully")


# ✅ Get current user profile
@users_bp.route("/me", methods=["GET"])
@jwt_required()
def get_me():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)
    return success_response(user.to_dict(exclude=["password_hash"]))


# ✅ Update current user profile (for Flutter)
@users_bp.route("/me", methods=["PATCH"])
@jwt_required()
def update_me():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)
    data = request.get_json() or {}

    allowed_fields = ["username", "email", "profile_picture"]
    for key in allowed_fields:
        if key in data and data[key] is not None:
            setattr(user, key, data[key])

    db.session.commit()
    return success_response(
        user.to_dict(exclude=["password_hash"]),
        "Profile updated successfully"
    )


# ✅ Upload profile avatar (Robust, deployment-friendly version)
@users_bp.route("/me/avatar", methods=["POST"])
@jwt_required()
def upload_avatar():
    user_id = get_jwt_identity()
    user = User.query.get_or_404(user_id)

    if "avatar" not in request.files:
        return error_response("No file uploaded. Please include an 'avatar' field.", 400)

    file = request.files["avatar"]

    if file.filename == "":
        return error_response("No selected file.", 400)

    if not allowed_file(file.filename):
        allowed_extensions = ", ".join(Config.ALLOWED_EXTENSIONS)
        return error_response(f"Invalid file type. Allowed: {allowed_extensions}.", 400)

    try:
        # Generate unique filename with UUID to prevent conflicts
        timestamp = int(datetime.utcnow().timestamp())
        unique_id = uuid.uuid4().hex[:8]  # Add random component
        extension = file.filename.rsplit('.', 1)[1].lower()
        filename = f"avatar_{user_id}_{timestamp}_{unique_id}.{extension}"
        filename = secure_filename(filename)

        # Get upload folder from config (works in any environment)
        upload_folder = Config.get_upload_folder()
        file_path = os.path.join(upload_folder, filename)

        # Save file
        file.save(file_path)
        
        # Verify file was saved
        if not os.path.exists(file_path):
            raise Exception("File was not saved successfully")

        print(f"✅ Avatar saved: {file_path}")
        print(f"✅ File size: {os.path.getsize(file_path)} bytes")
        print(f"✅ Environment: {Config.ENV}")

        # Delete old avatar if it exists
        if user.profile_picture and user.profile_picture.startswith('/uploads/'):
            _delete_old_avatar(user.profile_picture)

        # Store relative path in database (consistent across environments)
        user.profile_picture = f"/uploads/{filename}"
        db.session.commit()

        return success_response({
            "user": user.to_dict(exclude=["password_hash"]),
            "avatar_url": user.profile_picture,  # Relative path
            "filename": filename,
            "environment": Config.ENV,
            "message": "Avatar uploaded successfully"
        })

    except Exception as e:
        print(f"❌ Upload error in {Config.ENV}: {str(e)}")
        return error_response(f"Upload failed: {str(e)}", 500)


# ✅ Serve uploaded files (Universal - works in any environment)
@users_bp.route("/uploads/<filename>")
def serve_uploaded_file(filename):
    """Serve uploaded files - works in any environment"""
    try:
        upload_folder = Config.get_upload_folder()
        filename = secure_filename(filename)
        
        # Security: prevent directory traversal
        if '..' in filename or filename.startswith('/'):
            return error_response("Invalid filename", 400)
        
        file_path = os.path.join(upload_folder, filename)
        if not os.path.exists(file_path):
            print(f"❌ File not found: {filename} in {upload_folder}")
            return _serve_default_avatar()
        
        return send_from_directory(upload_folder, filename)
        
    except Exception as e:
        print(f"❌ Error serving file {filename}: {str(e)}")
        return _serve_default_avatar()


def _serve_default_avatar():
    """Serve a default avatar when file is not found"""
    try:
        upload_folder = Config.get_upload_folder()
        default_path = os.path.join(upload_folder, 'default-avatar.png')
        
        if os.path.exists(default_path):
            return send_from_directory(upload_folder, 'default-avatar.png')
        
        # Generate a simple default avatar as fallback
        try:
            from PIL import Image, ImageDraw
            import io
            
            img = Image.new('RGB', (100, 100), color=(74, 205, 196))
            draw = ImageDraw.Draw(img)
            draw.ellipse([20, 20, 80, 80], outline='white', width=3)
            
            img_io = io.BytesIO()
            img.save(img_io, 'PNG')
            img_io.seek(0)
            
            return send_file(img_io, mimetype='image/png')
        except ImportError:
            # PIL not available, return error
            return error_response("Default avatar not available", 404)
        
    except Exception as e:
        return error_response("Avatar not available", 404)


def _delete_old_avatar(avatar_path):
    """Safely delete old avatar file"""
    try:
        if avatar_path and avatar_path.startswith('/uploads/'):
            filename = avatar_path.split('/')[-1]
            upload_folder = Config.get_upload_folder()
            old_file_path = os.path.join(upload_folder, filename)
            
            if os.path.exists(old_file_path):
                os.remove(old_file_path)
                print(f"🗑️ Deleted old avatar: {old_file_path}")
                return True
    except Exception as e:
        print(f"⚠️ Could not delete old avatar: {str(e)}")
    return False


# ✅ Debug route to check upload configuration
@users_bp.route("/debug/upload-config", methods=["GET"])
def debug_upload_config():
    """Debug route to check upload configuration"""
    upload_folder = Config.get_upload_folder()
    exists = os.path.exists(upload_folder)
    files = []
    
    if exists:
        files = os.listdir(upload_folder)
        file_info = []
        for f in files:
            file_path = os.path.join(upload_folder, f)
            if os.path.isfile(file_path):
                file_info.append({
                    'name': f,
                    'size': os.path.getsize(file_path),
                    'modified': datetime.fromtimestamp(os.path.getmtime(file_path)).isoformat()
                })
        files = file_info
    
    return success_response({
        'environment': Config.ENV,
        'upload_folder': upload_folder,
        'upload_folder_exists': exists,
        'absolute_path': os.path.abspath(upload_folder),
        'base_url': Config.get_base_url(),
        'max_file_size': Config.MAX_CONTENT_LENGTH,
        'allowed_extensions': list(Config.ALLOWED_EXTENSIONS),
        'files_count': len(files),
        'files': files
    })


# ✅ Clean up broken profile picture references
@users_bp.route("/admin/cleanup-broken-avatars", methods=["POST"])
@jwt_required()
def cleanup_broken_avatars():
    """Admin route to find and fix broken avatar references"""
    try:
        user_id = get_jwt_identity()
        current_user = User.query.get(user_id)
        
        # Check if user is admin
        if not current_user or not getattr(current_user, 'is_admin', False):
            return error_response("Admin access required", 403)
        
        upload_folder = Config.get_upload_folder()
        existing_files = set(os.listdir(upload_folder)) if os.path.exists(upload_folder) else set()
        
        broken_users = []
        fixed_users = []
        
        # Check all users for broken avatar references
        all_users = User.query.all()
        for user in all_users:
            if user.profile_picture and user.profile_picture.startswith('/uploads/'):
                filename = user.profile_picture.split('/')[-1]
                if filename not in existing_files:
                    broken_users.append({
                        'user_id': user.id,
                        'username': user.username,
                        'broken_avatar': user.profile_picture
                    })
                    
                    # Fix it by setting to NULL
                    user.profile_picture = None
                    fixed_users.append(user.id)
        
        if fixed_users:
            db.session.commit()
        
        return success_response({
            'broken_users_found': len(broken_users),
            'fixed_users_count': len(fixed_users),
            'broken_users': broken_users,
            'fixed_user_ids': fixed_users,
            'environment': Config.ENV,
            'message': f'Fixed {len(fixed_users)} broken avatar references in {Config.ENV}'
        })
        
    except Exception as e:
        return error_response(f"Cleanup failed: {str(e)}", 500)


# ✅ Health check for file serving
@users_bp.route("/health/files", methods=["GET"])
def health_check_files():
    """Health check endpoint for file serving system"""
    try:
        upload_folder = Config.get_upload_folder()
        exists = os.path.exists(upload_folder)
        writable = os.access(upload_folder, os.W_OK) if exists else False
        
        # Test creating a temporary file
        test_success = False
        if exists and writable:
            try:
                test_file = os.path.join(upload_folder, 'health_check.tmp')
                with open(test_file, 'w') as f:
                    f.write('test')
                os.remove(test_file)
                test_success = True
            except:
                test_success = False
        
        return success_response({
            'environment': Config.ENV,
            'upload_system_healthy': exists and writable and test_success,
            'upload_folder_exists': exists,
            'upload_folder_writable': writable,
            'test_file_creation': test_success,
            'upload_folder': upload_folder,
            'base_url': Config.get_base_url()
        })
        
    except Exception as e:
        return error_response(f"Health check failed: {str(e)}", 500)
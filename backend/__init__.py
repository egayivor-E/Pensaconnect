# backend/__init__.py
from __future__ import annotations
from datetime import datetime
import os
import logging
from pathlib import Path
from typing import Optional
import secrets
from flask import g, request

from backend.admin import admin
from flask import Blueprint, Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from flask_smorest import Api   # type: ignore # ✅ Swagger API
from backend.models import User
from backend.routes.admin_auth import admin_auth

# ✅ ADD WEBSOCKET IMPORTS
from flask_socketio import SocketIO, emit, join_room, leave_room

from backend.config import ProductionConfig, DevelopmentConfig, TestingConfig, StagingConfig
from backend.extensions import (
    configure_extensions, db, limiter, jwt, 
    cache, init_celery, celery
)
from backend.middleware import register_error_handlers
from backend.api import api_v1

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

# ✅ ADD GLOBAL SOCKETIO INSTANCE
socketio = None

def _set_csp_headers(app: Flask):
    @app.before_request
    def set_nonce():
        # Generate a random nonce per request
        g.csp_nonce = secrets.token_urlsafe(16)

    @app.after_request
    def apply_csp(response):
        nonce = getattr(g, "csp_nonce", "")
        csp = (
            f"default-src 'self'; "
            f"script-src 'self' 'nonce-{nonce}' https://cdn.jsdelivr.net; "
            f"style-src 'self' 'nonce-{nonce}' https://cdn.jsdelivr.net; "
            f"img-src 'self' data:; "
            f"font-src 'self' https://cdn.jsdelivr.net; "
            f"connect-src 'self'; "
            f"object-src 'none'; "
            f"base-uri 'self'; "
            f"form-action 'self'; "
        )
        response.headers["Content-Security-Policy"] = csp
        return response

# ✅ ADD WEBSOCKET EVENT HANDLERS
def _register_websocket_events(socketio_instance):
    """Register WebSocket event handlers"""
    
    @socketio_instance.on('connect')
    def handle_connect():
        logger.info(f"🔌 WebSocket client connected: {request.sid}")
        emit('connected', {'message': 'Connected to WebSocket', 'sid': request.sid})
    
    @socketio_instance.on('disconnect')
    def handle_disconnect():
        logger.info(f"🔌 WebSocket client disconnected: {request.sid}")
    
    @socketio_instance.on('join_group')
    def handle_join_group(data):
        try:
            group_id = data.get('groupId')
            if group_id:
                room_name = f'group_{group_id}'
                join_room(room_name)
                logger.info(f"👥 Client {request.sid} joined group {group_id}")
                emit('joined_group', {
                    'message': f'Joined group {group_id}',
                    'groupId': group_id
                }, room=request.sid)
            else:
                emit('error', {'message': 'Missing groupId'})
        except Exception as e:
            logger.error(f"Error joining group: {e}")
            emit('error', {'message': str(e)})
    
    @socketio_instance.on('leave_group')
    def handle_leave_group(data):
        try:
            group_id = data.get('groupId')
            if group_id:
                room_name = f'group_{group_id}'
                leave_room(room_name)
                logger.info(f"👥 Client {request.sid} left group {group_id}")
                emit('left_group', {
                    'message': f'Left group {group_id}',
                    'groupId': group_id
                }, room=request.sid)
        except Exception as e:
            logger.error(f"Error leaving group: {e}")
    
    @socketio.on("new_message")
    def handle_new_message(data):
        from backend.models import db, User, GroupMessage

        try:
            group_id = data.get("groupId")
            content = data.get("content")
            sender_id = data.get("senderId")

            if not group_id or not content or not sender_id:
                emit("error", {"message": "Missing required fields"})
                return

            # ✅ Fetch actual user instance
            sender = db.session.get(User, sender_id)
            if not sender:
                emit("error", {"message": "Sender not found"})
                return

            # ✅ Create and save message
            new_msg = GroupMessage(
            group_chat_id=group_id,  # ✅ Correct field name
            sender_id=sender_id,
            content=content,
            )
            db.session.add(new_msg)
            db.session.commit()

            # ✅ Broadcast to group room
            emit(
                "message_received",
                {
                    "id": new_msg.id,
                    "groupId": group_id,
                    "content": new_msg.content,
                    "createdAt": new_msg.created_at.isoformat(),
                    "sender": {
                        "id": sender.id,
                        "full_name": getattr(sender, "full_name", sender.username),
                        "avatar": getattr(sender, "avatar_url", None),
                    },
                },
                room=f"group_{group_id}",
                include_self=True,
            )

            print(f"✅ Broadcasted message from {sender.username} to group {group_id}")

        except Exception as e:
            import traceback
            traceback.print_exc()
            emit("error", {"message": str(e)})

    @socketio_instance.on('typing_start')
    def handle_typing_start(data):
        group_id = data.get('groupId')
        user_id = data.get('userId')
        if group_id and user_id:
            room_name = f'group_{group_id}'
            emit('user_typing', {
                'userId': user_id,
                'groupId': group_id,
                'typing': True
            }, room=room_name, include_self=False)
    
    @socketio_instance.on('typing_stop')
    def handle_typing_stop(data):
        group_id = data.get('groupId')
        user_id = data.get('userId')
        if group_id and user_id:
            room_name = f'group_{group_id}'
            emit('user_typing', {
                'userId': user_id,
                'groupId': group_id,
                'typing': False
            }, room=room_name, include_self=False)

def create_app(config_name: Optional[str] = None) -> Flask:
    """Application factory for creating Flask app"""
    root_dir = Path(__file__).parent.parent
    frontend_build = root_dir / "frontend" / "build"

    static_folder = str(frontend_build) if frontend_build.exists() else None
    app = Flask(
        __name__,
        static_folder=static_folder,
        static_url_path="/" if static_folder else None,
    )
    
    # ✅ Config FIRST (before extensions)
    _configure_app(app, config_name)
    
    # ✅ Configure API docs BEFORE creating Api instance
    _configure_api_docs(app)
    
    # ✅ SIMPLE CORS configuration
    CORS(app,
     resources={r"/api/*": {
         "origins": [
             "http://localhost:58672",
             "http://localhost:*",
             "http://127.0.0.1:*",
             "http://0.0.0.0:*"
         ],
         "methods": ["GET", "POST", "PUT","PATCH", "DELETE", "OPTIONS"],
         "allow_headers": ["Content-Type", "Authorization"],
         "supports_credentials": True,
         "expose_headers": ["Content-Type", "Authorization"],
         
         r"/uploads/*": {  # ✅ ADD THIS FOR UPLOADS
         "origins": "*",  # Allow all origins for images
         "methods": ["GET", "OPTIONS"],
         "allow_headers": ["Content-Type"],
         "expose_headers": ["Content-Type"]
     }
     }})
    
    # ✅ Extensions AFTER config
    configure_extensions(app)
    admin.init_app(app)
    
    # ✅ WEBSOCKET SETUP
    global socketio
    socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    logger=True,
    engineio_logger=True,
    async_mode='threading'
    )

    
    # ✅ Register WebSocket events
    _register_websocket_events(socketio)
    
    # ✅ Secure CSP headers with nonce
    _set_csp_headers(app)

    # ✅ API setup - NOW this will work because config is already set
    api = Api(app)

    # 🔹 Register the single API v1 blueprint directly
    app.register_blueprint(api_v1)
    app.register_blueprint(admin_auth)
    
    logger.info("✅ API v1 blueprint registered successfully")

    # Cache, Celery, Middleware
    _configure_cache(app)
    _configure_celery(app)
    _register_middleware(app)
    _register_cli(app)
    register_health(app)
    
    @app.before_request
    def log_request_info():
        logger.info(f"Incoming request: {request.method} {request.path}")
        logger.info(f"Origin: {request.headers.get('Origin')}")

    # ✅ Serve frontend (SPA fallback)
    @app.route("/", defaults={"path": ""})
    @app.route("/<path:path>")
    def serve(path: str):
        if not frontend_build.exists():
            logger.warning("⚠️ Frontend build not found at %s", frontend_build)
            return jsonify({"error": "Frontend not built"}), 404

        file_path = frontend_build / path
        if file_path.exists() and file_path.is_file():
            return send_from_directory(frontend_build, path)

        return send_from_directory(frontend_build, "index.html")
    
    @app.route("/uploads/<path:filename>")
    def serve_uploads(filename):
        project_root = Path(app.root_path).parent
        upload_folder = os.path.join(project_root, "uploads")
        
        # Check if uploads folder exists
        if not os.path.exists(upload_folder):
            logger.error(f"❌ Uploads folder doesn't exist: {upload_folder}")
            return jsonify({"error": "Uploads directory not found"}), 404
        
        # Check if file exists
        file_path = os.path.join(upload_folder, filename)
        if not os.path.exists(file_path):
            # Log what files are available for debugging
            available_files = os.listdir(upload_folder)
            logger.warning(f"⚠️ File not found: {filename}")
            logger.warning(f"📁 Available files: {available_files}")
            return jsonify({
                "error": "File not found", 
                "requested": filename,
                "available": available_files
            }), 404
        
        logger.info(f"✅ Serving file: {file_path}")
        response = send_from_directory(upload_folder, filename)
        response.headers.add("Access-Control-Allow-Origin", "*")
        return response
    @app.context_processor
    def inject_nonce():
         return {"csp_nonce": getattr(g, "csp_nonce", "")}
    return app

# ---------------- Config ----------------
def _configure_app(app: Flask, config_name: Optional[str]):
    if not config_name:
        config_name = os.getenv("FLASK_ENV", "development")

    config_map = {
        "production": ProductionConfig,
        "staging": StagingConfig,
        "testing": TestingConfig,
        "development": DevelopmentConfig,
    }
    app.config.from_object(config_map.get(config_name, DevelopmentConfig))
    app.config.from_pyfile("config.py", silent=True)
    app.config.from_prefixed_env()

    os.makedirs(app.instance_path, exist_ok=True)
    app.config["ENV"] = config_name

def _configure_api_docs(app: Flask):
    """Configure OpenAPI / Swagger / Redoc docs - MUST be called before Api() creation"""
    app.config.update(
        API_TITLE="PensaConnect API",
        API_VERSION="v1",
        OPENAPI_VERSION="3.0.3",
        OPENAPI_URL_PREFIX="/docs",
        OPENAPI_SWAGGER_UI_PATH="/swagger-ui",
        OPENAPI_SWAGGER_UI_URL="https://cdn.jsdelivr.net/npm/swagger-ui-dist/",
        OPENAPI_REDOC_PATH="/redoc",
        OPENAPI_REDOC_URL="https://cdn.jsdelivr.net/npm/redoc/bundles/redoc.standalone.js",
    )
    logger.info("✅ API Docs configured") 

# ---------------- Cache / Celery ----------------
def _configure_cache(app: Flask):
    """Configure cache if available"""
    if cache:
        try:
            cache.init_app(app)
            logger.info("✅ Cache initialized")
        except Exception as e:
            logger.warning(f"⚠️ Cache initialization failed: {e}")

def _configure_celery(app: Flask):
    """Configure Celery if available"""
    if celery:
        try:
            # Initialize celery with app context
            init_celery(app)
            logger.info("✅ Celery initialized")
            
            # Try to register tasks
            try:
                from backend.tasks import register_tasks
                register_tasks(celery)
                logger.info("✅ Celery tasks registered")
            except ImportError:
                logger.warning("⚠️ No tasks module found, skipping Celery tasks")
        except Exception as e:
            logger.warning(f"⚠️ Celery initialization failed: {e}")

# ---------------- Middleware ----------------
def _register_middleware(app: Flask):
    """Register middleware and error handlers"""
    register_error_handlers(app)

    @app.before_request
    def log_request():
        logger.debug(f"{request.method} {request.path}")

# ---------------- CLI ----------------
def _register_cli(app: Flask):
    """Register CLI commands"""
    @app.cli.command("init-db")
    def init_db():
        """Initialize database"""
        with app.app_context():
            db.create_all()
            logger.info("✅ Database initialized")

    @app.cli.command("seed-db")
    def seed_db():
        """Seed database with sample data"""
        with app.app_context():
            try:
                from backend.seeds import seed_database
                seed_database()
                logger.info("✅ Database seeded")
            except ImportError:
                logger.warning("⚠️ Seed module not found")

    @app.cli.command("create-admin")
    def create_admin():
        """Create admin user"""
        with app.app_context():
            try:
                from backend.utils import create_admin_user
                create_admin_user()
                logger.info("✅ Admin user created")
            except ImportError:
                logger.warning("⚠️ Utils module not found")

# ---------------- Health ----------------
def register_health(app: Flask):
    """Register health check endpoints"""
    @app.route("/health")
    def health_check():
        """Health check endpoint"""
        try:
            db.session.execute("SELECT 1")
            db_status = "connected"
        except Exception as e:
            db_status = f"disconnected: {str(e)}"

        return jsonify({
            "status": "healthy",
            "environment": app.config.get("ENV", "unknown"),
            "database": db_status,
        })

    @app.route("/ping")
    def ping():
        """Simple ping endpoint"""
        return jsonify({"status": "ok", "message": "pong"})

# ✅ ADD THIS: Make socketio available for running the app
def get_socketio():
    return socketio
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
from flask_jwt_extended import decode_token

from backend.config import Config, ProductionConfig, DevelopmentConfig, RenderConfig, TestingConfig, StagingConfig
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
            f"connect-src 'self' https://pensaconnect-pjz9.onrender.com https://pensaconnect-pjz9.onrender.com https://pensaconnect-1.onrender.com; "
            f"object-src 'none'; "
            f"base-uri 'self'; "
            f"form-action 'self'; "
        )
        response.headers["Content-Security-Policy"] = csp
        return response

# ✅ SAFE EMIT HELPER FUNCTION
def safe_emit(event, data, room=None, skip_sid=None, include_self=True):
    """Safely emit events with proper context handling"""
    try:
        if room:
            emit(event, data, room=room, skip_sid=skip_sid, include_self=include_self)
        else:
            emit(event, data, skip_sid=skip_sid, include_self=include_self)
        return True
    except Exception as e:
        logger.error(f"❌ Emit error for event {event}: {e}")
        return False

# ✅ ENHANCED WEBSOCKET EVENT HANDLERS
def _register_websocket_events(socketio_instance):
    """
    Production-ready WebSocket event handlers.
    Tracks connected users, rooms, typing, and safe message delivery.
    """
    connected_users = {}  # {socket_id: {'user_id': int, 'rooms': set, 'connected_at': datetime}}
    user_typing = {}      # {group_id: set(user_ids)}

    # ---------------- Helper Functions ----------------
    def safe_emit(event, data, room=None, skip_sid=None, include_self=True):
        """Emit safely with logging."""
        try:
            if room:
                socketio_instance.emit(event, data, room=room, skip_sid=skip_sid, include_self=include_self)
            else:
                socketio_instance.emit(event, data, skip_sid=skip_sid, include_self=include_self)
            return True
        except Exception as e:
            logger.error(f"Emit error for event '{event}': {e}")
            return False

    def get_connected_users_count(group_id):
        """Count users in a specific group room."""
        room_name = f"group_{group_id}"
        return sum(1 for u in connected_users.values() if room_name in u.get('rooms', set()))

    def _is_rate_limited(user_id, group_id):
        """Simple memory-based rate limiting for free tier"""
        import time
        from flask import current_app
        
        if not hasattr(current_app, 'rate_limit_store'):
            current_app.rate_limit_store = {}
        
        key = f"{user_id}:{group_id}"
        current_time = time.time()
        
        # Initialize for this key
        if key not in current_app.rate_limit_store:
            current_app.rate_limit_store[key] = []
        
        # Clean old entries (older than 1 minute)
        current_app.rate_limit_store[key] = [
            t for t in current_app.rate_limit_store[key]
            if current_time - t < 60  # 1 minute window
        ]
        
        # Check limit (10 messages per minute)
        if len(current_app.rate_limit_store[key]) >= 10:
            return True
        
        # Add this request
        current_app.rate_limit_store[key].append(current_time)
        return False

    # ---------------- Connection ----------------
    @socketio_instance.on("connect")
    def handle_connect(auth=None):
        try:
            token = request.args.get("token")
            if not token:
                logger.warning(f"No token provided for {request.sid}")
                return False  # reject connection

            decoded = decode_token(token)
            user_id = decoded.get("sub")
            if not user_id:
                logger.warning(f"Invalid token payload: {request.sid}")
                return False

            connected_users[request.sid] = {
                "user_id": user_id,
                "rooms": set(),
                "connected_at": datetime.utcnow()
            }

            safe_emit("connected", {
                "status": "success",
                "sid": request.sid,
                "userId": user_id,
                "timestamp": datetime.utcnow().isoformat()
            }, room=request.sid)

            logger.info(f"✅ User {user_id} connected via WebSocket (SID: {request.sid})")

        except Exception as e:
            logger.error(f"WebSocket authentication failed: {e}")
            return False

    @socketio_instance.on("disconnect")
    def handle_disconnect():
        user_info = connected_users.pop(request.sid, None)
        if user_info:
            logger.info(f"❌ User {user_info['user_id']} disconnected (SID: {request.sid})")
        else:
            logger.info(f"❌ Unknown SID disconnected: {request.sid}")

    # ---------------- Join / Leave Rooms ----------------
    @socketio_instance.on("join_group")
    def handle_join_group(data):
        group_id = int(data.get("groupId"))
        room = f"group_{group_id}"
        join_room(room)

        if request.sid in connected_users:
            connected_users[request.sid]["rooms"].add(room)

        safe_emit("joined", {"groupId": group_id}, room=request.sid)
        logger.info(f"✅ User {request.sid} joined room {room}")

    @socketio_instance.on("leave_group")
    def handle_leave_group(data):
        group_id = int(data.get("groupId"))
        room = f"group_{group_id}"
        leave_room(room)

        if request.sid in connected_users:
            connected_users[request.sid]["rooms"].discard(room)

        safe_emit("left", {"groupId": group_id}, room=request.sid)
        logger.info(f"⚠️ User {request.sid} left room {room}")

    # ================================================================
    # ✅ PRODUCTION FIX: WebSocket send_message - Broadcasts to ALL clients
    # The HTTP POST /group-chats/$groupId/messages handles saving
    # ================================================================
    @socketio_instance.on("send_message")
    def handle_send_message(data):
        """
        Handle incoming WebSocket message.
        ✅ Uses message ID from frontend (sent by Flutter after HTTP save)
        ✅ Broadcasts to ALL clients in the room (including sender)
        ✅ NO DATABASE SAVE (HTTP handles saving)
        """
        try:
            logger.debug(f"DEBUG send_message received data: {data}")
            
            # Get user info
            user_info = connected_users.get(request.sid, {})
            user_id = user_info.get("user_id")
            
            if not user_id:
                logger.error("❌ Unauthenticated socket - user not found in connected_users")
                safe_emit("send_error", {"error": "Unauthenticated"}, room=request.sid)
                return
            
            # Get message data
            group_id = data.get("groupId") or data.get("group_id")
            content = data.get("content")
            
            logger.debug(f"DEBUG: group_id={group_id}, content={content}")
            
            # Validate data
            if group_id is None:
                safe_emit("send_error", {"error": "Missing groupId"}, room=request.sid)
                return
            if content is None:
                safe_emit("send_error", {"error": "Missing content"}, room=request.sid)
                return
            
            group_id = int(group_id)
            
            if not content.strip():
                safe_emit("send_error", {"error": "Message content empty"}, room=request.sid)
                return
            
            if _is_rate_limited(user_id, group_id):
                safe_emit("send_error", {"error": "Rate limit exceeded"}, room=request.sid)
                return
            
            # ✅ Get the message ID from frontend (sent after HTTP save)
            message_id = data.get("id")
            
            # If no ID provided, generate a temporary one (shouldn't happen with fixed frontend)
            if message_id is None or message_id == 0:
                import time
                message_id = int(time.time() * 1000)
                logger.warning(f"⚠️ No ID provided by frontend, using temporary ID: {message_id}")
            else:
                logger.info(f"✅ Using message ID from frontend: {message_id}")
            
            # ✅ SECURITY/CORRECTNESS FIX: look the sender up server-side from
            # the authenticated user_id instead of trusting whatever
            # "sender" object the client included in the payload. Trusting
            # client-supplied sender data meant (a) a client could claim to
            # be anyone, and (b) any client that forgot to attach full
            # sender info (e.g. a thin payload) broadcast "Unknown User"
            # with no picture to everyone else in the room.
            sender_name = "Unknown User"
            sender_username = "unknown"
            sender_profile_picture = None
            try:
                sender_user = User.query.get(user_id)
                if sender_user:
                    sender_name = (
                        sender_user.get_full_name()
                        if hasattr(sender_user, "get_full_name")
                        else sender_user.username
                    )
                    sender_username = sender_user.username
                    sender_profile_picture = getattr(sender_user, "profile_picture", None)
                else:
                    logger.warning(f"⚠️ send_message: no User row for user_id={user_id}")
            except Exception as e:
                logger.error(f"❌ Failed to look up sender {user_id} for broadcast: {e}")
            
            # Get timestamp
            created_at = data.get("createdAt")
            if created_at is None:
                created_at = datetime.utcnow().isoformat()
            
            # Get message type
            message_type = data.get("messageType", "text")
            
            # ✅ Format message for broadcasting using the ID from frontend
            message_data = {
                "id": message_id,
                "groupId": group_id,
                "senderId": user_id,
                "content": content.strip(),
                "messageType": message_type,
                "createdAt": created_at,
                "timestamp": datetime.utcnow().isoformat(),
                "sender": {
                    "id": user_id,
                    "username": sender_username,
                    "full_name": sender_name,
                    "profile_picture": sender_profile_picture
                }
            }
            
            # ✅ FIXED: Broadcast to ALL clients in the room
            # This ensures everyone (including the sender) gets the message
            room_name = f"group_{group_id}"
            
            # Emit to all clients in the room
            safe_emit(
                "new_message",
                message_data,
                room=room_name,
                skip_sid=None,      # ✅ Don't skip anyone
                include_self=True   # ✅ Include the sender
            )
            
            # ✅ Log the broadcast
            logger.info(f"📩 Broadcasted message ID {message_id} to room {room_name} ({get_connected_users_count(group_id)} users)")
            
        except Exception as e:
            logger.error(f"❌ Message broadcast failed: {e}")
            logger.error(f"Error details:", exc_info=True)
            safe_emit("send_error", {"error": str(e)}, room=request.sid)

    # ---------------- Typing Indicator ----------------
    @socketio_instance.on("typing")
    def handle_typing(data):
        group_id = int(data.get("groupId"))
        user_id = connected_users.get(request.sid, {}).get("user_id")
        if not user_id:
            return

        user_typing.setdefault(group_id, set()).add(user_id)
        safe_emit("user_typing", {"user_id": user_id, "group_id": group_id}, room=f"group_{group_id}", include_self=False)

    @socketio_instance.on("stop_typing")
    def handle_stop_typing(data):
        group_id = int(data.get("group_id"))
        user_id = connected_users.get(request.sid, {}).get("user_id")
        if not user_id:
            return

        user_typing.setdefault(group_id, set()).discard(user_id)
        safe_emit("user_stop_typing", {"user_id": user_id, "group_id": group_id}, room=f"group_{group_id}", include_self=False)

    # ---------------- Error Handling ----------------
    @socketio_instance.on_error_default
    def socket_error_handler(e):
        logger.error(f"Socket.IO error: {e}")



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
    
    # ============ CORS CONFIGURATION - FIXED ============
    # Determine allowed origins based on environment
    is_production = config_name in ['production', 'render'] or os.getenv('FLASK_ENV') == 'production'
    
    if is_production:
        # Production: explicit allowed origins only
        ALLOWED_ORIGINS = [
            "https://pensaconnect-pjz9.onrender.com",  # Backend URL
            "https://pensaconnect-1.onrender.com",     # ✅ Frontend URL - ADDED
            "https://pensaconnect.onrender.com",       # Main domain
        ]
        print(f"🔒 Production CORS origins: {ALLOWED_ORIGINS}")
    else:
        # Development: allow localhost with any port
        ALLOWED_ORIGINS = [
            "http://localhost:3000",
            "http://localhost:5000",
            "http://localhost:58672",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5000",
            "http://127.0.0.1:58672",
            "http://0.0.0.0:5000",
            "http://0.0.0.0:58672",
        ]
        print("🔓 Development CORS mode enabled")
    
    # SINGLE CORS configuration
    CORS(app,
        resources={
            r"/api/*": {
                "origins": ALLOWED_ORIGINS,
                "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
                "allow_headers": ["Content-Type", "Authorization", "X-Requested-With"],
                "expose_headers": ["Content-Type", "Authorization"],
                "supports_credentials": True,
                "max_age": 3600
            },
            r"/auth/*": {
                "origins": ALLOWED_ORIGINS,
                "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
                "allow_headers": ["Content-Type", "Authorization"],
                "supports_credentials": True,
            },
            r"/uploads/*": {
                "origins": ALLOWED_ORIGINS,
                "methods": ["GET", "OPTIONS"],
                "allow_headers": ["Content-Type"],
            },
        }
    )
    
    # ============ WEBSOCKET SETUP ============
    global socketio
    
    socketio = SocketIO(
        app,
        cors_allowed_origins=ALLOWED_ORIGINS if is_production else "*",
        logger=not is_production,
        engineio_logger=not is_production,
        async_mode='gevent',
        ping_timeout=60,
        ping_interval=25,
        max_http_buffer_size=1000000
    )

    # ✅ Register WebSocket events IMMEDIATELY after SocketIO creation
    _register_websocket_events(socketio)
    
    # ✅ THEN configure other extensions
    configure_extensions(app)
    admin.init_app(app)
    
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

    # ✅ WebSocket health check
    @app.route("/ws-health")
    def ws_health():
        return jsonify({
            "status": "healthy", 
            "websocket": "enabled",
            "connected_clients": len(socketio.server.manager.rooms.get('/', {}))
        })

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
        # ✅ FIX: this used to compute its own path
        # (Path(app.root_path).parent / "uploads"), which is *not* the same
        # folder avatars are actually saved to — that's
        # Config.get_upload_folder(), which honors the UPLOAD_FOLDER env
        # var (e.g. a persistent disk mount on Render). The mismatch meant
        # every freshly-uploaded avatar 404'd immediately when requested
        # from this root-level route, regardless of whether the file on
        # disk was still there. Route through the same helper everything
        # else uses so "where it was saved" and "where it's served from"
        # can never drift apart again.
        upload_folder = Config.get_upload_folder()

        # Check if file exists
        file_path = os.path.join(upload_folder, filename)
        if not os.path.exists(file_path):
            # Log what files are available for debugging
            available_files = os.listdir(upload_folder) if os.path.exists(upload_folder) else []
            logger.warning(f"⚠️ File not found: {filename} in {upload_folder}")
            logger.warning(f"📁 Available files: {available_files}")
            return jsonify({
                "error": "File not found",
                "requested": filename,
                "upload_folder": upload_folder,
                "available": available_files
            }), 404
        
        logger.info(f"✅ Serving file: {file_path}")
        response = send_from_directory(upload_folder, filename)
        return response
        
    @app.context_processor
    def inject_nonce():
         return {"csp_nonce": getattr(g, "csp_nonce", "")}
         
    logger.info("✅ Flask app created successfully with WebSocket support")
    return app

# ---------------- Config ----------------
def _configure_app(app: Flask, config_name: Optional[str]):
    if not config_name:
        config_name = os.getenv("FLASK_ENV", "development")
    
    # ✅ AUTO-DETECT RENDER
    if 'RENDER' in os.environ:
        config_name = 'render'
        print("🚀 Detected Render environment - using RenderConfig")

    config_map = {
        "production": ProductionConfig,
        "staging": StagingConfig,
        "testing": TestingConfig,
        "development": DevelopmentConfig,
        "render": RenderConfig,
    }
    
    config_class = config_map.get(config_name, DevelopmentConfig)
    app.config.from_object(config_class)
    
    # ✅ Initialize RenderConfig if needed (AFTER defining config_class)
    if config_name == 'render' and hasattr(config_class, 'init_app'):
        config_class.init_app(app)
    
    app.config.from_pyfile("config.py", silent=True)
    app.config.from_prefixed_env()
    app.config['ADMIN_EMAIL'] = os.getenv('ADMIN_EMAIL')
    app.config['MAIL_SERVER'] = os.getenv('MAIL_SERVER', 'smtp.gmail.com')
    app.config['MAIL_PORT'] = int(os.getenv('MAIL_PORT', 587))
    app.config['MAIL_USE_TLS'] = os.getenv('MAIL_USE_TLS', 'True').lower() in ['true', 'on', '1']
    app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME')
    app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD')

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

# ✅ Make socketio available for running the app
def get_socketio():
    return socketio

# ✅ Add this to ensure proper app context for WebSocket
def run_app():
    """Run the application with Socket.IO support"""
    app = create_app()
    socketio_instance = get_socketio()
    
    if socketio_instance is None:
        raise RuntimeError("Socket.IO not initialized")
    
    logger.info("🚀 Starting PensaConnect with WebSocket support...")
    socketio_instance.run(
        app, 
        host='0.0.0.0', 
        port=5000, 
        debug=True,
        allow_unsafe_werkzeug=True
    )
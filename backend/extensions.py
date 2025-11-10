import os
import logging
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_talisman import Talisman
from flask_compress import Compress
from flask_caching import Cache
from celery import Celery
from flask_login import LoginManager


# Core extensions
db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()
cors = CORS()
talisman = Talisman()
compress = Compress()

# Globals for cache, limiter, celery
cache = Cache()
limiter = Limiter(key_func=get_remote_address, default_limits=["200 per day", "1000 per hour"])  # Set limits here
celery = None  # global Celery instance

login_manager = LoginManager()


# --- Logging setup ---
logging.basicConfig(level=logging.INFO)

def configure_extensions(app):
    """Initialize all Flask extensions with app (Redis-aware)."""
    global cache, limiter

    # --- Database ---
    db.init_app(app)
    migrate.init_app(app, db)

    # --- JWT ---
    jwt.init_app(app)
    
    
        # --- Flask-Login ---
    login_manager.init_app(app)
    
        # --- Flask-Login user loader ---
    from backend.models import User

    @login_manager.user_loader
    def load_user(user_id):
        """Flask-Login user loader: loads a user by ID from the session."""
        try:
            return User.query.get(int(user_id))
        except Exception:
            return None

    
    
    login_manager.login_view = "admin_auth.admin_login"  # route name for your login page
    login_manager.login_message = "Please log in to access this page."
    login_manager.login_message_category = "error"


    # Move JWT callbacks to avoid circular imports
    _configure_jwt_callbacks(app)

    # --- CORS --- (MINIMAL setup here - main config is in __init__.py)
    cors.init_app(app)  # Simple init, detailed config is in main app

    # --- Compression & Security ---
    talisman.init_app(app)
    compress.init_app(app)

    # --- Cache & Limiter (Redis first, fallback to in-memory) ---
    _configure_cache_and_limiter(app)


def _configure_jwt_callbacks(app):
    """Configure JWT callbacks without circular imports"""

    @jwt.user_identity_loader
    def user_identity_lookup(user_id):
        """
        Store only the user.id inside the JWT (sub).
        This makes get_jwt_identity() return an int (user.id).
        """
        return user_id

    @jwt.user_lookup_loader
    def user_lookup_callback(_jwt_header, jwt_data):
        """
        Load full User object from JWT's sub field.
        This makes flask_jwt_extended.current_user available.
        """
        from backend.models import User
        identity = jwt_data["sub"]  # just user.id now
        return User.query.filter_by(id=identity).one_or_none()


def _configure_cache_and_limiter(app):
    """Configure cache and limiter with Redis fallback"""
    global cache, limiter
    
    try:
        import redis

        redis_client = redis.StrictRedis(
            host=app.config.get("REDIS_HOST", "localhost"),
            port=app.config.get("REDIS_PORT", 6379),
            db=0,
            decode_responses=True,
            socket_connect_timeout=1,  # Faster timeout for connection test
            socket_timeout=1
        )
        redis_client.ping()  # test connection

        # Configure Redis cache
        cache.init_app(app, config={
            "CACHE_TYPE": "RedisCache",
            "CACHE_REDIS_HOST": app.config.get("REDIS_HOST", "localhost"),
            "CACHE_REDIS_PORT": app.config.get("REDIS_PORT", 6379),
            "CACHE_REDIS_URL": app.config.get("REDIS_URL", "redis://localhost:6379/0"),
            "CACHE_DEFAULT_TIMEOUT": 300,
        })

        # Configure Redis limiter - FIXED: No default_limits in init_app
        limiter.init_app(
            app,
            storage_uri=f"redis://{app.config.get('REDIS_HOST', 'localhost')}:{app.config.get('REDIS_PORT', 6379)}",
            strategy="fixed-window",
        )

        app.logger.info("✅ Redis connected: using Redis for cache & rate limiting")

    except Exception as e:
        # fallback to in-memory cache
        cache.init_app(app, config={"CACHE_TYPE": "SimpleCache"})
        
        # Initialize limiter with app (already has default_limits set)
        limiter.init_app(app)
        
        app.logger.warning(f"⚠️ Redis not available ({e}) → using in-memory cache & limiter")


def init_celery(app=None):
    """Initialize Celery with Flask app context"""
    global celery
    
    if celery is not None:
        return celery  # Already initialized

    if app is None:
        raise ValueError("Flask app is required to initialize Celery")

    celery = Celery(
        app.import_name,
        broker=app.config.get("CELERY_BROKER_URL", "redis://localhost:6379/0"),
        backend=app.config.get("CELERY_RESULT_BACKEND", "redis://localhost:6379/0")
    )

    celery.conf.update(app.config)

    class ContextTask(celery.Task):
        def __call__(self, *args, **kwargs):
            with app.app_context():
                return self.run(*args, **kwargs)

    celery.Task = ContextTask
    app.logger.info("✅ Celery initialized successfully")
    return celery

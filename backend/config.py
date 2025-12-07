import os
from datetime import timedelta
from pathlib import Path

basedir = Path(__file__).parent.parent

def _bool(key: str, default: bool = False) -> bool:
    v = os.getenv(key)
    if v is None:
        return default
    return str(v).lower() in ("1", "true", "yes", "on")

def running_in_docker() -> bool:
    return os.path.exists("/.dockerenv")

class Config:
    SECRET_KEY = os.getenv("SECRET_KEY") or os.urandom(32)
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # ✅ FIXED: Database configuration that works on Render
    if 'RENDER' in os.environ or 'DATABASE_URL' in os.environ:
        # Render provides DATABASE_URL for PostgreSQL
        db_url = os.environ.get('DATABASE_URL')
        if db_url:
            # Convert postgres:// to postgresql:// for SQLAlchemy
            if db_url.startswith('postgres://'):
                db_url = db_url.replace('postgres://', 'postgresql://', 1)
            SQLALCHEMY_DATABASE_URI = db_url
            print(f"✅ Using Render PostgreSQL: {db_url[:50]}...")
        else:
            # Fallback for Render (shouldn't happen)
            SQLALCHEMY_DATABASE_URI = "sqlite:///app.db"
            print("⚠️ Warning: Using SQLite on Render (not recommended)")
    elif running_in_docker():
        # Docker environment
        SQLALCHEMY_DATABASE_URI = os.getenv("DOCKER_DATABASE_URL")
    else:
        # Local development
        SQLALCHEMY_DATABASE_URI = (
            os.getenv("DEV_DATABASE_URL")
            or os.getenv("DATABASE_URL")
            or f"sqlite:///{basedir / 'app.db'}"
        )

    # ✅ FIXED: Disable Redis for Render free tier
    if 'RENDER' in os.environ:
        # Render free tier doesn't have Redis
        CELERY_BROKER_URL = None
        CELERY_RESULT_BACKEND = None
        print("⚠️ Redis disabled for Render free tier")
    elif running_in_docker():
        CELERY_BROKER_URL = os.getenv("DOCKER_CELERY_BROKER_URL", "redis://redis:6379/0")
        CELERY_RESULT_BACKEND = os.getenv("DOCKER_CELERY_RESULT_BACKEND", "redis://redis:6379/0")
    else:
        CELERY_BROKER_URL = os.getenv("DEV_CELERY_BROKER_URL", "redis://localhost:6379/0")
        CELERY_RESULT_BACKEND = os.getenv("DEV_CELERY_RESULT_BACKEND", "redis://localhost:6379/0")

    # ✅ FIXED: CORS - NOT allowing "*" in production
    if 'RENDER' in os.environ or os.getenv('FLASK_ENV') == 'production':
        # Production: restrict origins
        CORS_ORIGINS = os.getenv("CORS_ORIGINS", "").split(",") or []
        if not CORS_ORIGINS:
            print("⚠️ WARNING: No CORS origins configured for production!")
    else:
        # Development: allow all for testing
        CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")
    
    # Rest of your config remains the same...
    # JWT, Cache, Uploads, etc.


class RenderConfig(Config):
    """Optimized configuration for Render free tier"""
    
    # Force production settings
    DEBUG = False
    ENV = "production"
    TESTING = False
    
    @classmethod
    def init_app(cls, app):
        """Initialize app with Render-specific settings"""
        # Ensure we're using PostgreSQL on Render
        if 'RENDER' in os.environ and 'DATABASE_URL' in os.environ:
            db_url = os.environ['DATABASE_URL']
            if db_url.startswith('postgres://'):
                db_url = db_url.replace('postgres://', 'postgresql://', 1)
            app.config['SQLALCHEMY_DATABASE_URI'] = db_url
            print(f"🚀 Render PostgreSQL configured")
            
            # ✅ ONLY set pooling for PostgreSQL, NOT for SQLite
            app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
                'pool_recycle': 300,
                'pool_pre_ping': True,
                'pool_size': 5,
                'max_overflow': 10
            }
        else:
            # Using SQLite (for local testing with RENDER env)
            print("⚠️ Using SQLite with RENDER env (local testing)")
            # ❌ DON'T set pooling options for SQLite
            app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {}
        
        # Disable Redis features
        app.config['CELERY_BROKER_URL'] = None
        app.config['CELERY_RESULT_BACKEND'] = None
        
        # Use memory-based rate limiting
        app.config['RATELIMIT_STORAGE_URL'] = 'memory://'
        app.config['CACHE_TYPE'] = 'SimpleCache'
        
        # Warn about file uploads
        print("⚠️ WARNING: File uploads will be lost on server restart!")
        print("💡 For production, use AWS S3, Cloudinary, or similar service")

class DevelopmentConfig(Config):
    DEBUG = True
    ENV = "development"
    
    # Development-specific email settings
    MAIL_SUPPRESS_SEND = _bool('MAIL_SUPPRESS_SEND', False)
    MAIL_DEBUG = _bool('MAIL_DEBUG', True)
    
    # Development Live Stream Settings
    ENABLE_LIVE_CHAT = True
    LOG_CHAT_MESSAGES = True
    ENABLE_CONTENT_FILTER = False  # Disable in dev for easier testing
    MAX_CONNECTION_RETRIES = 3  # Faster retries in development

class TestingConfig(Config):
    TESTING = True
    DEBUG = True
    ENV = "testing"
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    
    # Testing email settings
    MAIL_SUPPRESS_SEND = True
    MAIL_BACKEND = 'django.core.mail.backends.locmem.EmailBackend'
    
    # Testing Live Stream Settings
    ENABLE_LIVE_CHAT = True
    WEBSOCKET_URL = "http://testserver:5000"
    LOG_CHAT_MESSAGES = True
    MAX_MESSAGES_PER_MINUTE = 100  # Higher limit for testing

class ProductionConfig(Config):
    DEBUG = False
    ENV = "production"
    
    # Production email settings
    MAIL_DEBUG = _bool('MAIL_DEBUG', False)
    
    # Production Live Stream Settings
    ENABLE_LIVE_CHAT = True
    LOG_CHAT_MESSAGES = False
    REQUIRE_EMAIL_VERIFICATION = True
    ENABLE_CONTENT_FILTER = True
    ENABLE_AUTO_MODERATION = True

class StagingConfig(Config):
    DEBUG = _bool("DEBUG", True)
    ENV = "staging"
    
    # Staging email settings
    MAIL_SUPPRESS_SEND = _bool('MAIL_SUPPRESS_SEND', False)
    
    # Staging Live Stream Settings
    ENABLE_LIVE_CHAT = True
    LOG_CHAT_MESSAGES = True
    ENABLE_CONTENT_FILTER = True
    REQUIRE_EMAIL_VERIFICATION = False  # Disable in staging for testing

config = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
    "staging": StagingConfig,
    "render": RenderConfig,
    "default": DevelopmentConfig,
}
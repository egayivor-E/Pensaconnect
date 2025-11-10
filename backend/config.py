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
    # Docker sets this special file inside containers
    return os.path.exists("/.dockerenv")


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY") or os.urandom(32)
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Detect environment and select DB URL
    if running_in_docker():
        SQLALCHEMY_DATABASE_URI = os.getenv("DOCKER_DATABASE_URL")
        CELERY_BROKER_URL = os.getenv("DOCKER_CELERY_BROKER_URL", "redis://redis:6379/0")
        CELERY_RESULT_BACKEND = os.getenv("DOCKER_CELERY_RESULT_BACKEND", "redis://redis:6379/0")
    else:
        SQLALCHEMY_DATABASE_URI = (
            os.getenv("DEV_DATABASE_URL")
            or os.getenv("DATABASE_URL")
            or f"sqlite:///{basedir / 'app.db'}"
        )
        CELERY_BROKER_URL = os.getenv("DEV_CELERY_BROKER_URL", "redis://localhost:6379/0")
        CELERY_RESULT_BACKEND = os.getenv("DEV_CELERY_RESULT_BACKEND", "redis://localhost:6379/0")

    # CORS
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")

    # JWT
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY") or os.getenv("SECRET_KEY") or "change-me"
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=int(os.getenv("JWT_EXPIRES_HOURS", "24")))

    # Cache / Rate limit
    RATELIMIT_ENABLED = _bool("RATELIMIT_ENABLED", True)
    RATELIMIT_STORAGE_URL = os.getenv("RATELIMIT_STORAGE_URL", "memory://")
    CACHE_TYPE = os.getenv("CACHE_TYPE", "SimpleCache")
    CACHE_DEFAULT_TIMEOUT = int(os.getenv("CACHE_DEFAULT_TIMEOUT", "300"))

    # Upload settings (NEW)
    UPLOAD_FOLDER = os.getenv("UPLOAD_FOLDER", os.path.join(basedir, "uploads"))
    MAX_CONTENT_LENGTH = int(os.getenv("MAX_CONTENT_LENGTH", 2 * 1024 * 1024))  # 2MB

    # Ensure upload directory exists at runtime
    os.makedirs(UPLOAD_FOLDER, exist_ok=True)

    DEBUG = _bool("DEBUG", False)
    TESTING = False
    ENV = os.getenv("FLASK_ENV", "production")
    PORT = int(os.getenv("PORT", "5000"))


class DevelopmentConfig(Config):
    DEBUG = True
    ENV = "development"


class TestingConfig(Config):
    TESTING = True
    DEBUG = True
    ENV = "testing"
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"


class ProductionConfig(Config):
    DEBUG = False
    ENV = "production"


class StagingConfig(Config):
    DEBUG = _bool("DEBUG", True)
    ENV = "staging"


config = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
    "staging": StagingConfig,
    "default": DevelopmentConfig,
}

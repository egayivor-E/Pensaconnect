import logging
from flask import Blueprint

logger = logging.getLogger(__name__)

# Parent blueprint for API v1; child blueprints contribute their own segments
api_v1 = Blueprint("api_v1", __name__, url_prefix="/api/v1")

# Import child blueprints (relative imports within the package)
from .v1.auth import auth_bp
from .v1.users import users_bp
from .v1.posts import posts_bp
from .v1.prayers import prayers_bp
from .v1.events import events_bp
from .v1.comments import comments_bp
from .v1.reactions import reactions_bp
from .v1.notifications import notifications_bp
from .v1.donations import donations_bp
from .v1.resources import resources_bp
from .v1.home import home_bp
from .v1.activities import activities_bp
from .v1.live import live_bp
from .v1.messages import messages_bp
from .v1.bible import bible_bp
from .v1.forums import forums_bp
from .v1.testimonies import testimonies_bp
from .v1.group_chats import group_chats_bp



# Register them under /api/v1
api_v1.register_blueprint(auth_bp)
api_v1.register_blueprint(users_bp)
api_v1.register_blueprint(posts_bp)
api_v1.register_blueprint(prayers_bp)
api_v1.register_blueprint(events_bp)
api_v1.register_blueprint(comments_bp)
api_v1.register_blueprint(reactions_bp)
api_v1.register_blueprint(notifications_bp)
api_v1.register_blueprint(donations_bp)
api_v1.register_blueprint(resources_bp)
api_v1.register_blueprint(home_bp)
api_v1.register_blueprint(activities_bp)
api_v1.register_blueprint(live_bp)
api_v1.register_blueprint(messages_bp)
api_v1.register_blueprint(bible_bp)
api_v1.register_blueprint(forums_bp)
api_v1.register_blueprint(testimonies_bp)
api_v1.register_blueprint(group_chats_bp)

#def register_api_v1(app):
#    """Register the API v1 blueprint with the Flask app."""
#    try:
#        app.register_blueprint(api_v1)
#        logger.info("✅ API v1 blueprint registered successfully")
#    except Exception as e:
#        logger.error(f"❌ Failed to register API v1 blueprint: {e}")
#        raise

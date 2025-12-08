import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from flask import send_from_directory # Import necessary for serving static files

# Load environment variables from .env file
load_dotenv()

# Detect Render environment
RENDER = 'RENDER' in os.environ or os.environ.get('RENDER_EXTERNAL_URL') is not None
if RENDER:
    os.environ['FLASK_ENV'] = 'production'
    # FIX: Set RUN_FRONTEND to 'true' so the server attempts to serve the built Flutter app.
    os.environ['RUN_FRONTEND'] = 'true'
    print("🚀 RENDER DETECTED: Using production settings")

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from backend import create_app, db, get_socketio


# --- NEW FUNCTION: Frontend Serving Logic ---
def add_frontend_routes(app):
    """
    Adds routes to serve the built Flutter web app (index.html and assets).
    This logic only runs if the Flutter build was successful.
    """
    # Assuming run.py is in the root directory and Flutter is in './frontend'
    BASE_DIR = os.path.abspath(os.path.dirname(__file__)) 
    FRONTEND_WEB_DIR = os.path.join(BASE_DIR, 'frontend', 'build', 'web')
    
    # CRITICAL CHECK: Ensure the built files exist
    INDEX_HTML_PATH = os.path.join(FRONTEND_WEB_DIR, 'index.html')
    if not os.path.exists(INDEX_HTML_PATH):
        print(f"⚠️ Flutter Frontend build files not found at: {FRONTEND_WEB_DIR}")
        print("   Falling back to simple API-only serving.")
        # If frontend is missing, we skip adding frontend routes.
        # This prevents the whole app from crashing if the build step failed.
        return 

    print(f"✅ Serving frontend from: {FRONTEND_WEB_DIR}")

    # 1. Main Route: Serves index.html for the root URL
    @app.route('/', methods=['GET'])
    def serve_index():
        return send_from_directory(FRONTEND_WEB_DIR, 'index.html')

    # 2. Catch-all Route: Serves static assets and handles Flutter deep linking
    @app.route('/<path:path>', methods=['GET'])
    def serve_static(path):
        # 1. Try to serve the specific static file (e.g., app.js, fonts, images)
        if os.path.exists(os.path.join(FRONTEND_WEB_DIR, path)):
            return send_from_directory(FRONTEND_WEB_DIR, path)
        
        # 2. Fallback: For Flutter deep links (e.g., /profile), serve index.html
        # This allows Flutter's internal routing to take over.
        return send_from_directory(FRONTEND_WEB_DIR, 'index.html')

# --- END OF NEW FUNCTION ---


def ensure_instance():
    Path("instance").mkdir(exist_ok=True)

def setup_database():
    """Setup database and create admin user"""
    print("🔄 Setting up database...")
    
    try:
        # Create tables
        db.create_all()
        print("✅ Tables created")
        
        # Import models
        from backend.models import User, Role
        from sqlalchemy import or_
        
        # 1. Create admin role if it doesn't exist
        admin_role = Role.query.filter_by(name='admin').first()
        if not admin_role:
            admin_role = Role(name='admin')
            db.session.add(admin_role)
            db.session.commit()
            print("✅ Admin role created")
        else:
            print("✅ Admin role exists")
        
        # 2. Create admin user (FIXED LOGIC)
        admin_email = 'gayivore@gmail.com'
        admin_username = 'admin'
        
        # Check if a user with the target username OR email already exists.
        admin = User.query.filter(
            or_(
                User.username == admin_username,
                User.email == admin_email
            )
        ).first()
        
        if not admin:
            # Create admin user only if NO user was found with that username or email
            admin = User(
                username=admin_username,
                email=admin_email,
                first_name='Admin',
                last_name='User',
                email_verified=True,
                status='active'
            )
            admin.set_password('JesusSave123!')
            
            # Add admin role to user
            admin.roles.append(admin_role)
            
            db.session.add(admin)
            db.session.commit()
            print(f"✅ Admin user created: {admin_email}")
            print("   Password: JesusSave123!")
        else:
            # User exists, ensure they have the admin role
            if admin_role not in admin.roles:
                admin.roles.append(admin_role)
                db.session.commit()
                print(f"✅ Added admin role to existing user: {admin.email}")
            else:
                print(f"✅ Admin already exists with admin role: {admin.email}")
            
    except Exception as e:
        print(f"⚠️ Could not create admin: {e}")
        import traceback
        traceback.print_exc()

def run_app():
    """Main application runner"""
    print("=" * 60)
    print("🚀 PensaConnect Starting")
    print("=" * 60)
    
    ensure_instance()
    
    # Create app with correct config
    if RENDER:
        print("🎯 Using Render configuration")
        app = create_app('render')
    else:
        env = os.getenv('FLASK_ENV', 'development')
        print(f"🎯 Using {env} configuration")
        app = create_app(env)
    
    # --- FIX: Add Frontend Serving Routes First ---
    # This must run if RUN_FRONTEND is true (which it is on Render now)
    if os.getenv('RUN_FRONTEND', 'true') == 'true':
        add_frontend_routes(app)
    # ---------------------------------------------
    
    # Add health endpoint (REQUIRED for Render)
    # This specific route takes precedence over the generic '/' from frontend routes.
    @app.route('/health')
    def health():
        return {"status": "healthy", "service": "PensaConnect"}, 200
    
    # ORIGINAL ROOT ROUTE: 
    # The original API root route is REMOVED/OVERRIDDEN 
    # by the frontend route added in add_frontend_routes. 
    # If the frontend files are missing, the app will serve nothing at '/', 
    # but the API endpoints will still work.

    # Setup database
    with app.app_context():
        setup_database()
    
    # Get SocketIO
    socketio = get_socketio()
    if not socketio:
        raise RuntimeError("SocketIO not initialized")
    
    # Run the app
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', '5000'))
    
    print(f"📍 Server: {host}:{port}")
    print(f"🌍 Environment: {app.config.get('ENV', 'unknown')}")
    print(f"🔧 Debug: {app.config.get('DEBUG', False)}")
    print("✅ Starting server...")
    
    # Production settings for Render
    if RENDER:
        socketio.run(
            app,
            host=host,
            port=port,
            debug=False,
            use_reloader=False,
            allow_unsafe_werkzeug=False,
            log_output=True
        )
    else:
        # Development
        socketio.run(
            app,
            host=host,
            port=port,
            debug=True,
            use_reloader=True,
            allow_unsafe_werkzeug=True
        )

if __name__ == '__main__':
    run_app()
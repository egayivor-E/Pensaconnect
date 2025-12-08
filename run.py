import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load environment
load_dotenv()

# Detect Render
RENDER = 'RENDER' in os.environ or os.environ.get('RENDER_EXTERNAL_URL') is not None
if RENDER:
    os.environ['FLASK_ENV'] = 'production'
    os.environ['RUN_FRONTEND'] = 'false'
    print("🚀 RENDER DETECTED: Using production settings")

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from backend import create_app, db, get_socketio

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
        from sqlalchemy import or_ # <-- Import 'or_' for conditional filtering
        
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
        # This prevents the IntegrityError if the 'admin' username exists 
        # but is tied to an old/different email address.
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
    
    # Add health endpoint (REQUIRED for Render)
    @app.route('/health')
    def health():
        return {"status": "healthy", "service": "PensaConnect"}, 200
    
    @app.route('/')
    def index():
        return {"message": "PensaConnect API", "docs": "/docs"}, 200
    
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
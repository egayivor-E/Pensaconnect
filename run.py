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
        # Show database info
        db_url = db.engine.url
        print(f"🔍 Database: {db_url}")
        
        # Create all tables
        db.create_all()
        print("✅ Tables created")
        
        # Create admin user
        from backend.models import User
        
        admin_email = 'gayivore@gmail.com'
        admin = User.query.filter_by(email=admin_email).first()
        
        if not admin:
            admin = User(
                username='admin',
                email=admin_email,
                first_name='Admin',
                last_name='User',
                is_admin=True,
                email_verified=True,
                status='active'
            )
            admin.set_password('Jesus@save')
            db.session.add(admin)
            db.session.commit()
            print(f"✅ Admin created: {admin_email}")
        else:
            print(f"✅ Admin exists: {admin_email}")
            
    except Exception as e:
        print(f"⚠️ Database setup error: {e}")
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
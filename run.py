import os
import sys
import subprocess
import threading
from time import sleep
from pathlib import Path
from dotenv import load_dotenv

# ========== RENDER-SPECIFIC SETTINGS ==========
# Set RENDER environment variable early
os.environ['RENDER'] = 'true' if 'RENDER' in os.environ else 'false'

# Load .env for local development
load_dotenv()

# Override defaults for Render
if os.environ.get('RENDER') == 'true':
    os.environ['FLASK_ENV'] = 'production'
    os.environ['RUN_FRONTEND'] = 'false'
    print("🚀 Running on Render platform")
    
    # Fix PostgreSQL URL for SQLAlchemy if needed
    db_url = os.environ.get('DATABASE_URL')
    if db_url and db_url.startswith('postgres://'):
        os.environ['DATABASE_URL'] = db_url.replace('postgres://', 'postgresql://', 1)
        print("✅ Fixed PostgreSQL URL for SQLAlchemy")

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

# ✅ UPDATE IMPORTS FOR WEBSOCKET SUPPORT
from backend import create_app, db, get_socketio, run_app
from backend.config import config

# Get environment variables
FLASK_ENV = os.getenv("FLASK_ENV", "development").lower()
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "5000"))
RUN_FRONTEND = os.getenv("RUN_FRONTEND", "false").lower() in ("1", "true", "yes")
RENDER = os.getenv("RENDER", "false").lower() == "true"

# On Render, force no frontend
if RENDER:
    RUN_FRONTEND = False

print("=" * 60)
print(f"🚀 PensaConnect Server Starting...")
print(f"🌍 Environment: {FLASK_ENV}")
print(f"📍 Host: {HOST}:{PORT}")
print(f"🖥️  Run Frontend: {RUN_FRONTEND}")
print(f"🚀 On Render: {RENDER}")
print("=" * 60)

def ensure_instance():
    Path("instance").mkdir(exist_ok=True)

def migrate_or_create():
    """Initialize database - called within app context"""
    try:
        if FLASK_ENV in ["production", "staging"]:
            subprocess.run(["flask", "db", "upgrade"], check=True)
            print("✅ Applied migrations")
        else:
            db.create_all()
            print("✅ Ensured tables (dev/testing)")
        
        # ====== ADD ADMIN CREATION ======
        try:
            from backend.models import User
            
            # Check if admin already exists
            admin_exists = User.query.filter_by(email='gayivore@gmail.com').first()
            
            if not admin_exists:
                admin = User(
                    username='admin',
                    email='gayivore@gmail.com',
                    first_name='Admin',
                    last_name='User',
                    is_admin=True,
                    email_verified=True,
                    status='active'
                )
                admin.set_password('Admin123!')
                db.session.add(admin)
                db.session.commit()
                print("✅ Admin user created!")
                print("   Email: admin@pensaconnect.com")
                print("   Password: Admin123!")
            else:
                print(f"ℹ️ Admin already exists (ID: {admin_exists.id})")
                
        except Exception as admin_error:
            print(f"⚠️ Could not create admin user: {admin_error}")
        # ====== END ADMIN CREATION ======
            
    except Exception as e:
        print(f"❌ DB setup issue: {e}")

def run_backend():
    """Run backend with WebSocket support - OPTIMIZED FOR RENDER"""
    ensure_instance()
    
    print(f"🚀 Starting backend in {FLASK_ENV} mode")
    print(f"📍 Backend URL: http://{HOST}:{PORT}")
    
    if RENDER:
        print("🎯 Running on Render - WebSocket optimized")
    
    # ✅ Use RenderConfig from your config
    app = create_app('render' if RENDER else FLASK_ENV)
    socketio = get_socketio()
    
    if socketio is None:
        raise RuntimeError("❌ Socket.IO not initialized properly")
    
    # Initialize database within app context
    with app.app_context():
        migrate_or_create()  # This creates admin too!
    
    print("✅ Starting Socket.IO server...")
    
    # ✅ RENDER-SPECIFIC CONFIGURATION
    if RENDER or FLASK_ENV == "production":
        # Optimized for Render/production
        socketio.run(
            app, 
            debug=False, 
            host=HOST, 
            port=PORT, 
            use_reloader=False,
            allow_unsafe_werkzeug=False,
            log_output=True,  # Keep True to see logs in Render
            ping_timeout=60,
            ping_interval=25
        )
    else:
        # Development mode
        socketio.run(
            app, 
            debug=True, 
            host=HOST, 
            port=PORT, 
            use_reloader=True,
            allow_unsafe_werkzeug=True,
            log_output=True
        )

def check_dependencies():
    """Check if required dependencies are available"""
    print("🔍 Checking dependencies...")
    
    try:
        import flask_socketio
        print("✅ flask-socketio available")
    except ImportError:
        print("❌ flask-socketio not installed")
        return False
        
    if RENDER:
        print("✅ Running on Render - skipping Flutter check")
        return True
    
    if RUN_FRONTEND:
        try:
            result = subprocess.run(["flutter", "--version"], capture_output=True, text=True)
            if result.returncode == 0:
                print("✅ Flutter available")
            else:
                print("❌ Flutter not working properly")
                return False
        except FileNotFoundError:
            print("❌ Flutter not found in PATH")
            return False
    
    return True

if __name__ == "__main__":
    # Check dependencies first
    if not check_dependencies():
        print("❌ Missing dependencies")
        sys.exit(1)
    
    # On Render, always run backend only
    if RENDER:
        print("🔧 Starting backend only (Render deployment)...")
        run_backend()
    elif RUN_FRONTEND:
        print("🔧 Starting both backend and frontend...")
        backend_thread = threading.Thread(target=run_backend, daemon=False)
        backend_thread.start()
        sleep(8)
        # Frontend code would go here, but disabled on Render
        print("⚠️ Frontend disabled for this deployment")
        # Keep running
        try:
            while True:
                sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Shutting down...")
    else:
        print("🔧 Starting backend only...")
        run_backend()
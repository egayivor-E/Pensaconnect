import os
import sys
import subprocess
import threading
from time import sleep
from pathlib import Path
from dotenv import load_dotenv

# Load .env
load_dotenv()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

# ✅ UPDATE IMPORTS FOR WEBSOCKET SUPPORT
from backend import create_app, db, get_socketio, run_app
from backend.config import config

FLASK_ENV = os.getenv("FLASK_ENV", "development").lower()
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "5000"))
RUN_FRONTEND = os.getenv("RUN_FRONTEND", "false").lower() in ("1", "true", "yes")

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
    except Exception as e:
        print(f"❌ DB setup issue: {e}")

def run_backend():
    """Run backend with WebSocket support - FIXED VERSION"""
    ensure_instance()
    
    print(f"🚀 Starting backend in {FLASK_ENV} mode")
    print(f"📍 Backend URL: http://{HOST}:{PORT}")
    print(f"🔌 WebSocket URL: ws://{HOST}:{PORT}/socket.io")
    print(f"📚 API Docs: http://{HOST}:{PORT}/docs/swagger-ui")
    print(f"❤️  Health Check: http://{HOST}:{PORT}/health")
    print(f"🔍 WebSocket Health: http://{HOST}:{PORT}/ws-health")
    
    # ✅ FIX: Use manual startup with proper WebSocket configuration
    app = create_app(FLASK_ENV)
    socketio = get_socketio()
    
    if socketio is None:
        raise RuntimeError("❌ Socket.IO not initialized properly")
    
    # Initialize database within app context
    with app.app_context():
        migrate_or_create()
    
    print("✅ Starting Socket.IO server...")
    
    # ✅ FIX: Environment-specific configuration
    if FLASK_ENV == "production":
        socketio.run(
            app, 
            debug=False, 
            host=HOST, 
            port=PORT, 
            use_reloader=False,
            allow_unsafe_werkzeug=False,
            log_output=False
        )
    else:
        # Development mode with better WebSocket support
        socketio.run(
            app, 
            debug=True, 
            host=HOST, 
            port=PORT, 
            use_reloader=True,
            allow_unsafe_werkzeug=True,
            log_output=True
        )

def run_frontend():
    """Run Flutter frontend"""
    try:
        sleep(5)  # ✅ INCREASED: Give backend more time to start
        print("🎨 Starting Flutter frontend...")
        
        # Check if frontend directory exists
        frontend_dir = Path("frontend")
        if not frontend_dir.exists():
            print("❌ Frontend directory not found")
            return
            
        # Try to run Flutter
        print("🚀 Launching Flutter in Chrome...")
        result = subprocess.run(
            ["flutter", "run", "-d", "chrome", "--web-port=58672"], 
            cwd="frontend", 
            capture_output=True, 
            text=True
        )
        
        if result.returncode != 0:
            print(f"❌ Flutter run failed: {result.stderr}")
            print("💡 Make sure Flutter is installed and configured")
        else:
            print("✅ Flutter frontend started successfully")
            
    except FileNotFoundError:
        print("❌ Flutter not found. Please install Flutter SDK")
    except Exception as e:
        print(f"❌ Frontend start failed: {e}")

def check_dependencies():
    """Check if required dependencies are available"""
    print("🔍 Checking dependencies...")
    
    # Check Python dependencies
    try:
        import flask_socketio
        print("✅ flask-socketio available")
    except ImportError:
        print("❌ flask-socketio not installed. Run: pip install flask-socketio")
        return False
        
    try:
        import eventlet
        print("✅ eventlet available (optional)")
    except ImportError:
        print("⚠️  eventlet not installed (using threading mode)")
    
    # Check Flutter if needed
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

def test_websocket_connection():
    """Test if WebSocket server is responding"""
    import requests
    try:
        response = requests.get(f"http://{HOST}:{PORT}/ws-health", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ WebSocket server is running: {data}")
            return True
        else:
            print(f"❌ WebSocket health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to WebSocket server: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("🚀 PensaConnect Server Starting...")
    print("=" * 60)
    
    # Check dependencies first
    if not check_dependencies():
        print("❌ Missing dependencies. Please install required packages.")
        sys.exit(1)
    
    # Start the application
    if RUN_FRONTEND:
        print("🔧 Starting both backend and frontend...")
        
        # ✅ FIX: Start backend in a NON-daemon thread
        backend_thread = threading.Thread(target=run_backend, daemon=False)  # Changed to False
        backend_thread.start()
        
        # ✅ FIX: Wait for backend to be fully ready
        print("⏳ Waiting for backend to start...")
        sleep(8)  # Increased wait time for WebSocket initialization
        
        # Test WebSocket connection before starting frontend
        if test_websocket_connection():
            print("✅ WebSocket server ready, starting frontend...")
            run_frontend()
        else:
            print("❌ WebSocket server not ready. Frontend may not connect properly.")
            run_frontend()  # Still try to start frontend
    else:
        print("🔧 Starting backend only...")
        # Run backend in main thread (recommended for WebSocket)
        run_backend()
    
    # Keep the main thread alive
    try:
        while True:
            sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Shutting down PensaConnect...")
        print("👋 Thank you for using PensaConnect!")
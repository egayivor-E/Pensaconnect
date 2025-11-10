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
from backend import create_app, db, get_socketio
from backend.config import config

FLASK_ENV = os.getenv("FLASK_ENV", "development").lower()
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "5000"))
RUN_FRONTEND = os.getenv("RUN_FRONTEND", "false").lower() in ("1", "true", "yes")

def ensure_instance():
    Path("instance").mkdir(exist_ok=True)

def migrate_or_create(app):
    with app.app_context():
        try:
            if FLASK_ENV in ["production", "staging"]:
                subprocess.run(["flask", "db", "upgrade"], check=True)
                print("Applied migrations")
            else:
                db.create_all()
                print("Ensured tables (dev/testing)")
        except Exception as e:
            print(f"DB setup issue: {e}")

def run_backend():
    ensure_instance()
    app = create_app(config.get(FLASK_ENV, config["default"]))
    socketio = get_socketio()  # ✅ GET SOCKETIO INSTANCE
    
    print(f"🚀 Starting backend in {FLASK_ENV} mode")
    print(f"📍 Backend URL: http://{HOST}:{PORT}")
    print(f"🔌 WebSocket URL: ws://{HOST}:{PORT}")
    print(f"📚 API Docs: http://{HOST}:{PORT}/docs/swagger-ui")
    
    migrate_or_create(app)
    
    # ✅ USE SOCKETIO.RUN() INSTEAD OF APP.RUN()
    socketio.run(
        app, 
        debug=(FLASK_ENV == "development"), 
        host=HOST, 
        port=PORT, 
        use_reloader=False,
        allow_unsafe_werkzeug=True
    )

def run_frontend():
    try:
        sleep(2)  # Give backend time to start
        print("🎨 Starting Flutter frontend...")
        subprocess.run(["flutter", "run", "-d", "chrome"], cwd="frontend", check=True)
    except Exception as e:
        print(f"❌ Frontend start failed: {e}")
        print("💡 Make sure Flutter is installed and frontend directory exists")

if __name__ == "__main__":
    print("=" * 50)
    print("🚀 PensaConnect Server Starting...")
    print("=" * 50)
    
    # Start backend in main thread (SocketIO needs main thread)
    if RUN_FRONTEND:
        # If running frontend too, start backend in thread
        t = threading.Thread(target=run_backend, daemon=True)
        t.start()
        run_frontend()
    else:
        # If only backend, run in main thread
        run_backend()
    
    try:
        while True:
            sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Shutting down...")
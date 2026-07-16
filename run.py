# ✅ MUST be the very first thing that runs, before any other imports.
# Flask-SocketIO is configured with async_mode='gevent' (see backend/__init__.py),
# which requires gevent's cooperative greenlets to be patched into the standard
# library (socket, ssl, threading, etc.) before anything else — including the
# DB driver, requests, or Flask itself — gets a reference to the un-patched
# versions. Without this, gevent's WSGI server can't yield during blocking I/O,
# so one slow request (e.g. a DB query or an open websocket) blocks every other
# connection on the same worker, which is what caused requests like
# GET /socket.io/... to hang for 100+ seconds and then fail with status 000.
from gevent import monkey
monkey.patch_all()

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from flask import send_from_directory

# Load environment variables from .env file
load_dotenv()

# Detect Render environment
RENDER = 'RENDER' in os.environ or os.environ.get('RENDER_EXTERNAL_URL') is not None
if RENDER:
    os.environ['FLASK_ENV'] = 'production'
    os.environ['RUN_FRONTEND'] = 'true'
    print("🚀 RENDER DETECTED: Using production settings")

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from backend import create_app, db, get_socketio


# --- FIXED: Frontend Serving Logic ---
def add_frontend_routes(app):
    """
    Adds routes to serve the built Flutter web app.
    Uses multiple fallback paths to locate the build files.
    """
    print("🔍 Looking for Flutter frontend build...")
    
    # Try multiple possible locations for the Flutter build
    possible_paths = []
    
    # Get base directory where this script is located
    BASE_DIR = os.path.abspath(os.path.dirname(__file__))
    print(f"📁 Script directory: {BASE_DIR}")
    print(f"📁 Current working directory: {os.getcwd()}")
    
    # Common locations to check
    possible_paths = [
        # 1. Relative from script location
        os.path.join(BASE_DIR, 'frontend', 'build', 'web'),
        # 2. Relative from parent directory
        os.path.join(os.path.dirname(BASE_DIR), 'frontend', 'build', 'web'),
        # 3. Absolute path for Render
        '/opt/render/project/src/frontend/build/web',
        # 4. Current working directory relative
        os.path.join(os.getcwd(), 'frontend', 'build', 'web'),
        # 5. If script is in subdirectory
        os.path.join(BASE_DIR, '..', 'frontend', 'build', 'web'),
    ]
    
    FRONTEND_WEB_DIR = None
    for i, path in enumerate(possible_paths):
        index_path = os.path.join(path, 'index.html')
        if os.path.exists(index_path):
            FRONTEND_WEB_DIR = path
            print(f"✅ Found Flutter build at option {i+1}: {path}")
            break
    
    if not FRONTEND_WEB_DIR:
        print("❌ Flutter frontend build NOT FOUND in any location!")
        print("   Checked these locations:")
        for i, path in enumerate(possible_paths):
            exists = os.path.exists(path)
            print(f"   {i+1}. {path} - {'EXISTS' if exists else 'NOT FOUND'}")
            if exists:
                print(f"      Contents: {os.listdir(path)[:5]}...")
        
        # Create a fallback route that shows a helpful message
        @app.route('/')
        def fallback_index():
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <title>PensaConnect - Setup Required</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 40px; }
                    .container { max-width: 800px; margin: 0 auto; }
                    .alert { background: #fff3cd; border: 1px solid #ffeaa7; padding: 20px; border-radius: 5px; }
                    .success { background: #d4edda; border: 1px solid #c3e6cb; }
                    code { background: #f8f9fa; padding: 2px 5px; border-radius: 3px; }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>PensaConnect</h1>
                    <div class="alert">
                        <h3>⚠️ Frontend Build Not Found</h3>
                        <p>The Flutter frontend build files could not be found.</p>
                        <p>This usually means:</p>
                        <ul>
                            <li>The Flutter build failed during deployment</li>
                            <li>The build files are in a different location than expected</li>
                            <li>You need to run: <code>cd frontend && flutter build web --release --no-tree-shake-icons</code></li>
                        </ul>
                    </div>
                    
                    <div class="alert success">
                        <h3>✅ Backend API is Running</h3>
                        <p>Your Flask backend is working correctly!</p>
                        <ul>
                            <li><a href="/api/v1">API Endpoints</a></li>
                            <li><a href="/admin">Admin Panel</a></li>
                            <li><a href="/health">Health Check</a></li>
                        </ul>
                    </div>
                    
                    <h3>Debug Information:</h3>
                    <pre id="debug"></pre>
                </div>
                
                <script>
                    // Show debug info
                    const debugInfo = {
                        scriptDir: window.location.origin + '/debug/paths',
                        checkedPaths: """ + str(possible_paths) + """,
                        renderEnv: """ + str(RENDER) + """
                    };
                    document.getElementById('debug').textContent = JSON.stringify(debugInfo, null, 2);
                </script>
            </body>
            </html>
            """, 200
        print("✅ Created fallback route for missing frontend")
        return
    
    print(f"✅ Serving frontend from: {FRONTEND_WEB_DIR}")
    
    # List ALL files for debugging
    try:
        print("📄 Listing ALL files in build directory:")
        for root, dirs, files in os.walk(FRONTEND_WEB_DIR):
            level = root.replace(FRONTEND_WEB_DIR, '').count(os.sep)
            indent = ' ' * 2 * level
            print(f"{indent}{os.path.basename(root)}/")
            subindent = ' ' * 2 * (level + 1)
            for file in files[:10]:  # First 10 files per directory
                print(f"{subindent}{file}")
    except Exception as e:
        print(f"⚠️ Could not list files: {e}")

    # 1. Main Route: Serves index.html for the root URL
    @app.route('/', methods=['GET'])
    def serve_index():
        print("🌐 Serving index.html for /")
        return send_from_directory(FRONTEND_WEB_DIR, 'index.html')

    # 2. Catch-all Route: Serves static assets and handles Flutter deep linking
    @app.route('/<path:path>', methods=['GET'])
    def serve_static(path):
        print(f"🔍 Request for: {path}")
        
        # Build the full path
        full_path = os.path.join(FRONTEND_WEB_DIR, path)
        
        # Check if file exists and is a file (not directory)
        if os.path.isfile(full_path):
            print(f"✅ Serving static file: {path}")
            return send_from_directory(FRONTEND_WEB_DIR, path)
        else:
            print(f"⚠️ File not found, serving index.html for deep link: {path}")
            return send_from_directory(FRONTEND_WEB_DIR, 'index.html')


# --- END OF FIXED FUNCTION ---


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
        
        # 2. Create admin user
        # ✅ FIXED: no more hardcoded email/password baked into source
        # control. Both are read from the environment now; if
        # ADMIN_PASSWORD isn't set, a random one-time password is
        # generated and printed to the deploy log ONCE at creation time
        # (never re-printed or persisted anywhere) instead of every
        # instance of this app shipping with the same known credentials.
        admin_email = os.getenv('ADMIN_EMAIL', 'admin@pensaconnect.local')
        admin_username = os.getenv('ADMIN_USERNAME', 'admin')
        admin_password = os.getenv('ADMIN_PASSWORD')
        generated_password = admin_password is None
        if generated_password:
            import secrets
            admin_password = secrets.token_urlsafe(12)
        
        # Check if a user with the target username OR email already exists.
        admin = User.query.filter(
            or_(
                User.username == admin_username,
                User.email == admin_email
            )
        ).first()
        
        if not admin:
            # Create admin user only if NO user was found
            admin = User(
                username=admin_username,
                email=admin_email,
                first_name='Admin',
                last_name='User',
                email_verified=True,
                status='active'
            )
            admin.set_password(admin_password)
            
            # Add admin role to user
            admin.roles.append(admin_role)
            
            db.session.add(admin)
            db.session.commit()
            print(f"✅ Admin user created: {admin_email}")
            if generated_password:
                print(f"   🔑 Generated one-time password: {admin_password}")
                print("   ⚠️  Save this now — it will not be shown again.")
                print("   💡 Set ADMIN_PASSWORD in your env to control it yourself instead.")
            else:
                print("   Password: (set via ADMIN_PASSWORD env var)")
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
    
    # --- CRITICAL: Register frontend routes BEFORE anything else ---
    if os.getenv('RUN_FRONTEND', 'true') == 'true':
        print("📱 Adding frontend routes...")
        add_frontend_routes(app)
    
    # --- Add Debug Route ---
    @app.route('/debug/paths')
    def debug_paths():
        """Debug endpoint to check file locations"""
        BASE_DIR = os.path.abspath(os.path.dirname(__file__))
        info = {
            'script_location': __file__,
            'script_directory': BASE_DIR,
            'current_working_directory': os.getcwd(),
            'is_render': RENDER,
            'frontend_paths_checked': [
                os.path.join(BASE_DIR, 'frontend', 'build', 'web'),
                os.path.join(os.path.dirname(BASE_DIR), 'frontend', 'build', 'web'),
                '/opt/render/project/src/frontend/build/web',
                os.path.join(os.getcwd(), 'frontend', 'build', 'web'),
                os.path.join(BASE_DIR, '..', 'frontend', 'build', 'web'),
            ],
            'directory_contents': {}
        }
        
        # Check what exists
        for path in info['frontend_paths_checked']:
            if os.path.exists(path):
                try:
                    info['directory_contents'][path] = os.listdir(path)
                except:
                    info['directory_contents'][path] = 'ACCESS DENIED'
        
        return info
    
    # --- Add health endpoint (REQUIRED for Render) ---
    @app.route('/health')
    def health():
        return {"status": "healthy", "service": "PensaConnect"}, 200
    
    # --- CRITICAL: Add custom 404 handler that serves Flutter for non-API routes ---
    @app.errorhandler(404)
    def handle_404(e):
        """Handle 404 errors: serve Flutter app for non-API routes"""
        from flask import request, send_from_directory, jsonify
        import os
        
        # Log the 404 attempt
        print(f"🔍 404 encountered for: {request.path}")
        
        # Define API routes that should return JSON 404
        api_routes = ('/api/', '/admin/', '/health', '/debug', '/static/')
        
        # Check if this is an API route
        is_api_route = any(request.path.startswith(route) for route in api_routes)
        
        if not is_api_route:
            # Try to serve Flutter frontend for non-API routes
            frontend_dir = '/opt/render/project/src/frontend/build/web'
            index_path = os.path.join(frontend_dir, 'index.html')
            
            if os.path.exists(index_path):
                print(f"📱 Serving Flutter app for: {request.path}")
                return send_from_directory(frontend_dir, 'index.html')
            else:
                print(f"⚠️ Flutter index.html not found at: {index_path}")
        
        # For API routes or if frontend not found, return JSON
        print(f"🔧 Returning JSON 404 for API route: {request.path}")
        return jsonify({
            'error': 'not_found',
            'message': 'The requested resource was not found',
            'path': request.path
        }), 404
    
    print("✅ Custom 404 handler registered for Flutter frontend")
    
    # --- Optional: Test route to verify frontend serving ---
    @app.route('/test-frontend')
    def test_frontend():
        """Test route to verify frontend is being served"""
        from flask import send_from_directory
        import os
        
        frontend_dir = '/opt/render/project/src/frontend/build/web'
        index_path = os.path.join(frontend_dir, 'index.html')
        
        if os.path.exists(index_path):
            return send_from_directory(frontend_dir, 'index.html')
        else:
            return f"Frontend not found at: {index_path}<br>Current dir: {os.getcwd()}"
    
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
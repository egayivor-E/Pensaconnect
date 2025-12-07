# backend/app.py

try:
    import sqlalchemy_fix  # Apply SQLAlchemy compatibility patch if needed
except ImportError as e:
    print(f"Note: SQLAlchemy patch not applied: {e}")

import os
from pathlib import Path
from flask import current_app, send_from_directory
from backend import create_app
from backend.config import config
# 🚨 CRITICAL IMPORT: Import cross_origin to solve statusCode: 0 error
from flask_cors import cross_origin # <-- ADD THIS LINE!

# Pick config dynamically (default: development)
env = os.getenv("FLASK_ENV", "development")
app = create_app(config[env])

# ✅ Serve uploaded files (publicly accessible)
@app.route("/uploads/<path:filename>")
def serve_uploads(filename):
    project_root = Path(app.root_path).parent
    upload_folder = os.path.join(project_root, "uploads")
    
    # Get the file response first
    response = send_from_directory(upload_folder, filename)
    
    # 🚨 CRITICAL FIX: Manually add the CORS header to the response
    # Using "*" is acceptable for development/localhost/known origins
    response.headers.add("Access-Control-Allow-Origin", "*")
    
    return response


@app.route('/uploads/<path:filename>')
def serve_uploaded_file(filename):
    """Serve uploaded files (avatars, audio, video, images)"""
    uploads_dir = os.path.join(current_app.root_path, 'uploads')
    return send_from_directory(uploads_dir, filename)

# Gunicorn / uWSGI entrypoint
if __name__ == "__main__":
    port = int(app.config.get("PORT", 5000))
    # Note: We use app.config["DEBUG"] directly for run()
    app.run(host="0.0.0.0", port=port, debug=app.config["DEBUG"])
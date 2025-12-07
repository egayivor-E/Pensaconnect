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


# Gunicorn / uWSGI entrypoint
if __name__ == "__main__":
    port = int(app.config.get("PORT", 5000))
    # Note: We use app.config["DEBUG"] directly for run()
    app.run(host="0.0.0.0", port=port, debug=app.config["DEBUG"])
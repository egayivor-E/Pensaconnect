# backend/api/v1/home.py
from flask import Blueprint, jsonify

home_bp = Blueprint("home", __name__, url_prefix="/home")

@home_bp.route("/", methods=["GET"])
def home():
    return jsonify({
        "status": "success",
        "message": "Welcome to PensaConnect API v1 🚀",
        "version": "v1",
        "endpoints": {
            "users": "/api/v1/users",
            "posts": "/api/v1/posts",
            "prayers": "/api/v1/prayers",
            "events": "/api/v1/events",
            "home": "/api/v1/home"
        }
    })
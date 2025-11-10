from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, current_user
from backend.models import User

admin_auth = Blueprint("admin_auth", __name__, url_prefix="/admin")

@admin_auth.route("/login", methods=["GET", "POST"])
def admin_login():
    """Simple admin login form for Flask-Admin access."""
    if current_user.is_authenticated and current_user.has_role("admin"):
        return redirect(url_for("admin.index"))

    if request.method == "POST":
        email = request.form.get("email")
        password = request.form.get("password")

        user = User.query.filter_by(email=email.lower()).first()
        if user and user.check_password(password) and user.has_role("admin"):
            login_user(user)
            flash("Welcome to the Admin Dashboard!", "success")
            return redirect(url_for("admin.index"))

        flash("Invalid credentials or insufficient permissions.", "error")

    return render_template("admin_login.html")

@admin_auth.route("/logout")
def admin_logout():
    """Logout admin users"""
    logout_user()
    flash("You have been logged out.", "info")
    return redirect(url_for("admin_auth.admin_login"))

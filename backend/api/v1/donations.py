from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.extensions import db
from .utils import success_response
from datetime import datetime
from sqlalchemy import or_

donations_bp = Blueprint("donations", __name__, url_prefix="/donations")

def get_donation_model():
    from backend.models import Donation
    return Donation

@donations_bp.route("/", methods=["GET"])
@jwt_required()
def list_donations():
    Donation = get_donation_model()
    user_id = get_jwt_identity()
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    donations = Donation.query.filter(
        or_(Donation.donor_id == user_id, Donation.recipient_id == user_id)
    ).order_by(Donation.created_at.desc()).paginate(page, per_page, error_out=False)
    return success_response([d.to_dict() for d in donations.items])

@donations_bp.route("/", methods=["POST"])
@jwt_required()
def create_donation():
    Donation = get_donation_model()
    user_id = get_jwt_identity()
    data = request.get_json()

    if not data.get("amount") or not data.get("currency"):
        return {"error": "amount and currency are required"}, 400

    donation = Donation(
        donor_id=user_id,
        recipient_id=data.get("recipient_id"),
        amount=data["amount"],
        currency=data["currency"],
        payment_method=data.get("payment_method"),
        transaction_id=data.get("transaction_id"),
        status=data.get("status", "pending"),
        purpose=data.get("purpose"),
        is_recurring=data.get("is_recurring", False),
        recurrence_frequency=data.get("recurrence_frequency"),
        created_at=datetime.utcnow()
    )

    db.session.add(donation)
    db.session.commit()
    return success_response(donation.to_dict(), "Donation created", 201)

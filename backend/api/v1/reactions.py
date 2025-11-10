from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Reaction
from backend.extensions import db
from .utils import success_response
from datetime import datetime

reactions_bp = Blueprint("reactions", __name__, url_prefix="/reactions")

@reactions_bp.route("/", methods=["GET"])
def list_reactions():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    reactions = Reaction.query.order_by(Reaction.created_at.desc()).paginate(page, per_page, error_out=False)
    return success_response([r.to_dict() for r in reactions.items])

@reactions_bp.route("/", methods=["POST"])
@jwt_required()
def add_reaction():
    user_id = get_jwt_identity()
    data = request.get_json()
    reaction = Reaction(
        user_id=user_id,
        post_id=data.get("post_id"),
        comment_id=data.get("comment_id"),
        reaction_type=data["reaction_type"],
        created_at=datetime.utcnow()
    )
    db.session.add(reaction)
    db.session.commit()
    return success_response(reaction.to_dict(), "Reaction added", 201)

@reactions_bp.route("/<int:reaction_id>", methods=["DELETE"])
@jwt_required()
def remove_reaction(reaction_id: int):
    reaction = Reaction.query.get_or_404(reaction_id)
    db.session.delete(reaction)
    db.session.commit()
    return success_response(message="Reaction removed")

from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Resource
from backend.extensions import db
from .utils import success_response
from datetime import datetime

resources_bp = Blueprint("resources", __name__, url_prefix="/resources")

@resources_bp.route("/", methods=["GET"])
def list_resources():
    page = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))
    resources = Resource.query.order_by(Resource.created_at.desc()).paginate(page, per_page, error_out=False)
    return success_response([r.to_dict() for r in resources.items])

@resources_bp.route("/<int:resource_id>", methods=["GET"])
def get_resource(resource_id: int):
    resource = Resource.query.get_or_404(resource_id)
    return success_response(resource.to_dict())

@resources_bp.route("/", methods=["POST"])
@jwt_required()
def create_resource():
    user_id = get_jwt_identity()
    data = request.get_json()
    resource = Resource(
        title=data["title"],
        description=data.get("description"),
        url=data["url"],
        user_id=user_id,
        created_at=datetime.utcnow()
    )
    db.session.add(resource)
    db.session.commit()
    return success_response(resource.to_dict(), "Resource created", 201)

@resources_bp.route("/<int:resource_id>", methods=["PATCH"])
@jwt_required()
def update_resource(resource_id: int):
    resource = Resource.query.get_or_404(resource_id)
    data = request.get_json()
    for key in ["title", "description", "url"]:
        if key in data:
            setattr(resource, key, data[key])
    resource.updated_at = datetime.utcnow()
    db.session.commit()
    return success_response(resource.to_dict(), "Resource updated")

@resources_bp.route("/<int:resource_id>", methods=["DELETE"])
@jwt_required()
def delete_resource(resource_id: int):
    resource = Resource.query.get_or_404(resource_id)
    db.session.delete(resource)
    db.session.commit()
    return success_response(message="Resource deleted")

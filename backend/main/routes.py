# routes.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from backend.models import Activity, db, Post, Comment, PrayerRequest, Event, Resource, User
from backend.models import PostCategory, PrayerStatus, EventType, ResourceType
from datetime import datetime, timezone
import json

# 🚨 CRITICAL CHANGE: Import the blueprint from the package's __init__.py
from . import auth_bp
from .utils import success_response, error_response # type: ignore


main_bp = Blueprint('main', __name__)

# -------------------------
# Helper Functions
# -------------------------
def json_response(data, status=200):
    """Standardized JSON response helper."""
    return jsonify(data), status

def validate_required_fields(data, required_fields):
    """Validate required fields in request payload."""
    missing = [field for field in required_fields if field not in data or not data[field]]
    if missing:
        return {"error": f"Missing required fields: {', '.join(missing)}"}
    return None

# -------------------------
# Posts Routes
# -------------------------
@main_bp.route('/posts', methods=['GET'])
def get_posts():
    try:
        category = request.args.get('category')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        query = Post.query.filter_by(is_active=True, is_approved=True)

        if category:
            try:
                post_category = PostCategory(category)
                query = query.filter_by(category=post_category)
            except ValueError:
                return json_response({"error": "Invalid category"}, 400)

        posts = query.order_by(Post.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return json_response({
            'posts': [{
                'id': post.id,
                'title': post.title,
                'content': post.content,
                'excerpt': post.excerpt,
                'category': post.category.value,
                'created_at': post.created_at.isoformat(),
                'updated_at': post.updated_at.isoformat(),
                'author': {
                    'id': post.author.id,
                    'username': post.author.username,
                    'profile_picture': post.author.profile_picture
                },
                'view_count': post.view_count,
                'comment_count': post.comments.count(),
                'featured_image': post.featured_image
            } for post in posts.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': posts.total,
                'pages': posts.pages
            }
        })
    except Exception as e:
        return json_response({"error": str(e)}, 500)

@main_bp.route('/posts', methods=['POST'])
@jwt_required()
def create_post():
    try:
        data = request.get_json()
        if not data:
            return json_response({"error": "Request body must be JSON"}, 400)

        current_user_id = get_jwt_identity()
        user = User.query.get(current_user_id)
        if not user:
            return json_response({"error": "User not found"}, 404)

        # Validate required fields
        error = validate_required_fields(data, ['title', 'content', 'category'])
        if error:
            return json_response(error, 400)

        # Validate category
        try:
            category = PostCategory(data['category'])
        except ValueError:
            return json_response({"error": "Invalid post category"}, 400)

        new_post = Post(
            title=data['title'].strip(),
            content=data['content'].strip(),
            category=category,
            user_id=current_user_id,
            excerpt=data.get('excerpt', '').strip()[:300],
            featured_image=data.get('featured_image'),
            media_assets=data.get('media_assets', [])
        )

        # Generate slug and calculate reading time
        new_post.generate_slug()
        new_post.calculate_reading_time()

        db.session.add(new_post)
        db.session.commit()

        return json_response({
            'message': 'Post created successfully',
            'post': {
                'id': new_post.id,
                'title': new_post.title,
                'slug': new_post.slug
            }
        }, 201)

    except Exception as e:
        db.session.rollback()
        return json_response({"error": f"Server error: {str(e)}"}, 500)

@main_bp.route('/posts/<int:post_id>', methods=['GET'])
def get_post(post_id):
    try:
        post = Post.query.filter_by(id=post_id, is_active=True, is_approved=True).first()
        if not post:
            return json_response({"error": "Post not found"}, 404)

        # Increment view count
        post.view_count += 1
        db.session.commit()

        return json_response({
            'post': {
                'id': post.id,
                'title': post.title,
                'content': post.content,
                'excerpt': post.excerpt,
                'category': post.category.value,
                'slug': post.slug,
                'created_at': post.created_at.isoformat(),
                'updated_at': post.updated_at.isoformat(),
                'author': {
                    'id': post.author.id,
                    'username': post.author.username,
                    'profile_picture': post.author.profile_picture
                },
                'view_count': post.view_count,
                'reading_time': post.reading_time,
                'featured_image': post.featured_image,
                'media_assets': post.media_assets
            }
        })
    except Exception as e:
        return json_response({"error": str(e)}, 500)

# -------------------------
# Prayer Requests Routes
# -------------------------
@main_bp.route('/prayer-requests', methods=['GET'])
def get_prayer_requests():
    try:
        status = request.args.get('status')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        query = PrayerRequest.query.filter_by(is_active=True, is_public=True)

        if status:
            try:
                prayer_status = PrayerStatus(status)
                query = query.filter_by(status=prayer_status)
            except ValueError:
                return json_response({"error": "Invalid status"}, 400)

        requests = query.order_by(PrayerRequest.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return json_response({
            'prayer_requests': [{
                'id': req.id,
                'title': req.title,
                'content': req.content,
                'status': req.status.value,
                'is_anonymous': req.is_anonymous,
                'prayer_count': req.prayer_count,
                'created_at': req.created_at.isoformat(),
                'user': None if req.is_anonymous else {
                    'id': req.user.id,
                    'username': req.user.username,
                    'profile_picture': req.user.profile_picture
                },
                'urgency_level': req.urgency_level
            } for req in requests.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': requests.total,
                'pages': requests.pages
            }
        })
    except Exception as e:
        return json_response({"error": str(e)}, 500)

@main_bp.route('/prayer-requests', methods=['POST'])
@jwt_required()
def create_prayer_request():
    try:
        data = request.get_json()
        if not data:
            return json_response({"error": "Request body must be JSON"}, 400)

        current_user_id = get_jwt_identity()
        user = User.query.get(current_user_id)
        if not user:
            return json_response({"error": "User not found"}, 404)

        error = validate_required_fields(data, ['title', 'content'])
        if error:
            return json_response(error, 400)

        new_request = PrayerRequest(
            title=data['title'].strip(),
            content=data['content'].strip(),
            is_anonymous=data.get('is_anonymous', False),
            is_public=data.get('is_public', True),
            allow_comments=data.get('allow_comments', True),
            allow_prayers=data.get('allow_prayers', True),
            urgency_level=min(max(data.get('urgency_level', 1), 5),  # Clamp between 1-5
            user_id=current_user_id
        ))

        db.session.add(new_request)
        db.session.commit()

        return json_response({
            'message': 'Prayer request submitted successfully',
            'prayer_request': {
                'id': new_request.id,
                'title': new_request.title
            }
        }, 201)

    except Exception as e:
        db.session.rollback()
        return json_response({"error": f"Server error: {str(e)}"}, 500)

# -------------------------
# Events Routes
# -------------------------
@main_bp.route('/events', methods=['GET'])
def get_events():
    try:
        event_type = request.args.get('type')
        upcoming = request.args.get('upcoming', 'true').lower() == 'true'
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        query = Event.query.filter_by(is_active=True)

        if event_type:
            try:
                event_type_enum = EventType(event_type)
                query = query.filter_by(event_type=event_type_enum)
            except ValueError:
                return json_response({"error": "Invalid event type"}, 400)

        if upcoming:
            query = query.filter(Event.start_time >= datetime.now(timezone.utc))

        events = query.order_by(Event.start_time.asc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return json_response({
            'events': [{
                'id': event.id,
                'title': event.title,
                'description': event.description,
                'event_type': event.event_type.value,
                'start_time': event.start_time.isoformat(),
                'end_time': event.end_time.isoformat(),
                'location': event.location,
                'is_virtual': event.is_virtual,
                'meeting_link': event.meeting_link,
                'cover_image': event.cover_image,
                'organizer': {
                    'id': event.organizer.id,
                    'username': event.organizer.username,
                    'profile_picture': event.organizer.profile_picture
                },
                'current_attendees': event.current_attendees,
                'max_attendees': event.max_attendees
            } for event in events.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': events.total,
                'pages': events.pages
            }
        })
    except Exception as e:
        return json_response({"error": str(e)}, 500)

@main_bp.route('/events', methods=['POST'])
@jwt_required()
def create_event():
    try:
        data = request.get_json()
        if not data:
            return json_response({"error": "Request body must be JSON"}, 400)

        current_user_id = get_jwt_identity()
        user = User.query.get(current_user_id)
        if not user:
            return json_response({"error": "User not found"}, 404)

        error = validate_required_fields(data, ['title', 'description', 'start_time', 'end_time', 'event_type'])
        if error:
            return json_response(error, 400)

        # Validate event type
        try:
            event_type = EventType(data['event_type'])
        except ValueError:
            return json_response({"error": "Invalid event type"}, 400)

        # Parse datetime strings
        try:
            start_time = datetime.fromisoformat(data['start_time'].replace('Z', '+00:00'))
            end_time = datetime.fromisoformat(data['end_time'].replace('Z', '+00:00'))
        except ValueError:
            return json_response({"error": "Invalid datetime format. Use ISO format."}, 400)

        if start_time >= end_time:
            return json_response({"error": "End time must be after start time"}, 400)

        new_event = Event(
            title=data['title'].strip(),
            description=data['description'].strip(),
            event_type=event_type,
            start_time=start_time,
            end_time=end_time,
            location=data.get('location'),
            is_virtual=data.get('is_virtual', False),
            meeting_link=data.get('meeting_link'),
            max_attendees=data.get('max_attendees'),
            cover_image=data.get('cover_image'),
            user_id=current_user_id
        )

        db.session.add(new_event)
        db.session.commit()

        return json_response({
            'message': 'Event created successfully',
            'event': {
                'id': new_event.id,
                'title': new_event.title
            }
        }, 201)

    except Exception as e:
        db.session.rollback()
        return json_response({"error": f"Server error: {str(e)}"}, 500)

# -------------------------
# Resources Routes
# -------------------------
@main_bp.route('/resources', methods=['GET'])
def get_resources():
    try:
        category = request.args.get('category')
        resource_type = request.args.get('type')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        query = Resource.query.filter_by(is_active=True)

        if category:
            query = query.filter_by(category=category)
        
        if resource_type:
            try:
                res_type = ResourceType(resource_type)
                query = query.filter_by(file_type=res_type)
            except ValueError:
                return json_response({"error": "Invalid resource type"}, 400)

        resources = query.order_by(Resource.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return json_response({
            'resources': [{
                'id': res.id,
                'title': res.title,
                'description': res.description,
                'category': res.category,
                'file_type': res.file_type.value,
                'file_path': res.file_path,
                'cdn_url': res.cdn_url,
                'file_size': res.file_size,
                'downloads': res.downloads,
                'created_at': res.created_at.isoformat(),
                'duration': res.duration,
                'access_level': res.access_level
            } for res in resources.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': resources.total,
                'pages': resources.pages
            }
        })
    except Exception as e:
        return json_response({"error": str(e)}, 500)

# -------------------------
# Additional Routes
# -------------------------
@main_bp.route('/stats', methods=['GET'])
def get_stats():
    """Get platform statistics"""
    try:
        stats = {
            'total_posts': Post.query.filter_by(is_active=True, is_approved=True).count(),
            'total_prayer_requests': PrayerRequest.query.filter_by(is_active=True, is_public=True).count(),
            'upcoming_events': Event.query.filter(
                Event.is_active == True,
                Event.start_time >= datetime.now(timezone.utc)
            ).count(),
            'total_resources': Resource.query.filter_by(is_active=True).count()
        }
        return json_response(stats)
    except Exception as e:
        return json_response({"error": str(e)}, 500)



@main_bp.route("/recent", methods=["GET"])
@jwt_required()
def recent_activities():
    current_user_id = get_jwt_identity()
    # Fetch recent 10 activities for logged-in user
    activities = (
        Activity.query.filter_by(user_id=current_user_id)
        .order_by(Activity.created_at.desc())
        .limit(10)
        .all()
    )
    return success_response([a.to_dict() for a in activities])

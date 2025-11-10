# backend/seeds.py
from datetime import datetime, timedelta
import random
from backend.extensions import db
from backend.models import User, Role, Post, PostCategory, PrayerRequest, PrayerStatus, Event, EventType

def seed_roles():
    """Seed default system roles into the database."""
    default_roles = [
        "member",
        "pastor",
        "admin",
        "SUPERADMIN"
        "moderator",
        "content_creator",
        "worship_leader",
    ]
    roles = {}
    for name in default_roles:
        role = Role.query.filter_by(name=name).first()
        if not role:
            role = Role(name=name)
            db.session.add(role)
        roles[name] = role
    db.session.commit()
    return roles


def seed_reference_data():
    """Seed default reference data for categories, statuses, and event types."""
    # Post categories
    default_post_categories = [
        "bible_study", "testimony", "discussion", "announcement",
        "prayer", "devotional", "sermon", "news"
    ]
    for name in default_post_categories:
        if not PostCategory.query.filter_by(name=name).first():
            db.session.add(PostCategory(name=name))

    # Prayer statuses
    default_prayer_statuses = [
        "pending", "answered", "in_progress", "needs_support"
    ]
    for name in default_prayer_statuses:
        if not PrayerStatus.query.filter_by(name=name).first():
            db.session.add(PrayerStatus(name=name))

    # Event types
    default_event_types = [
        "worship", "bible_study", "prayer_meeting", "fellowship",
        "community_service", "conference", "retreat", "workshop"
    ]
    for name in default_event_types:
        if not EventType.query.filter_by(name=name).first():
            db.session.add(EventType(name=name))

    db.session.commit()


def seed_database():
    """Seed the database with sample data"""
    roles = seed_roles()          # ensure roles exist
    seed_reference_data()         # ensure categories/statuses/types exist

    # Create admin user
    admin = User.query.filter_by(email="admin@example.com").first()
    if not admin:
        admin = User(
            username="admin",
            email="admin@example.com",
            first_name="Admin",
            last_name="User",
        )
        admin.set_password("admin123")
        admin.roles.append(roles["admin"])
        db.session.add(admin)

    # Create regular users
    users = []
    for i in range(1, 6):
        user = User.query.filter_by(email=f"user{i}@example.com").first()
        if not user:
            user = User(
                username=f"user{i}",
                email=f"user{i}@example.com",
                first_name=f"User{i}",
                last_name="Test",
            )
            user.set_password("password123")
            user.roles.append(roles["member"])
            db.session.add(user)
            users.append(user)

    db.session.commit()

    # ✅ Query categories, statuses, event types dynamically
    post_categories = PostCategory.query.all()
    prayer_statuses = PrayerStatus.query.all()
    event_types = EventType.query.all()

    post_titles = [
        "The Power of Prayer",
        "Finding Peace in Difficult Times",
        "Building a Strong Community",
        "The Importance of Faith",
        "Daily Devotional Guide",
    ]

    # Create sample posts
    for i in range(10):
        post = Post(
            title=random.choice(post_titles) + f" {i+1}",
            content=f"This is the content of post {i+1}. " * 20,
            category=random.choice(post_categories),
            user_id=random.choice(users).id if users else admin.id,
            excerpt=f"Brief excerpt for post {i+1}...",
            is_approved=True,
        )
        db.session.add(post)

    # Create prayer requests
    for i in range(8):
        prayer = PrayerRequest(
            title=f"Prayer Request {i+1}",
            content=f"Please pray for this situation {i+1}. " * 10,
            status=random.choice(prayer_statuses),
            user_id=random.choice(users).id if users else admin.id,
            is_anonymous=random.choice([True, False]),
        )
        db.session.add(prayer)

    # Create events
    for i in range(5):
        start_time = datetime.utcnow() + timedelta(days=i * 2)
        event = Event(
            title=f"Event {i+1}",
            description=f"Description for event {i+1}",
            event_type=random.choice(event_types),
            start_time=start_time,
            end_time=start_time + timedelta(hours=2),
            location=f"Location {i+1}",
            user_id=admin.id,
        )
        db.session.add(event)

    db.session.commit()
    print("✅ Database seeded successfully!")


    # Give SUPERADMIN role to your account
    user = User.query.filter_by(email="gayivore@gmail.com").first()
    superadmin_role = Role.query.filter_by(name="SUPERADMIN").first()
    if user and superadmin_role and superadmin_role not in user.roles:
        user.roles.append(superadmin_role)
        db.session.commit()
        print("✅ Superadmin role assigned")
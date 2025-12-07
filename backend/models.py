from datetime import datetime, timezone
import json
from uuid import uuid4
from typing import Optional, List, Dict, Any
import enum
import re
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request
from sqlalchemy import Column, ForeignKey, Index, Numeric, Float
from sqlalchemy.orm import relationship, validates
from sqlalchemy.dialects.postgresql import TSVECTOR, ARRAY
from slugify import slugify # type: ignore
from backend.extensions import db
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import Enum, String, Integer, Boolean, Date, DateTime, Text, BigInteger, JSON,  UniqueConstraint
import os
from sqlalchemy import event
from flask_login import UserMixin

user_roles = db.Table("user_roles",db.Column("user_id", db.Integer, db.ForeignKey("users.id"), primary_key=True),
    db.Column("role_id", db.Integer, db.ForeignKey("roles.id"), primary_key=True)
)



class UserStatus(enum.Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    DELETED = "deleted"
    PENDING = "pending"  # optional (e.g., waiting for email verification)



# --- Base Model ---
class BaseModel(db.Model):
    __abstract__ = True

    id = db.Column(db.BigInteger, primary_key=True)
    uuid = db.Column(db.String(36), default=lambda: str(uuid4()), unique=True, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    meta_data = db.Column(JSON, default=dict)

    def to_dict(self, exclude: Optional[List[str]] = None) -> Dict[str, Any]:
        exclude = exclude or []
        return {c.name: getattr(self, c.name) for c in self.__table__.columns if c.name not in exclude}

class Role(BaseModel):
    __tablename__ = "roles"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)
    users = db.relationship("User", secondary="user_roles", back_populates="roles")

    def __repr__(self):
        return f"<Role {self.name}>"

class PrayerStatus(BaseModel):
    __tablename__ = "prayer_statuses"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)
    prayer_requests = relationship("PrayerRequest", back_populates="status")


class EventType(BaseModel):
    __tablename__ = "event_types"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    events_of_type = relationship('Event', back_populates='event_type')


class ResourceType(BaseModel):
    __tablename__ = "resource_types"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)


class NotificationType(BaseModel):
    __tablename__ = "notification_types"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)


class PostCategory(BaseModel):
    __tablename__ = "post_categories"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    title = db.Column(db.String(200), nullable=False)
    content = db.Column(db.Text, nullable=False)

    # ✅ One-to-many: one category → many posts
    posts = db.relationship(
        "Post",
        back_populates="category",
        cascade="all, delete-orphan"
    )

    # ✅ Self-referencing foreign key for nesting categories
    parent_id = db.Column(db.Integer, db.ForeignKey("post_categories.id"), nullable=True)

    # ✅ Relationship to parent and children
    parent = db.relationship(
        "PostCategory",
        remote_side=[id],
        backref="subcategories"
    )





# --- User Model ---
class User(BaseModel,  UserMixin):
    __tablename__ = 'users'

    username = db.Column(String(120), unique=True, nullable=False, index=True)
    email = db.Column(String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(String(512), nullable=False)
    email_verified = db.Column(Boolean, default=False, nullable=False)
    verification_token = db.Column(String(255), unique=True)
    mfa_enabled = db.Column(Boolean, default=False)
    mfa_secret = db.Column(String(32))
    last_password_change = db.Column(DateTime(timezone=True))
    first_name = db.Column(String(150), nullable=False)
    last_name = db.Column(String(150), nullable=False)
    profile_picture = db.Column(db.String(200), nullable=True) # Assuming SQLAlchemy/Flask-SQLAlchemy

    bio = db.Column(Text)
    phone_number = db.Column(String(20), unique=True)
    date_of_birth = db.Column(Date)
    gender = db.Column(String(20))
    
    status = db.Column(db.String(20), nullable=False, default="active") 
    permissions = db.Column(JSON, default=lambda: [])
    last_login = db.Column(DateTime(timezone=True))
    login_count = db.Column(Integer, default=0)
    failed_login_attempts = db.Column(Integer, default=0)
    account_locked_until = db.Column(DateTime(timezone=True))

    push_token = db.Column(String(200))
    timezone = db.Column(String(50), default='UTC')
    language = db.Column(String(10), default='en')
    country = db.Column(String(2))
    reputation_score = db.Column(Integer, default=0)

    is_premium = db.Column(Boolean, default=False)
    premium_expires_at = db.Column(DateTime(timezone=True))
    subscription_id = db.Column(String(150))
    reset_token = db.Column(String(255))

    # --- Relationships ---
    posts = relationship('Post', back_populates='author', cascade='all, delete-orphan', foreign_keys='Post.user_id')
    approved_posts = relationship('Post', back_populates='approver', foreign_keys='Post.approved_by_id')
    prayer_requests = relationship('PrayerRequest', back_populates='user', cascade='all, delete-orphan')
    prayers_offered = relationship('Prayer', back_populates='user', cascade='all, delete-orphan')
    comments = relationship('Comment', back_populates='user', cascade='all, delete-orphan')
    reactions = relationship('Reaction', back_populates='user', cascade='all, delete-orphan')
    notifications = relationship('Notification', back_populates='user', cascade='all, delete-orphan')
    donations_made = relationship('Donation', foreign_keys='Donation.donor_id', back_populates='donor')
    donations_received = relationship('Donation', foreign_keys='Donation.recipient_id', back_populates='recipient')
    donation_notifications_sent = relationship('DonationNotification', foreign_keys='DonationNotification.donor_id', back_populates='donor')
    donation_notifications_received = relationship('DonationNotification', foreign_keys='DonationNotification.recipient_id', back_populates='recipient')
    events = relationship('Event', back_populates='user', cascade='all, delete-orphan')
    event_attendances = relationship('EventAttendee', back_populates='user', cascade='all, delete-orphan')
    event_reminders = relationship('EventReminder', back_populates='user', cascade='all, delete-orphan')
    resources = relationship('Resource', back_populates='user', cascade='all, delete-orphan')
    activities = relationship("Activity", back_populates="user", cascade='all, delete-orphan')
    messages = relationship("Message", back_populates="sender", cascade="all, delete-orphan")
    devotions = relationship("Devotion", back_populates="author", cascade="all, delete-orphan", passive_deletes=True)
    study_plans = relationship("StudyPlan",back_populates="author", cascade="all, delete-orphan",passive_deletes=True)
    study_plan_progresses = relationship("StudyPlanProgress",back_populates="user",cascade="all, delete-orphan",passive_deletes=True)
    archives = relationship("Archive", back_populates="author", cascade="all, delete-orphan", passive_deletes=True)
    forum_threads = relationship("ForumThread", back_populates="author", cascade="all, delete-orphan")
    forum_posts = relationship("ForumPost", back_populates="author", cascade="all, delete-orphan")
    forum_likes = relationship("ForumLike", back_populates="user", cascade="all, delete-orphan")
    forum_comments = relationship("ForumComment", back_populates="user", cascade="all, delete-orphan")
    roles = relationship("Role", secondary="user_roles", back_populates="users")
    testimonies = relationship("Testimony", back_populates="user")
    testimony_comments = relationship("TestimonyComment", back_populates="user")
    testimony_likes = relationship("TestimonyLike", back_populates="user")
    group_chats_created = db.relationship('GroupChat',back_populates='created_by', foreign_keys='GroupChat.created_by_id', cascade='all, delete-orphan'
    )
    
    # Group memberships (groups this user belongs to)
    group_memberships = db.relationship(
        'GroupMember', 
        back_populates='user', 
        cascade='all, delete-orphan'
    )
    
    # Messages sent in groups
    group_messages = db.relationship(
        'GroupMessage', 
        back_populates='sender', 
        cascade='all, delete-orphan'
    )


    
    # --- Table constraints & indexes ---
    __table_args__ = (
        UniqueConstraint("username", name="uq_users_username"),
        UniqueConstraint("email", name="uq_users_email"),
        UniqueConstraint("phone_number", name="uq_users_phone_number"),
        Index("ix_users_email_username", "email", "username"),
    )
    
    
    @property
    def avatar_url(self):
        """Alias for profile_picture to satisfy the to_dict method requirement."""
        return self.profile_picture
    



    # --- Validators & Methods ---
    @validates('email')
    def validate_email(self, key, email):
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        if not re.match(pattern, email):
            raise ValueError("Invalid email address")
        return email.lower()

    @validates('username')
    def validate_username(self, key, username):
        if not 3 <= len(username) <= 80:
            raise ValueError("Username must be 3-80 characters")
        if not re.match(r'^[A-Za-z0-9_ ]+$', username):
            raise ValueError("Username can only contain letters, numbers, underscores, and spaces")
        return username.lower()
    
    @validates('phone_number')
    def validate_phone(self, key, phone):
        if phone:
            phone = re.sub(r'\D', '', phone)  # keep only digits
        return phone



    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
        self.last_password_change = datetime.now(timezone.utc)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def get_full_name(self):
        return f"{self.first_name} {self.last_name}"
    
    
    def update_last_login(self):
        self.last_login = datetime.utcnow()
        db.session.commit()

    
    
    
     # --- Status helpers ---
    def is_active(self) -> bool:
        return self.status == "active"

    def is_suspended(self) -> bool:
        return self.status == "suspended"

    def is_deleted(self) -> bool:
        return self.status == "deleted"

    def activate(self):
        self.status = "active"
        db.session.commit()

    def suspend(self):
        self.status = "suspended"
        db.session.commit()

    def soft_delete(self):
        """Mark as deleted without removing from DB"""
        self.status = "deleted"
        db.session.commit()
    
    
    
    
    
    # --- Utility methods ---

    
    def has_role(self, role_name: str) -> bool:
        return any(role.name == role_name for role in self.roles)

    def to_dict(self, exclude: Optional[List[str]] = None):
        default_exclude = [
            "password_hash", "mfa_secret", "verification_token",
            "reset_token", "meta_data"
        ]
        if exclude:
            default_exclude.extend(exclude)
        data = super().to_dict(exclude=default_exclude)
        data["full_name"] = self.get_full_name()
        data["roles"] = [r.name for r in self.roles] # return multiple roles
        data["group_chats_count"] = len([gm for gm in self.group_memberships if gm.is_active])
        data["groups_created_count"] = len([gc for gc in self.group_chats_created if gc.is_active])
        
        return data
    
    def add_role(self, role_name: str):
        """Assign a role to the user if not already assigned"""
        role = Role.query.filter_by(name=role_name).first()
        if role and role not in self.roles:
            self.roles.append(role)
            db.session.commit()

    def remove_role(self, role_name: str):
        """Remove a role from the user if it exists"""
        role = Role.query.filter_by(name=role_name).first()
        if role and role in self.roles:
            self.roles.remove(role)
            db.session.commit()

    def set_roles(self, role_names: list[str]):
        """Replace all user roles with a new set"""
        # Fetch all roles that match the given names
        roles = Role.query.filter(Role.name.in_(role_names)).all()
        self.roles = roles
        db.session.commit()


    
    
    
# --- Post Model ---
class Post(BaseModel):
    __tablename__ = "posts"

    title = db.Column(String(200), nullable=False, index=True)
    content = db.Column(Text, nullable=False)
    excerpt = db.Column(String(300))
    slug = db.Column(String(210), unique=True, index=True)
    featured_image = db.Column(String(200))
    media_assets = db.Column(JSON, default=list)
    audio_url = db.Column(String(200))
    video_url = db.Column(String(200))
    duration = db.Column(Integer)
    view_count = db.Column(Integer, default=0)
    unique_views = db.Column(Integer, default=0)
    share_count = db.Column(Integer, default=0)
    save_count = db.Column(Integer, default=0)
    reading_time = db.Column(Integer)
    is_featured = db.Column(Boolean, default=False)
    is_pinned = db.Column(Boolean, default=False)
    featured_until = db.Column(DateTime(timezone=True))
    pin_until = db.Column(DateTime(timezone=True))
    sentiment_score = db.Column(Float)
    content_quality = db.Column(Float)
    seo_keywords = db.Column(ARRAY(String(50)))

    approved_by_id = db.Column(BigInteger, db.ForeignKey("users.id"))
    user_id = db.Column(BigInteger, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    category_id = db.Column(Integer, db.ForeignKey("post_categories.id"), nullable=True)
    thread_id = db.Column(Integer, db.ForeignKey("forum_threads.id"), nullable=False)

    is_approved = db.Column(Boolean, default=False)
   

   
   
 
    
    # ✅ relationships
    author = relationship("User", foreign_keys=[user_id], back_populates="posts")
    approver = relationship("User", foreign_keys=[approved_by_id], back_populates="approved_posts")
    comments = relationship("Comment", back_populates="post", cascade="all, delete-orphan")
    reactions = relationship("Reaction", back_populates="post", cascade="all, delete-orphan")  
    thread = relationship("ForumThread", back_populates="posts" )
    # ✅ Relationship back to PostCategory
    category = relationship("PostCategory", back_populates="posts")
  

    __table_args__ = (
        Index("ix_posts_category_approved", "category_id", "is_approved", "is_active"),
        Index("ix_posts_created_featured", "created_at", "is_featured"),
        Index("ix_posts_slug_active", "slug", "is_active"),
        Index("ix_posts_sentiment", "sentiment_score", "is_active"),
    )

    def generate_slug(self):
        self.slug = f"{slugify(self.title)}-{uuid4().hex[:8]}"

    def calculate_reading_time(self, words_per_minute=200):
        word_count = len(self.content.split())
        self.reading_time = max(1, round(word_count / words_per_minute))

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "content": self.content,
            "user_id": self.user_id,
            "thread_id": self.thread_id,
            "category_id": self.category_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


# --- Donation Model ---
class Donation(BaseModel):
    __tablename__ = 'donations'

    amount = db.Column(Numeric(10, 2), nullable=False)
    currency = db.Column(String(10), nullable=False)
    donor_id = db.Column(BigInteger, db.ForeignKey('users.id'), nullable=False)
    recipient_id = db.Column(BigInteger, db.ForeignKey('users.id'))
    payment_method = db.Column(String(50))
    transaction_id = db.Column(String(100), unique=True)
    status = db.Column(String(20), default='pending')
    fee = db.Column(Numeric(10, 2))
    purpose = db.Column(String(100))
    is_recurring = db.Column(Boolean, default=False)
    recurrence_frequency = db.Column(String(20))
  


    # Relationships
    donation_notifications = relationship('DonationNotification', back_populates='donation',cascade='all, delete-orphan'
)
    donor = relationship('User', foreign_keys=[donor_id], back_populates='donations_made')
    recipient = relationship('User', foreign_keys=[recipient_id], back_populates='donations_received')

    __table_args__ = (
        Index('ix_donations_status', 'status', 'created_at'),
        Index('ix_donations_currency', 'currency', 'created_at'),
        Index('ix_donations_donor', 'donor_id'),
        Index('ix_donations_recipient', 'recipient_id'),
    )


# --- PrayerRequest Model ---
class PrayerRequest(BaseModel):
    __tablename__ = 'prayer_requests'

    title = Column(String(200), nullable=False, index=True)
    content = Column(Text, nullable=False)
    is_anonymous = Column(Boolean, default=False, nullable=False)
    category = Column(String(50), default="General", nullable=False)

    status_id = Column(Integer, db.ForeignKey("prayer_statuses.id"), nullable=False)
    status = relationship("PrayerStatus", back_populates="prayer_requests")

    prayer_count = Column(Integer, default=0)
    unique_prayers = Column(Integer, default=0)
    answered_at = Column(DateTime(timezone=True))
    is_public = Column(Boolean, default=True)
    allow_comments = Column(Boolean, default=True)
    allow_prayers = Column(Boolean, default=True)
    urgency_level = Column(Integer, default=1)
    suggested_verses = Column(JSON)
    sentiment_analysis = Column(JSON)

    user_id = Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)

    # Relationships
    user = relationship('User', back_populates='prayer_requests')
    prayers = relationship('Prayer', back_populates='prayer_request', cascade='all, delete-orphan')
    comments = relationship('Comment', back_populates='prayer_request', cascade='all, delete-orphan')

    __table_args__ = (
        Index('ix_prayer_requests_status', 'status_id', 'is_active'),
        Index('ix_prayer_requests_public', 'is_public', 'created_at'),
        Index('ix_prayer_requests_urgency', 'urgency_level', 'created_at'),
    )

    def to_dict(self, include_prayers=False, current_user_id=None):
        """
        Serialize prayer request to dictionary.
        :param include_prayers: include prayers details
        :param current_user_id: used to check if current user has prayed
        """
        data = {
            "id": self.id,
            "title": self.title,
            "content": self.content,
            "is_anonymous": self.is_anonymous,
            "category": self.category,
            "status": self.status.name if self.status else None,
            "prayer_count": self.prayer_count,
            "unique_prayers": self.unique_prayers,
            "answered_at": self.answered_at.isoformat() if self.answered_at else None,
            "is_public": self.is_public,
            "allow_comments": self.allow_comments,
            "allow_prayers": self.allow_prayers,
            "urgency_level": self.urgency_level,
            "suggested_verses": self.suggested_verses,
            "sentiment_analysis": self.sentiment_analysis,
            "user_id": self.user_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "has_prayed": False,  # default
        }

        if include_prayers:
            data["prayers"] = [p.to_dict() for p in self.prayers]

        # Check if current user has prayed
        if current_user_id:
            data["has_prayed"] = any(p.user_id == current_user_id for p in self.prayers)

        return data    

# --- Prayer Model ---
class Prayer(BaseModel):
    __tablename__ = 'prayers'

    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    prayer_request_id = db.Column(BigInteger, db.ForeignKey('prayer_requests.id', ondelete='CASCADE'), nullable=False)
    message = db.Column(Text, nullable=False)

    # Relationships
    user = relationship('User', back_populates='prayers_offered')
    prayer_request = relationship('PrayerRequest', back_populates='prayers')

    __table_args__ = (
        Index('ix_prayers_user_request', 'user_id', 'prayer_request_id'),
    )
    
    
    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "prayer_request_id": self.prayer_request_id,
            "message": self.message,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
    


# --- Comment Model ---
class Comment(BaseModel):
    __tablename__ = 'comments'

    content = db.Column(Text, nullable=False)
    content_html = db.Column(Text)
    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    post_id = db.Column(BigInteger, db.ForeignKey('posts.id', ondelete='CASCADE'))
    prayer_request_id = db.Column(BigInteger, db.ForeignKey('prayer_requests.id', ondelete='CASCADE'))
    event_id = db.Column(BigInteger, db.ForeignKey('events.id', ondelete='CASCADE'))
    parent_id = db.Column(BigInteger, db.ForeignKey('comments.id', ondelete='CASCADE'))
    depth = db.Column(Integer, default=0)
    path = db.Column(ARRAY(BigInteger))
    reply_count = db.Column(Integer, default=0)
    sentiment = db.Column(Float)
    toxicity_score = db.Column(Float)
    is_approved = db.Column(Boolean, default=True)
    flagged = db.Column(Boolean, default=False)
    flag_reason = db.Column(String(100))
    upvotes = db.Column(Integer, default=0)
    downvotes = db.Column(Integer, default=0)
    score = db.Column(Integer, default=0)

    # Relationships
    user = relationship('User', back_populates='comments')
    post = relationship('Post', back_populates='comments')
    prayer_request = relationship('PrayerRequest', back_populates='comments')
    event = relationship('Event', back_populates='comments')
    parent = relationship('Comment', remote_side='Comment.id', back_populates='replies')
    replies = relationship('Comment', back_populates='parent', cascade='all, delete-orphan')
    reactions = relationship('Reaction', back_populates='comment', cascade='all, delete-orphan')

    __table_args__ = (
        Index('ix_comments_post', 'post_id', 'created_at'),
        Index('ix_comments_prayer', 'prayer_request_id', 'created_at'),
        Index('ix_comments_path', 'path', postgresql_using='gin'),
        Index('ix_comments_score', 'score', 'created_at'),
    )

# --- Reaction Model ---
class Reaction(BaseModel):
    __tablename__ = 'reactions'

    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    post_id = db.Column(BigInteger, db.ForeignKey('posts.id', ondelete='CASCADE'))
    comment_id = db.Column(BigInteger, db.ForeignKey('comments.id', ondelete='CASCADE'))
    reaction_type = db.Column(String(20), nullable=False)

    # Relationships
    user = relationship('User', back_populates='reactions')
    post = relationship('Post', back_populates='reactions')
    comment = relationship('Comment', back_populates='reactions')

    __table_args__ = (
        Index('ix_reactions_user_post', 'user_id', 'post_id'),
        Index('ix_reactions_user_comment', 'user_id', 'comment_id'),
    )


# --- Event Model ---
class Event(BaseModel):
    __tablename__ = 'events'

    title = db.Column(String(200), nullable=False, index=True)
    description = db.Column(Text, nullable=False)
    start_time = db.Column(db.DateTime(timezone=True), nullable=False, index=True)
    end_time = db.Column(DateTime(timezone=True), nullable=False)
    timezone = db.Column(String(50), default='UTC')
    location = db.Column(String(255))
    latitude = db.Column(Float)
    longitude = db.Column(Float)
    is_virtual = db.Column(Boolean, default=False, nullable=False)
    meeting_link = db.Column(String(200))
    max_attendees = db.Column(Integer)
    current_attendees = db.Column(Integer, default=0)
    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    # ✅ Instead of Enum(EventType)
    event_type_id = db.Column(db.Integer, db.ForeignKey("event_types.id"), nullable=False)
    
    event_type = relationship('EventType', back_populates='events_of_type') 
    

    # Relationships
    user = relationship('User', back_populates='events')
    attendees = relationship('EventAttendee', back_populates='event', cascade='all, delete-orphan')
    reminders = relationship('EventReminder', back_populates='event', cascade='all, delete-orphan')
    comments = relationship('Comment', back_populates='event', cascade='all, delete-orphan')

    __table_args__ = (
        Index('ix_events_geo', 'latitude', 'longitude'),
    )


# --- EventAttendee Model ---
class EventAttendee(BaseModel):
    __tablename__ = 'event_attendees'

    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    event_id = db.Column(BigInteger, db.ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    status = db.Column(String(20), default='registered')

    # Relationships
    user = relationship('User', back_populates='event_attendances')
    event = relationship('Event', back_populates='attendees')

    __table_args__ = (
        Index('ix_event_attendees_user_event', 'user_id', 'event_id'),
    )


# --- EventReminder Model ---
class EventReminder(BaseModel):
    __tablename__ = 'event_reminders'

    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    event_id = db.Column(BigInteger, db.ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    reminder_time = db.Column(DateTime(timezone=True), nullable=False)
    is_sent = db.Column(Boolean, default=False)
    sent_at = db.Column(DateTime(timezone=True))
    message = db.Column(String(200))
    meta_data = db.Column(JSON, default=dict)

    # Relationships
    user = relationship('User', back_populates='event_reminders')
    event = relationship('Event', back_populates='reminders')

    __table_args__ = (
        Index('ix_event_reminders_user_event', 'user_id', 'event_id', 'reminder_time'),
        Index('ix_event_reminders_sent', 'is_sent', 'reminder_time'),
    )

    def mark_as_sent(self):
        self.is_sent = True
        self.sent_at = datetime.now(timezone.utc)


# --- Resource Model ---
class Resource(BaseModel):
    __tablename__ = "resources"

    title = db.Column(String(200), nullable=False, index=True)
    description = db.Column(Text, nullable=True)
    url = db.Column(String(512), nullable=False, unique=True)
    user_id = db.Column(BigInteger, db.ForeignKey("users.id"), nullable=True)
    search_vector = db.Column(TSVECTOR)
    resource_type_id = db.Column(db.Integer, db.ForeignKey("resource_types.id"), nullable=False)
    

    file_url = db.Column(db.String(500))
    uploaded_at = db.Column(db.DateTime(timezone=True), server_default=db.func.now())


    # Relationships
    user = relationship("User", back_populates="resources")

    __table_args__ = (
        Index("ix_resources_search", "search_vector", postgresql_using="gin"),
    )


# --- Notification Model ---
class Notification(BaseModel):
    __tablename__ = 'notifications'

    user_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    title = db.Column(String(200), nullable=False)
    message = db.Column(Text, nullable=False)
    is_read = db.Column(Boolean, default=False, nullable=False)
    read_at = db.Column(DateTime(timezone=True))
    is_delivered = db.Column(Boolean, default=False, nullable=False)
    delivered_at = db.Column(DateTime(timezone=True))
    action_url = db.Column(String(200))
    action_label = db.Column(String(50))
    priority = db.Column(Integer, default=1, nullable=False)
    expires_at = db.Column(DateTime(timezone=True))
    scheduled_for = db.Column(DateTime(timezone=True))
    source_id = db.Column(BigInteger)
    notification_meta = db.Column(JSON, default=dict)
    
    notification_type_id = db.Column(db.Integer, db.ForeignKey("notification_types.id"), nullable=False)
    


    

    # Relationships
    user = relationship('User', back_populates='notifications')

    __table_args__ = (
        Index('ix_notifications_user_read', 'user_id', 'is_read', 'created_at'),
        Index('ix_notifications_delivered_scheduled', 'is_delivered', 'scheduled_for'),
    )


# --- DonationNotification Model ---
class DonationNotification(BaseModel):
    __tablename__ = 'donation_notifications'

    donor_id = db.Column(BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    donation_id = db.Column(BigInteger, db.ForeignKey('donations.id', ondelete='CASCADE'), nullable=False)
    recipient_id = db.Column(BigInteger, db.ForeignKey('users.id'))
    message = db.Column(String(200))
    is_read = db.Column(Boolean, default=False)
    read_at = db.Column(DateTime(timezone=True))
   

    # Relationships
    donor = relationship('User', foreign_keys=[donor_id], back_populates='donation_notifications_sent')
    recipient = relationship('User', foreign_keys=[recipient_id], back_populates='donation_notifications_received')
    donation = relationship('Donation', foreign_keys=[donation_id], back_populates='donation_notifications')

    __table_args__ = (
        Index('ix_donation_notifications_donor_recipient', 'donor_id', 'recipient_id', 'is_read'),
        Index('ix_donation_notifications_donation', 'donation_id'),
    )

    def mark_as_read(self):
        self.is_read = True
        self.read_at = datetime.now(timezone.utc)



class Activity(BaseModel):
    __tablename__ = "activities"

    id = Column(Integer, primary_key=True)
    title = Column(String(120), nullable=False)
    subtitle = Column(String(255))
    icon = Column(String(50), default="notifications")
    color = Column(String(50), default="grey")
    time_ago = Column(String(50), default="just now")
    
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    # Relationship with User
    user = relationship("User", back_populates="activities")

    # String representation
    def __repr__(self):
        return f"<Activity id={self.id} title={self.title} user_id={self.user_id}>"

    # Convert to dictionary for API
    def to_dict(self, include_user=False):
        data = {
            "id": self.id,
            "title": self.title,
            "subtitle": self.subtitle,
            "icon": self.icon,
            "color": self.color,
            "timeAgo": self.time_ago,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
            "updatedAt": self.updated_at.isoformat() if self.updated_at else None,
            "isActive": self.is_active,
            "metaData": self.meta_data,
            "userId": self.user_id,
        }
        if include_user and self.user:
            data["user"] = {
                "id": self.user.id,
                "username": self.user.username,
                "fullName": self.user.get_full_name() if hasattr(self.user, "get_full_name") else None,
                "profilePicture": getattr(self.user, "profile_picture", None),
            }
        return data

    # Helper for recent activities
    @classmethod
    def recent(cls, session, limit=10):
        """
        Fetch recent activities, newest first.
        Usage: Activity.recent(db.session, limit=5)
        """
        return session.query(cls).filter_by(is_active=True).order_by(cls.created_at.desc()).limit(limit).all()


class Message(BaseModel):
    __tablename__ = "messages"

    id = db.Column(BigInteger, primary_key=True)
    uuid = db.Column(String(36), unique=True, nullable=False, default=lambda: str(uuid4()))
    group_id = db.Column(String(64), nullable=False, index=True)

    sender_id = db.Column(BigInteger, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    

    content = db.Column(Text, nullable=False)
    timestamp = db.Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    is_active = db.Column(Boolean, default=True, nullable=False)
    meta_data = db.Column(db.JSON, default=dict)
    
    
    # Relationship
    sender = relationship("User", back_populates="messages")

    def to_dict(self, include_sender=True):
        data = {
            "id": self.id,
            "uuid": self.uuid,
            "group_id": self.group_id,
            "sender_id": self.sender_id,
            "content": self.content,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "is_active": self.is_active,
            "meta_data": self.meta_data,
        }
        if include_sender and self.sender:
            data["sender_name"] = self.sender.get_full_name() if hasattr(self.sender, "get_full_name") else self.sender.username
            data["sender_username"] = self.sender.username
            data["sender_profile_picture"] = getattr(self.sender, "profile_picture", None)
        return data
    

class StudyLevel(enum.Enum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"
    ALL_LEVELS = "all_levels"

# --- Devotion Model ---
class Devotion(BaseModel):
    __tablename__ = "devotions"

    title = Column(String(200), nullable=False, index=True)
    verse = Column(String(100), nullable=False, index=True)
    content = Column(Text, nullable=False)
    reflection = Column(Text)
    prayer = Column(Text)
    date = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        index=True
    )

    author_id = Column(db.BigInteger, ForeignKey("users.id", ondelete="SET NULL"))
    author = relationship("User", back_populates="devotions")


    __table_args__ = (
        Index("ix_devotions_author_date", "author_id", "date"),
    )

    def to_dict(self, include_author=False):
        data = super().to_dict()
        data.update({
            "title": self.title,
            "verse": self.verse,
            "content": self.content,
            "reflection": self.reflection,
            "prayer": self.prayer,
            "date": self.date.isoformat() if self.date else None,
        })
        if include_author and self.author:
            data["author"] = {
                "id": self.author.id,
                "username": self.author.username,
                "full_name": self.author.get_full_name(),
                "profile_picture": getattr(self.author, "profile_picture", None),
            }
        return data

# ================= STUDY PLAN =================
class StudyPlan(BaseModel):
    __tablename__ = "study_plans"

    title = Column(String(200), nullable=False, index=True)
    description = Column(Text)
    level = Column(Enum(StudyLevel), default=StudyLevel.BEGINNER, nullable=False)
    total_days = Column(Integer, default=10)
    is_public = Column(Boolean, default=True, nullable=False)

    author_id = Column(db.BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    author = relationship("User", back_populates="study_plans")
    verses_json = Column(db.Text, nullable=True) 


    progresses = relationship("StudyPlanProgress",back_populates="plan",cascade="all, delete-orphan",passive_deletes=True)

    __table_args__ = (
        Index("ix_study_plans_public_active", "is_public", "is_active"),
        Index("ix_study_plans_author_level", "author_id", "level"),
    )

    def to_dict(self, include_author=False, include_progress=False):
        data = super().to_dict()
        data.update({
            "title": self.title,
            "description": self.description,
            "level": self.level.value if self.level else None,
            "total_days": self.total_days,
            "is_public": self.is_public,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "verses": json.loads(self.verses_json) if self.verses_json else [],
        })
        if include_author and self.author:
            data["author"] = {
                "id": self.author.id,
                "full_name": self.author.get_full_name(),
                "username": self.author.username,
            }
        if include_progress:
            data["progresses"] = [p.to_dict(include_user=True) for p in self.progresses]
        return data


# --- StudyPlanProgress Model ---
class StudyPlanProgress(BaseModel):
    __tablename__ = "study_plan_progresses"

    user_id = Column(db.BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    plan_id = Column(db.BigInteger, ForeignKey("study_plans.id", ondelete="CASCADE"), nullable=False)

    current_day = Column(Integer, default=1)
    completed = Column(Boolean, default=False, nullable=False)

    user = relationship("User", back_populates="study_plan_progresses")
    plan = relationship("StudyPlan", back_populates="progresses")

    __table_args__ = (
        Index("ix_progress_user_plan", "user_id", "plan_id", unique=True),
    )

    def to_dict(self, include_user=False):
        data = super().to_dict()
        data.update({
            "current_day": self.current_day,
            "completed": self.completed,
            "plan_id": self.plan_id,
        })
        if include_user and self.user:
            data["user"] = {
                "id": self.user.id,
                "username": self.user.username,
                "full_name": self.user.get_full_name(),
            }
        return data



class Archive(BaseModel):
    
    __tablename__ = "archives"

    title = Column(String(200), nullable=False, index=True)
    notes = Column(Text)
    category = Column(String(100), default="general", index=True)

    author_id = Column(db.BigInteger, ForeignKey("users.id", ondelete="CASCADE"))
    author = relationship("User", back_populates="archives")


    __table_args__ = (
        Index("ix_archives_category_author", "category", "author_id"),
    )

    def to_dict(self, include_author=False):
        data = super().to_dict()
        data.update({
            "title": self.title,
            "notes": self.notes,
            "category": self.category,
        })
        if include_author and self.author:
            data["author"] = {
                "id": self.author.id,
                "username": self.author.username,
                "full_name": self.author.get_full_name(),
            }
        return data


class ForumThread(BaseModel):
    __tablename__ = "forum_threads"

    id = Column(Integer, primary_key=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
   

    category_id = Column(Integer, ForeignKey("forum_categories.id"))
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    posts = relationship("Post", back_populates="thread", cascade="all, delete-orphan")
    forum_posts = relationship("ForumPost", back_populates="thread", cascade="all, delete-orphan")
    likes = relationship("ForumLike", back_populates="thread", lazy="dynamic")


    author = relationship("User", back_populates="forum_threads")
    category = relationship("ForumCategory", back_populates="threads")

    def to_dict(self, include_posts=False, include_forum_posts=False, current_user_id=None):        
        data = {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "created_at": self.created_at.isoformat(),
            "author_id": self.author_id,
            "author_name": self.author.username if self.author else None,
            "author_avatar": self.author.avatar_url if self.author else None,
            "category_id": self.category_id,
            "posts_count": len(self.posts),
            "forum_posts_count": len(self.forum_posts),
            "like_count": ForumLike.query.filter_by(thread_id=self.id, reaction_type="like").count(),
            "dislike_count": ForumLike.query.filter_by(thread_id=self.id, reaction_type="dislike").count(),
            "liked_by_me": False,
            "disliked_by_me": False,
        }

        # ✅ Determine if the current user liked/disliked this thread
        if current_user_id:
            user_reaction = ForumLike.query.filter_by(
                thread_id=self.id, user_id=current_user_id
            ).first()
            if user_reaction:
                if user_reaction.reaction_type == "like":
                    data["liked_by_me"] = True
                elif user_reaction.reaction_type == "dislike":
                    data["disliked_by_me"] = True

        if include_posts:
            data["posts"] = [p.to_dict() for p in self.posts]
        if include_forum_posts:
            data["forum_posts"] = [fp.to_dict() for fp in self.forum_posts]

        return data


class ForumPost(BaseModel):
    __tablename__ = "forum_posts"

    id = Column(db.Integer, primary_key=True)
    title = Column(db.String(200), nullable=False)
    content = Column(db.Text, nullable=False)
    
    
  

    thread_id = Column(db.Integer, db.ForeignKey("forum_threads.id"), nullable=False)
    author_id = Column(db.Integer, db.ForeignKey("users.id"), nullable=False)


    # Relationships
    thread = relationship("ForumThread", back_populates="forum_posts")
    author = relationship("User", back_populates="forum_posts")
    comments = relationship("ForumComment", back_populates="post", cascade="all, delete-orphan")
    attachments = relationship("ForumAttachment", back_populates="post", cascade="all, delete-orphan")
    likes = relationship("ForumLike", back_populates="post", cascade="all, delete-orphan")
    

    def to_dict(self, with_user=False, include_attachments=True):
        liked_by_me = False
        try:
            verify_jwt_in_request(optional=True)
            current_user_id = get_jwt_identity()
            if current_user_id:
                liked_by_me = any(l.user_id == current_user_id for l in self.likes)
        except Exception:
            pass

        data = {
            "id": self.id,
            "title": self.title,
            "content": self.content,
            "thread_id": self.thread_id,
            "author_id": self.author_id,
            "author_name": self.author.username if self.author else "Unknown",
            "author_avatar": getattr(self.author, "avatar_url", None),
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "like_count": len(self.likes),
            "liked_by_me": liked_by_me,
            "comments_count": len(self.comments),
        }

        if include_attachments:
            data["attachments"] = [a.to_dict() for a in self.attachments]

        if with_user and self.author:
            data["user"] = self.author.to_dict()

        return data





class ForumComment(BaseModel):
    __tablename__ = "forum_comments"

    id = Column(db.Integer, primary_key=True)
    content = Column(db.Text, nullable=False)
    post_id = Column(db.Integer, db.ForeignKey("forum_posts.id"), nullable=False)
    author_id = Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    # Relationships
    post = relationship("ForumPost", back_populates="comments")
    user = relationship("User", back_populates="forum_comments")
    attachments = relationship("ForumAttachment", back_populates="comment", cascade="all, delete-orphan")

    def to_dict(self, include_attachments: bool = True):
        """Serialize ForumComment to dictionary."""
        data = {
            "id": self.id,
            "content": self.content,
            "post_id": self.post_id,
            "author_id": self.author_id,
            "author_name": self.user.username if self.user else "Unknown",
            "author_avatar": getattr(self.user, "avatar_url", None),
            "created_at": self.created_at.isoformat(),
        }

        if include_attachments:
            data["attachments"] = [a.to_dict() for a in self.attachments]
            data["attachmentIds"] = [str(a.id) for a in self.attachments]

        return data  


class ForumAttachment(BaseModel):
    __tablename__ = "forum_attachments"

    id = Column(db.Integer, primary_key=True)
    file_url = Column(db.String(255), nullable=False)
    file_type =Column(db.String(50), nullable=False)
    file_path =Column(db.String(255), nullable=False)
    file_name =Column(db.String(255), nullable=False)
    mime_type =Column(db.String(100), nullable=False, default="application/octet-stream")
    created_at =Column(db.DateTime, default=datetime.utcnow)

    post_id = Column(db.Integer, db.ForeignKey("forum_posts.id"))
    comment_id = Column(db.Integer, db.ForeignKey("forum_comments.id"))

    # Relationships
    post = relationship("ForumPost", back_populates="attachments")
    comment = relationship("ForumComment", back_populates="attachments")

    def to_dict(self):
        return {
            "id": self.id,
            "file_url": self.file_url,
            "file_type": self.file_type,
            "file_name": self.file_name,
            "mime_type": self.mime_type,
            "post_id": self.post_id,
            "comment_id": self.comment_id,
            "created_at": self.created_at.isoformat(),
            "url": f"/forums/attachments/{self.id}",
        }


class ForumCategory(BaseModel):
    __tablename__ = "forum_categories"

    id = Column(db.Integer, primary_key=True)
    name = Column(db.String(100), nullable=False, unique=True)

    # Relationships
    threads = relationship("ForumThread", back_populates="category", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "threads_count": len(self.threads),
        }


class ForumLike(BaseModel):
    __tablename__ = "forum_likes"

    id = Column(db.Integer, primary_key=True)
    created_at = Column(db.DateTime, default=datetime.utcnow)

    user_id = Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    post_id = Column(db.Integer, db.ForeignKey("forum_posts.id"), nullable=True)
    thread_id = Column(db.Integer, db.ForeignKey("forum_threads.id"), nullable=True)
    
    reaction_type = Column(db.String(20), default="like")

    # Relationships
    user = relationship("User", back_populates="forum_likes")
    post = relationship("ForumPost", back_populates="likes")
    thread = relationship("ForumThread", back_populates="likes")

    __table_args__ = (
        db.UniqueConstraint("user_id", "post_id", "reaction_type", name="uq_user_post_reaction"),
        db.UniqueConstraint("user_id", "thread_id", "reaction_type", name="uq_user_thread_reaction"),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "post_id": self.post_id,"thread_id": self.thread_id,
            "reaction_type": self.reaction_type,
            "thread_id": self.thread_id,
            "created_at": self.created_at.isoformat(),
        }


# --- Cleanup event: remove files from disk when attachments are deleted ---
@event.listens_for(ForumAttachment, "before_delete")
def delete_file_from_disk(mapper, connection, target):
    """Delete file from disk when an attachment row is deleted."""
    if target.file_path and os.path.exists(target.file_path):
        try:
            os.remove(target.file_path)
        except Exception:
            pass


class Testimony(BaseModel):
    __tablename__ = 'testimonies'

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(255), nullable=False)
    content = db.Column(db.Text, nullable=False)
    image_url = db.Column(db.String(500), nullable=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    
    is_anonymous = db.Column(db.Boolean, default=False)
    
    user = db.relationship("User", back_populates="testimonies")
    comments = db.relationship("TestimonyComment", back_populates="testimony", cascade="all, delete-orphan")
    likes = db.relationship("TestimonyLike", back_populates="testimony", cascade="all, delete-orphan")


    

    def to_dict(self, include_comments=False):
        data = {
            "id": self.id,
            "title": self.title,
            "content": self.content,
            "is_anonymous": self.is_anonymous,
            "image_url": self.image_url,
            "created_at": self.created_at.isoformat(),
            "user": None if self.is_anonymous else {
                "id": self.user.id if self.user else None,
                "name": self.user.username if self.user else "Guest"
            },
            "like_count": len(self.likes),
            "comment_count": len(self.comments)
            
        }
        if include_comments:
            data["comments"] = [c.to_dict() for c in self.comments]
        return data
    
    

class TestimonyComment(BaseModel):
    __tablename__ = "testimony_comments"

    id = db.Column(db.Integer, primary_key=True)
    testimony_id = db.Column(db.Integer, db.ForeignKey("testimonies.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    content = db.Column(db.Text, nullable=False)
    

    testimony = relationship("Testimony", back_populates="comments")
    user = relationship("User", back_populates="testimony_comments")

    def to_dict(self):
        return {
            "id": self.id,
            "content": self.content,
            "created_at": self.created_at.isoformat(),
            "user": {
                "id": self.user.id if self.user else None,
                "name": self.user.username if self.user else "Anonymous"
            }
        }




class TestimonyLike(BaseModel):
    __tablename__ = "testimony_likes"

    id = db.Column(db.Integer, primary_key=True)
    testimony_id = db.Column(db.Integer, db.ForeignKey("testimonies.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)


    testimony = relationship("Testimony", back_populates="likes")
    user = relationship("User", back_populates="testimony_likes")

    __table_args__ = (db.UniqueConstraint("testimony_id", "user_id", name="unique_like"),)

    def to_dict(self):
        return {
            "id": self.id,
            "created_at": self.created_at.isoformat(),
            "user_id": self.user_id
        }
        
class GroupMemberRole(Enum):  # ✅ Renamed enum
    ADMIN = "admin"
    MODERATOR = "moderator"
    MEMBER = "member"


class GroupChat(BaseModel):
    __tablename__ = "group_chats"

    name = db.Column(db.String(200), nullable=False, index=True)
    description = db.Column(db.Text)
    avatar = db.Column(db.String(500))
    is_public = db.Column(db.Boolean, default=True)
    max_members = db.Column(db.Integer, default=100)
    tags = db.Column(db.JSON, default=lambda: [])

    created_by_id = db.Column(db.BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    created_by = db.relationship('User', back_populates='group_chats_created', foreign_keys=[created_by_id])

    members = db.relationship('GroupMember', back_populates='group_chat', cascade='all, delete-orphan')
    messages = db.relationship('GroupMessage', back_populates='group_chat', cascade='all, delete-orphan')

    __table_args__ = (
        db.Index('ix_group_chats_public_created', 'is_public', 'created_at'),
    )

    @validates('name')
    def validate_name(self, key, name):
        if not 3 <= len(name) <= 200:
            raise ValueError("Group name must be between 3 and 200 characters")
        return name

    def to_dict(self, include_members=False, include_messages=False):
        data = super().to_dict()
        data.update({
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "avatar": self.avatar,
            "is_public": self.is_public,
            "max_members": self.max_members,
            "tags": self.tags,
            "created_by_id": self.created_by_id,
            "member_count": len([m for m in self.members if m.is_active]),
            "created_by": {
                "id": self.created_by.id,
                "username": self.created_by.username,
                "full_name": self.created_by.get_full_name()
            } if self.created_by else None
        })
        if include_members:
            data["members"] = [m.to_dict() for m in self.members if m.is_active]
        if include_messages:
            data["messages"] = [msg.to_dict() for msg in self.messages if msg.is_active]
        return data


class GroupMember(BaseModel):
    __tablename__ = "group_members"

    group_chat_id = db.Column(db.BigInteger, db.ForeignKey('group_chats.id', ondelete='CASCADE'), nullable=False)
    user_id = db.Column(db.BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    
    # ✅ FIXED: Use string literal instead of Enum.value
    group_role = db.Column(db.String(20), default="member", nullable=False)
    
    
    joined_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    group_chat = db.relationship('GroupChat', back_populates='members')
    user = db.relationship('User')

    __table_args__ = (
        db.UniqueConstraint('group_chat_id', 'user_id', name='uq_group_member'),
        db.Index('ix_group_members_user', 'user_id'),
        db.CheckConstraint(
            "group_role IN ('admin', 'moderator', 'member')",
            name='ck_group_member_role'
        ),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "group_chat_id": self.group_chat_id,
            "user_id": self.user_id,
            "group_role": self.group_role,  # ✅ Now it's a string directly
            "joined_at": self.joined_at.isoformat() if self.joined_at else None,
            "is_active": self.is_active,
            "user": {
                "id": self.user.id,
                "username": self.user.username,
                "full_name": self.user.get_full_name(),
                "profile_picture": self.user.profile_picture
            } if self.user else None
        }


class GroupMessage(BaseModel):
    __tablename__ = "group_messages"

    group_chat_id = db.Column(db.BigInteger, db.ForeignKey('group_chats.id', ondelete='CASCADE'), nullable=False)
    sender_id = db.Column(db.BigInteger, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    content = db.Column(db.Text, nullable=False)
    message_type = db.Column(db.String(20), default='text')
    attachments = db.Column(db.JSON, default=lambda: [])
    replied_to_id = db.Column(db.BigInteger, db.ForeignKey('group_messages.id'))
    read_by = db.Column(db.JSON, default=lambda: [])

    group_chat = db.relationship('GroupChat', back_populates='messages')
    sender = db.relationship('User')
    replied_to = db.relationship('GroupMessage', remote_side='GroupMessage.id', backref='replies')  # ✅ Fixed remote_side

    __table_args__ = (
        db.Index('ix_group_messages_group_created', 'group_chat_id', 'created_at'),
        db.Index('ix_group_messages_sender', 'sender_id'),
    )

    @validates('content')
    def validate_content(self, key, content):
        if not content or len(content.strip()) == 0:
            raise ValueError("Message content cannot be empty")
        return content.strip()

    def to_dict(self):
        return {
            "id": self.id,
            "group_chat_id": self.group_chat_id,
            "sender_id": self.sender_id,
            "content": self.content,
            "message_type": self.message_type,
            "attachments": self.attachments,
            "replied_to_id": self.replied_to_id,
            "read_by": self.read_by,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "is_active": self.is_active,
            "sender": {
                "id": self.sender.id,
                "username": self.sender.username,
                "full_name": self.sender.get_full_name(),
                "profile_picture": self.sender.profile_picture
            } if self.sender else None,
            "replied_to": {
                "id": self.replied_to.id,
                "content": self.replied_to.content
            } if self.replied_to else None
        }
        
        


from flask import current_app
import os

class WorshipSong(db.Model):
    __tablename__ = 'worship_songs'
    
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    artist = db.Column(db.String(200), nullable=False)
    video_id = db.Column(db.String(100))  # For YouTube videos
    video_url = db.Column(db.String(500))  # For uploaded videos
    audio_url = db.Column(db.String(500))  # For audio files
    thumbnail_url = db.Column(db.String(500))
    category = db.Column(db.Integer, default=0)  # 0=English, 1=African
    media_type = db.Column(db.String(20), default='youtube')  # youtube, video, audio
    lyrics = db.Column(db.Text)
    duration = db.Column(db.Integer)  # in seconds
    file_size = db.Column(db.Integer)  # in bytes (for downloads)
    allow_download = db.Column(db.Boolean, default=True)
    download_count = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'artist': self.artist,
            'videoId': self.video_id,
            'videoUrl': self._get_full_url(self.video_url),
            'audioUrl': self._get_full_url(self.audio_url),
            'thumbnailUrl': self._get_full_thumbnail_url(),
            'category': self.category,
            'mediaType': self.media_type,
            'lyrics': self.lyrics,
            'duration': self.duration,
            'fileSize': self.file_size,
            'allowDownload': self.allow_download,
            'downloadCount': self.download_count,
            'createdAt': self.created_at.isoformat() if self.created_at else datetime.utcnow().isoformat(),
        }
    
    def _get_full_url(self, url):
        """Convert relative URL to absolute URL"""
        if not url:
            return None
        
        # If already a full URL or YouTube URL, return as-is
        if url.startswith('http://') or url.startswith('https://'):
            return url
        
        # Get base URL from Flask config or use default
        base_url = current_app.config.get('BASE_URL', 'http://localhost:5000')
        
        # Ensure URL starts with /
        if not url.startswith('/'):
            url = f'/{url}'
        
        return f'{base_url}{url}'
    
    def _get_full_thumbnail_url(self):
        """Get full URL for thumbnail, with special handling for YouTube"""
        if not self.thumbnail_url:
            # Return default with full URL
            default_thumb = 'assets/images/worship_icon.jpeg'
            base_url = current_app.config.get('BASE_URL', 'http://localhost:5000')
            if not default_thumb.startswith('/'):
                default_thumb = f'/{default_thumb}'
            return f'{base_url}{default_thumb}'
        
        # YouTube thumbnail
        if self.video_id and 'youtube.com' in self.thumbnail_url:
            return self.thumbnail_url
        
        # Already full URL
        if self.thumbnail_url.startswith('http://') or self.thumbnail_url.startswith('https://'):
            return self.thumbnail_url
        
        # Relative URL - convert to absolute
        base_url = current_app.config.get('BASE_URL', 'http://localhost:5000')
        if not self.thumbnail_url.startswith('/'):
            thumb_url = f'/{self.thumbnail_url}'
        else:
            thumb_url = self.thumbnail_url
        
        return f'{base_url}{thumb_url}'
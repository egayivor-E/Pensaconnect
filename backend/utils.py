# backend/utils.py
import re
import logging
from typing import Dict, Tuple, Optional
from datetime import datetime, timedelta
from flask import request
from backend.models import User
from backend.extensions import db, limiter

logger = logging.getLogger(__name__)

# ================================
# EXISTING USER MANAGEMENT FUNCTIONS
# ================================

def create_admin_user():
    """Create an admin user if none exists"""
    admin = User.query.filter_by(role=UserRole.ADMIN).first()
    if not admin:
        admin = User(
            username='admin',
            email='admin@example.com',
            first_name='Admin',
            last_name='User',
            role=UserRole.ADMIN
        )
        admin.set_password('admin123')
        db.session.add(admin)
        db.session.commit()
        print("Admin user created:")
        print(f"Username: admin")
        print(f"Email: admin@example.com")
        print(f"Password: admin123")
    else:
        print("Admin user already exists")

def create_test_users():
    """Create test users"""
    for i in range(1, 6):
        user = User.query.filter_by(email=f'user{i}@example.com').first()
        if not user:
            user = User(
                username=f'user{i}',
                email=f'user{i}@example.com',
                first_name=f'User{i}',
                last_name='Test',
                role=UserRole.MEMBER
            )
            user.set_password('password123')
            db.session.add(user)
    
    db.session.commit()
    print("Test users created")

def cleanup_test_data():
    """Clean up test data"""
    # Be careful with this in production!
    User.query.filter(User.email.contains('@example.com')).delete()
    db.session.commit()
    print("Test data cleaned up")

# ================================
# VALIDATION FUNCTIONS
# ================================

class ValidationResult:
    """Standardized validation result"""
    def __init__(self, is_valid: bool, message: str = "", errors: Dict = None):
        self.is_valid = is_valid
        self.message = message
        self.errors = errors or {}
    
    def to_dict(self) -> Dict:
        return {
            "valid": self.is_valid,
            "message": self.message,
            "errors": self.errors
        }

# MESSAGE VALIDATION
def validate_message_content(content: str, user_id: int = None) -> ValidationResult:
    """
    Validate message content for production use
    """
    errors = {}
    
    # Required field
    if not content or len(content.strip()) == 0:
        errors["content"] = "Message cannot be empty"
        return ValidationResult(False, "Message validation failed", errors)
    
    content = content.strip()
    
    # Length validation
    max_length = 500
    if len(content) > max_length:
        errors["content"] = f"Message too long (max {max_length} characters)"
        return ValidationResult(False, "Message validation failed", errors)
    
    # Profanity filter
    profanity_result = _check_profanity(content)
    if not profanity_result.is_valid:
        errors["content"] = profanity_result.message
        return ValidationResult(False, "Message validation failed", errors)
    
    # Spam detection
    spam_result = _check_spam(content, user_id)
    if not spam_result.is_valid:
        errors["content"] = spam_result.message
        return ValidationResult(False, "Message validation failed", errors)
    
    # URL validation
    url_result = _validate_urls(content)
    if not url_result.is_valid:
        errors["content"] = url_result.message
        return ValidationResult(False, "Message validation failed", errors)
    
    return ValidationResult(True, "Message is valid")

def _check_profanity(content: str) -> ValidationResult:
    """Check for inappropriate content"""
    profanity_patterns = [
        r'\b(asshole|fuck|shit|bitch|damn|hell)\b',
        r'\b(cunt|piss|dick|pussy|whore|slut)\b',
        r'\b(retard|fag|nigger|chink|spic)\b',
    ]
    
    for pattern in profanity_patterns:
        if re.search(pattern, content, re.IGNORECASE):
            return ValidationResult(False, "Message contains inappropriate content")
    
    return ValidationResult(True)

def _check_spam(content: str, user_id: int = None) -> ValidationResult:
    """Check for spam patterns"""
    spam_patterns = [
        r'(.)\1{5,}',  # Repeated characters (aaaaaaa)
        r'[!?\.]{4,}',  # Excessive punctuation (!!!!! ??? ....)
        r'^[A-Z\s]{20,}$',  # ALL CAPS
        r'\b(free money|make money fast|click here|buy now|limited time)\b',  # Common spam phrases
        r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+',  # Multiple URLs
    ]
    
    for pattern in spam_patterns:
        if re.search(pattern, content, re.IGNORECASE):
            return ValidationResult(False, "Message appears to be spam")
    
    return ValidationResult(True)

def _validate_urls(content: str) -> ValidationResult:
    """Validate URLs in message content"""
    url_regex = r'https?://[^\s/$.?#].[^\s]*'
    urls = re.findall(url_regex, content, re.IGNORECASE)
    
    if len(urls) > 3:
        return ValidationResult(False, "Too many URLs in message")
    
    # Check for suspicious domains
    suspicious_domains = [
        'bit.ly', 'tinyurl.com', 'goo.gl', 't.co',  # URL shorteners
        '.ru', '.cn', '.tk', '.ml', '.ga',  # Suspicious TLDs
    ]
    
    for url in urls:
        try:
            from urllib.parse import urlparse
            domain = urlparse(url).netloc.lower()
            
            for suspicious in suspicious_domains:
                if suspicious in domain:
                    return ValidationResult(False, "Suspicious URL detected")
        except Exception:
            return ValidationResult(False, "Invalid URL in message")
    
    return ValidationResult(True)

# USER INPUT VALIDATION
def validate_email(email: str) -> ValidationResult:
    """Validate email address"""
    if not email or len(email.strip()) == 0:
        return ValidationResult(False, "Email is required")
    
    email = email.strip().lower()
    
    # Basic email regex
    email_regex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    if not re.match(email_regex, email):
        return ValidationResult(False, "Please enter a valid email address")
    
    # Check for disposable email domains (basic list)
    disposable_domains = [
        'tempmail.com', 'throwaway.com', 'guerrillamail.com',
        'mailinator.com', '10minutemail.com', 'yopmail.com'
    ]
    
    domain = email.split('@')[-1]
    if domain in disposable_domains:
        return ValidationResult(False, "Disposable email addresses are not allowed")
    
    return ValidationResult(True)

def validate_username(username: str) -> ValidationResult:
    """Validate username"""
    if not username or len(username.strip()) == 0:
        return ValidationResult(False, "Username is required")
    
    username = username.strip()
    
    if len(username) < 3:
        return ValidationResult(False, "Username must be at least 3 characters long")
    
    if len(username) > 30:
        return ValidationResult(False, "Username must be less than 30 characters")
    
    # Alphanumeric and underscore only
    if not re.match(r'^[a-zA-Z0-9_]+$', username):
        return ValidationResult(False, "Username can only contain letters, numbers, and underscores")
    
    # Check for reserved usernames
    reserved_usernames = [
        'admin', 'administrator', 'root', 'system', 'support',
        'help', 'contact', 'info', 'test', 'null', 'undefined'
    ]
    
    if username.lower() in reserved_usernames:
        return ValidationResult(False, "This username is reserved")
    
    return ValidationResult(True)

def validate_password(password: str) -> ValidationResult:
    """Validate password strength"""
    if not password:
        return ValidationResult(False, "Password is required")
    
    errors = {}
    
    if len(password) < 8:
        errors["length"] = "Password must be at least 8 characters long"
    
    if not re.search(r'[A-Z]', password):
        errors["uppercase"] = "Password must contain at least one uppercase letter"
    
    if not re.search(r'[a-z]', password):
        errors["lowercase"] = "Password must contain at least one lowercase letter"
    
    if not re.search(r'[0-9]', password):
        errors["number"] = "Password must contain at least one number"
    
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        errors["special"] = "Password must contain at least one special character"
    
    if errors:
        return ValidationResult(False, "Password does not meet requirements", errors)
    
    return ValidationResult(True)

def validate_name(name: str, field_name: str = "Name") -> ValidationResult:
    """Validate name fields (first name, last name)"""
    if not name or len(name.strip()) == 0:
        return ValidationResult(False, f"{field_name} is required")
    
    name = name.strip()
    
    if len(name) < 2:
        return ValidationResult(False, f"{field_name} must be at least 2 characters long")
    
    if len(name) > 50:
        return ValidationResult(False, f"{field_name} must be less than 50 characters")
    
    # Only letters, spaces, hyphens, and apostrophes
    if not re.match(r"^[a-zA-Zà-ÿÀ-Ÿ '\-]+$", name):
        return ValidationResult(False, f"{field_name} can only contain letters, spaces, hyphens, and apostrophes")
    
    return ValidationResult(True)

def validate_phone_number(phone: str) -> ValidationResult:
    """Validate phone number (optional)"""
    if not phone or len(phone.strip()) == 0:
        return ValidationResult(True)  # Phone is optional
    
    phone = re.sub(r'[\s\-\(\)]', '', phone.strip())
    
    # Basic international phone validation
    if not re.match(r'^\+?[0-9]{10,15}$', phone):
        return ValidationResult(False, "Please enter a valid phone number")
    
    return ValidationResult(True)

# FORM VALIDATION
def validate_user_registration(data: Dict) -> ValidationResult:
    """Validate complete user registration form"""
    errors = {}
    
    # Email
    email_result = validate_email(data.get('email', ''))
    if not email_result.is_valid:
        errors['email'] = email_result.message
    
    # Username
    username_result = validate_username(data.get('username', ''))
    if not username_result.is_valid:
        errors['username'] = username_result.message
    
    # Password
    password_result = validate_password(data.get('password', ''))
    if not password_result.is_valid:
        errors.update(password_result.errors)
    
    # First name
    first_name_result = validate_name(data.get('first_name', ''), "First name")
    if not first_name_result.is_valid:
        errors['first_name'] = first_name_result.message
    
    # Last name
    last_name_result = validate_name(data.get('last_name', ''), "Last name")
    if not last_name_result.is_valid:
        errors['last_name'] = last_name_result.message
    
    # Phone (optional)
    phone_result = validate_phone_number(data.get('phone', ''))
    if not phone_result.is_valid:
        errors['phone'] = phone_result.message
    
    if errors:
        return ValidationResult(False, "Registration validation failed", errors)
    
    return ValidationResult(True, "All fields are valid")

def validate_user_profile_update(data: Dict) -> ValidationResult:
    """Validate user profile update data"""
    errors = {}
    
    if 'email' in data:
        email_result = validate_email(data['email'])
        if not email_result.is_valid:
            errors['email'] = email_result.message
    
    if 'username' in data:
        username_result = validate_username(data['username'])
        if not username_result.is_valid:
            errors['username'] = username_result.message
    
    if 'first_name' in data:
        first_name_result = validate_name(data['first_name'], "First name")
        if not first_name_result.is_valid:
            errors['first_name'] = first_name_result.message
    
    if 'last_name' in data:
        last_name_result = validate_name(data['last_name'], "Last name")
        if not last_name_result.is_valid:
            errors['last_name'] = last_name_result.message
    
    if 'phone' in data:
        phone_result = validate_phone_number(data['phone'])
        if not phone_result.is_valid:
            errors['phone'] = phone_result.message
    
    if errors:
        return ValidationResult(False, "Profile update validation failed", errors)
    
    return ValidationResult(True, "Profile data is valid")

# RATE LIMITING UTILITIES
def is_rate_limited(user_id: int, action: str, window_seconds: int = 60, max_requests: int = 10) -> bool:
    """
    Basic rate limiting check
    In production, use Redis for distributed rate limiting
    """
    # TODO: Implement proper Redis-based rate limiting
    # For now, this is a placeholder
    return False

def get_client_identifier() -> str:
    """Get unique identifier for rate limiting"""
    if request:
        return request.remote_addr or 'unknown'
    return 'unknown'

# FILE VALIDATION
def validate_image_file(filename: str, content_type: str, max_size_mb: int = 10) -> ValidationResult:
    """Validate uploaded image file"""
    allowed_extensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'}
    allowed_mime_types = {
        'image/jpeg', 'image/jpg', 'image/png', 
        'image/gif', 'image/webp'
    }
    
    errors = {}
    
    # Check extension
    if not ('.' in filename and 
            filename.rsplit('.', 1)[1].lower() in allowed_extensions):
        errors['extension'] = f"File type not allowed. Allowed types: {', '.join(allowed_extensions)}"
    
    # Check MIME type
    if content_type not in allowed_mime_types:
        errors['mime_type'] = f"File type not allowed. Allowed types: {', '.join(allowed_mime_types)}"
    
    # Check file size (placeholder - actual size check should be done when reading the file)
    if max_size_mb > 50:  # Sanity check
        errors['size'] = "File size limit too high"
    
    if errors:
        return ValidationResult(False, "File validation failed", errors)
    
    return ValidationResult(True, "File is valid")

# ================================
# UTILITY FUNCTIONS
# ================================

def sanitize_input(text: str) -> str:
    """Basic input sanitization"""
    if not text:
        return ""
    
    # Remove potentially dangerous characters
    text = re.sub(r'[<>]', '', text)
    
    # Trim whitespace
    text = text.strip()
    
    return text

def format_validation_errors(validation_result: ValidationResult) -> Dict:
    """Format validation errors for API response"""
    return {
        "status": "error",
        "message": validation_result.message,
        "errors": validation_result.errors
    }
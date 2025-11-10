# backend/utils.py
from backend.models import User, UserRole
from backend.extensions import db

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
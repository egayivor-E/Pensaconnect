from backend.extensions import celery
import time

@celery.task
def add_numbers(a, b):
    """Simple demo task to test Celery workers"""
    time.sleep(2)  # simulate work
    return a + b


@celery.task
def send_welcome_email(user_email):
    """Fake email sender for demo"""
    # In real life, integrate with Flask-Mail or an external provider
    print(f"📧 Sending welcome email to {user_email}...")
    time.sleep(3)
    return f"Welcome email sent to {user_email}"

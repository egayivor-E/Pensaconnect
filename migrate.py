import os

from flask_migrate import upgrade
from backend import create_app


os.environ['FLASK_ENV'] = 'production'

app = create_app('render')

with app.app_context():
    print("Running database migrations...")
    upgrade()
    print("Database migrations completed successfully.")

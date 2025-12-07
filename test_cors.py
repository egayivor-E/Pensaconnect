import os
os.environ['RENDER'] = 'true'

from backend import create_app
app = create_app('render')

# Check CORS config
print(f"CORS origins: {app.config.get('CORS_ORIGINS', 'Not set')}")

# Check a route
with app.test_client() as client:
    response = client.get('/health')
    print(f'Health check: {response.status_code}')
# test_render_final.py
import os

# Simulate Render environment
os.environ['RENDER'] = 'true'
os.environ['DATABASE_URL'] = 'postgres://user:pass@host/dbname'  # Fake URL for testing

print("🧪 Final Render Test (with fake PostgreSQL URL)")
print("=" * 50)

try:
    from backend import create_app
    app = create_app('render')
    
    print(f"✅ App created successfully")
    print(f"   ENV: {app.config.get('ENV')}")
    print(f"   DEBUG: {app.config.get('DEBUG')}")
    
    # Check database URL was converted
    db_uri = app.config.get('SQLALCHEMY_DATABASE_URI', '')
    print(f"   Database URI: {db_uri[:60]}...")
    
    # Test health endpoint
    with app.test_client() as client:
        response = client.get('/health')
        print(f"✅ Health endpoint: {response.status_code}")
    
    print("\n🎉 READY FOR DEPLOYMENT!")
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
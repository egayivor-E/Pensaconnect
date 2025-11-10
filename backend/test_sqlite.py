import sqlite3
import os

def test_sqlite():
    print("Testing SQLite database creation...")
    
    # Test 1: Create in instance folder
    try:
        conn = sqlite3.connect('instance/test.db')
        print("✅ Success: instance/test.db")
        conn.close()
        os.remove('instance/test.db')
    except Exception as e:
        print(f"❌ Failed instance/test.db: {e}")
    
    # Test 2: Create in current directory
    try:
        conn = sqlite3.connect('test.db')
        print("✅ Success: test.db")
        conn.close()
        os.remove('test.db')
    except Exception as e:
        print(f"❌ Failed test.db: {e}")
    
    # Test 3: Check instance folder permissions
    try:
        with open('instance/test_write.txt', 'w') as f:
            f.write('test')
        print("✅ Success: instance folder writable")
        os.remove('instance/test_write.txt')
    except Exception as e:
        print(f"❌ Failed instance folder write: {e}")

if __name__ == '__main__':
    test_sqlite()
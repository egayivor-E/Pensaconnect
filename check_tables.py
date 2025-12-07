# check_tables.py
import sqlite3
import os
from pathlib import Path

def check_tables():
    # Try different possible database locations
    possible_paths = [
        'app.db',
        'instance/app.db', 
        '../app.db',
        '../instance/app.db'
    ]
    
    db_path = None
    for path in possible_paths:
        if os.path.exists(path):
            db_path = path
            break
    
    if not db_path:
        print("❌ No database file found. Looking for:")
        for path in possible_paths:
            print(f"   - {path}")
        return
    
    print(f"📁 Database found: {db_path}")
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get all tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = cursor.fetchall()
    
    print("\n📋 Tables in database:")
    for table in tables:
        print(f"  - {table[0]}")
    
    # Check if worship_songs exists
    worship_songs_exists = any('worship_songs' in table[0] for table in tables)
    if worship_songs_exists:
        print("\n✅ worship_songs table exists!")
    else:
        print("\n❌ worship_songs table NOT found")
    
    conn.close()

if __name__ == "__main__":
    check_tables()
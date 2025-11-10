# scripts/setup_database.py
import psycopg2
from psycopg2 import sql
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def create_database(db_name, user="postgres", password="jesus%40save", host="localhost", port=5432):
    """Create PostgreSQL database if it doesn't exist"""
    try:
        # Connect to default postgres database
        conn = psycopg2.connect(
            host=host,
            database="postgres",
            user=user,
            password=jesus@save, # type: ignore
            port=port
        )
        conn.autocommit = True
        cursor = conn.cursor()
        
        # Check if database exists
        cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
        exists = cursor.fetchone()
        
        if not exists:
            cursor.execute(sql.SQL("CREATE DATABASE {}").format(
                sql.Identifier(db_name)
            ))
            print(f"✅ Database '{db_name}' created successfully")
        else:
            print(f"✅ Database '{db_name}' already exists")
            
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Error creating database '{db_name}': {e}")

def setup_all_databases():
    """Create all required databases"""
    databases = [
        "pensaconnect_dev",
        "pensaconnect_test", 
        "pensaconnect_prod"
    ]
    
    for db_name in databases:
        create_database(db_name)

if __name__ == "__main__":
    setup_all_databases()
# find_all_remaining_commas.py
import re

def find_all_remaining_commas():
    with open('backend/models.py', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    print("🔍 Finding ALL remaining trailing commas...")
    
    for i, line in enumerate(lines, 1):
        # Look for any line with comma before closing parenthesis
        if re.search(r',\s*\)', line):
            print(f"❌ Line {i}: {line.strip()}")
    
    print("\n🔍 Checking specific problematic patterns...")
    
    # Check for these specific patterns
    patterns_to_check = [
        'lazy="joined"',
        'lazy=True',
        'passive_deletes=True,',
        'cascade=',
    ]
    
    for pattern in patterns_to_check:
        for i, line in enumerate(lines, 1):
            if pattern in line and 'relationship' in line:
                print(f"⚠️  Line {i} has {pattern}: {line.strip()}")

if __name__ == "__main__":
    find_all_remaining_commas()
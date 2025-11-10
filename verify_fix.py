# verify_fix.py
def verify_fix():
    with open('backend/models.py', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if we have the correct syntax
    correct_pattern = r'__table_args__ = \(db\.UniqueConstraint\("testimony_id", "user_id", name="unique_like"\),\)'
    
    if re.search(correct_pattern, content):
        print("✅ __table_args__ syntax is correct")
    else:
        print("❌ __table_args__ syntax is still wrong")
        # Show what we actually have
        import re
        wrong_pattern = r'__table_args__ = \(.*?\)'
        match = re.search(wrong_pattern, content)
        if match:
            print(f"Current __table_args__: {match.group()}")

if __name__ == "__main__":
    verify_fix()
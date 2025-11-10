# fix_final_comma.py
def fix_final_comma():
    with open('backend/models.py', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Fix line 1283 (0-indexed, so line 1282)
    if len(lines) > 1282:
        line_1283 = lines[1282]  # This is actually line 1283 in the file (1-indexed)
        if 'db.UniqueConstraint("testimony_id", "user_id", name="unique_like"),)' in line_1283:
            lines[1282] = line_1283.replace('),)', '))')
            print("✅ Fixed the trailing comma on line 1283")
        else:
            print(f"❌ Line 1283 doesn't match expected pattern: {line_1283.strip()}")
    else:
        print("❌ File doesn't have enough lines")
    
    with open('backend/models.py', 'w', encoding='utf-8') as f:
        f.writelines(lines)

if __name__ == "__main__":
    fix_final_comma()
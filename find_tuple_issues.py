# find_tuple_issues.py
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

def find_tuple_problems():
    """Simply scan the models.py file for tuple patterns"""
    
    models_file = os.path.join('backend', 'models.py')
    
    if not os.path.exists(models_file):
        print(f"❌ models.py not found at {models_file}")
        return
    
    print("🔍 Scanning models.py for tuple patterns...")
    
    with open(models_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    problematic_patterns = []
    
    for i, line in enumerate(lines, 1):
        line = line.strip()
        
        # Look for problematic patterns
        if 'lazy="joined"' in line and 'relationship' in line:
            problematic_patterns.append(f"Line {i}: {line}")
        
        if '= (' in line and 'relationship' in line:
            problematic_patterns.append(f"Line {i}: {line}")
            
        if 'backref=' in line and '(' in line and ')' in line:
            problematic_patterns.append(f"Line {i}: {line}")
            
        if 'back_populates=' in line and '(' in line and ')' in line:
            problematic_patterns.append(f"Line {i}: {line}")
    
    if problematic_patterns:
        print("❌ Found potentially problematic lines:")
        for pattern in problematic_patterns:
            print(f"  {pattern}")
    else:
        print("✅ No obvious tuple patterns found in relationships")
    
    # Also check for specific known issues
    print("\n🔍 Checking for specific known issues...")
    
    # Look for the specific lines we identified earlier
    known_issues = [
        'event_type = db.relationship("EventType", lazy="joined")',
        'resource_type = db.relationship("ResourceType", lazy="joined")', 
        'notification_type = db.relationship("NotificationType", lazy="joined")'
    ]
    
    for issue in known_issues:
        for i, line in enumerate(lines, 1):
            if issue in line:
                print(f"❌ Known issue at line {i}: {line.strip()}")
                break

if __name__ == "__main__":
    find_tuple_problems()
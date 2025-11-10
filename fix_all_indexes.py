# fix_all_indexes.py
import re

# Read the models.py file
with open('backend/models.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove all problematic indexes from Donation class
donation_class_content = re.search(
    r'class Donation\(BaseModel\):.*?__table_args__ = \((.*?)\)', 
    content, 
    re.DOTALL
)

if donation_class_content:
    indexes_to_remove = [
        "Index('ix_donations_email', 'email')",
        "Index('ix_donations_start_time', 'start_time')",
        "Index('ix_donations_blockchain', 'blockchain_hash', 'created_at')",
        # Add any other problematic indexes here
    ]
    
    for index in indexes_to_remove:
        content = content.replace(index, '')
    
    print("Removed problematic indexes from Donation class")

# Also check for other models with similar issues
# Remove any index that references non-existent columns
content = re.sub(
    r"Index\('.*(email|start_time|blockchain_hash).*'\)", 
    '', 
    content
)

# Write the fixed content back
with open('backend/models.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("All problematic indexes removed!")
# fix_lazy_parameters.py
def fix_lazy_parameters():
    with open('backend/models.py', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Fix the specific problematic lines
    fixes = {
        # Fix the trailing comma in TestimonyLike
        '__table_args__ = (db.UniqueConstraint("testimony_id", "user_id", name="unique_like"),)': 
        '__table_args__ = (db.UniqueConstraint("testimony_id", "user_id", name="unique_like"),)',
        
        # Fix lazy="joined" - remove the lazy parameter entirely
        'status = relationship("PrayerStatus", back_populates="prayer_requests", lazy="joined")': 
        'status = relationship("PrayerStatus", back_populates="prayer_requests")',
        
        # Fix lazy=True in testimony relationships - remove lazy parameter
        'testimonies = relationship("Testimony", back_populates="user", lazy=True)': 
        'testimonies = relationship("Testimony", back_populates="user")',
        
        'testimony_comments = relationship("TestimonyComment", back_populates="user", lazy=True)': 
        'testimony_comments = relationship("TestimonyComment", back_populates="user")',
        
        'testimony_likes = relationship("TestimonyLike", back_populates="user", lazy=True)': 
        'testimony_likes = relationship("TestimonyLike", back_populates="user")'
    }
    
    fixed_content = content
    for wrong, correct in fixes.items():
        fixed_content = fixed_content.replace(wrong, correct)
    
    with open('backend/models.py', 'w', encoding='utf-8') as f:
        f.write(fixed_content)
    
    print("✅ Fixed lazy parameters and remaining trailing comma")

if __name__ == "__main__":
    fix_lazy_parameters()
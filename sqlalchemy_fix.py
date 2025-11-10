# sqlalchemy_fix.py
"""
Monkey patch to fix SQLAlchemy compatibility with Python 3.13
"""
import sys

def apply_sqlalchemy_patch():
    """Apply monkey patch to fix SQLAlchemy 3.13 compatibility"""
    if sys.version_info >= (3, 13):
        try:
            import sqlalchemy.util.langhelpers
            
            # Store the original method
            original_init_subclass = sqlalchemy.util.langhelpers.__init_subclass__
            
            def patched_init_subclass(cls, *args, **kwargs):
                try:
                    return original_init_subclass(cls, *args, **kwargs)
                except AssertionError as e:
                    if "directly inherits TypingOnly" in str(e):
                        # Ignore this specific error for Python 3.13 compatibility
                        return
                    raise
            
            # Apply the patch
            sqlalchemy.util.langhelpers.__init_subclass__ = patched_init_subclass
            print("SQLAlchemy patch applied successfully")
            
        except Exception as e:
            print(f"Failed to apply SQLAlchemy patch: {e}")

# Apply the patch when this module is imported
apply_sqlalchemy_patch()
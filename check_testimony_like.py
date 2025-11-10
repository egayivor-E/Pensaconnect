# check_testimony_like.py
def check_testimony_like():
    with open('backend/models.py', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Find the TestimonyLike class
    in_testimony_like = False
    for i, line in enumerate(lines, 1):
        if 'class TestimonyLike' in line:
            in_testimony_like = True
            print(f"Found TestimonyLike class at line {i}")
        elif in_testimony_like and line.strip().startswith('class '):
            break
        elif in_testimony_like and '__table_args__' in line:
            print(f"Line {i}: {line.strip()}")
            # Show the next few lines for context
            for j in range(i, min(i+5, len(lines))):
                print(f"Line {j}: {lines[j-1].strip()}")

if __name__ == "__main__":
    check_testimony_like()
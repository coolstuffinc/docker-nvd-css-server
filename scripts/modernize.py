import re
import sys

def modernize(content):
    # Fix old String syntax: new String:name[size] -> char name[size]
    content = re.sub(r'new String:([a-zA-Z0-9_]+)\[([0-9]+)\]', r'char \1[\2]', content)
    # Fix old bool syntax: new bool:name = ... -> bool name = ...
    content = re.sub(r'new bool:([a-zA-Z0-9_]+)', r'bool \1', content)
    # Fix old int syntax
    content = re.sub(r'new ([a-zA-Z0-9_]+):', r'int \1:', content)
    # Convert old callback prototypes
    content = re.sub(r'public OnPluginStart\(\)', r'public void OnPluginStart()', content)
    content = re.sub(r'public OnMapStart\(\)', r'public void OnMapStart()', content)
    # Replace common deprecated syntax
    content = content.replace('new Handle:', 'Handle ')
    content = content.replace('INVALID_HANDLE', 'null')
    return content

if __name__ == "__main__":
    with open(sys.argv[1], 'r') as f:
        data = f.read()
    print(modernize(data))

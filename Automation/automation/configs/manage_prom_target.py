#!/usr/bin/env python3
import sys, re
from pathlib import Path

# Usage: python3 manage_prom_target.py <path_to_yml> <job_name> <target_ip:port> <action>
# Action: add | remove

if len(sys.argv) < 5:
    print("USAGE: manage_prom_target.py <prometheus.yml> <job_name> <target> <add|remove>")
    sys.exit(2)

yml_path = Path(sys.argv[1])
job_name = sys.argv[2]
target = sys.argv[3].strip()
action = sys.argv[4].lower()

if not yml_path.exists():
    print(f"ERROR: File not found: {yml_path}")
    sys.exit(3)

text = yml_path.read_text()
lines = text.splitlines()

def indent_len(s):
    return len(s) - len(s.lstrip(' '))

# 1. Tim vi tri cua Job
start_idx = None
job_regex = re.compile(rf'^\s*-\s*job_name:\s*[\'"]?{re.escape(job_name)}[\'"]?\s*$')

for idx, line in enumerate(lines):
    if job_regex.match(line):
        start_idx = idx
        break

# --- LOGIC REMOVE ---
if action == 'remove':
    if start_idx is None:
        print("JOB_NOT_FOUND")
        sys.exit(0)
    
    start_indent = indent_len(lines[start_idx])
    end_idx = len(lines)
    for j in range(start_idx + 1, len(lines)):
        if re.match(r'^\s*-\s*job_name:', lines[j]) and indent_len(lines[j]) == start_indent:
            end_idx = j
            break
            
    new_lines = []
    removed = False
    
    for i in range(len(lines)):
        if i < start_idx or i >= end_idx:
            new_lines.append(lines[i])
        else:
            if target in lines[i] and re.search(r'^\s*-\s*[\'"]?'+re.escape(target), lines[i]):
                removed = True
                continue 
            new_lines.append(lines[i])

    if removed:
        yml_path.write_text("\n".join(new_lines) + "\n")
        print("REMOVED")
    else:
        print("TARGET_NOT_FOUND")
    sys.exit(0)

# --- LOGIC ADD ---
elif action == 'add':
    # Neu chua co job, tao moi
    if start_idx is None:
        new_block = [
            f'  - job_name: "{job_name}"',
            '    static_configs:',
            '      - targets:',
            f'        - "{target}"'
        ]
        if any(l.strip().startswith('scrape_configs:') for l in lines):
            for idx, line in enumerate(lines):
                if line.strip().startswith('scrape_configs:'):
                    lines[idx+1:idx+1] = new_block
                    break
        else:
            lines.append('scrape_configs:')
            lines.extend(new_block)
        
        yml_path.write_text("\n".join(lines) + "\n")
        print("CREATED_JOB_AND_ADDED")
        sys.exit(0)

    start_indent = indent_len(lines[start_idx])
    end_idx = len(lines)
    for j in range(start_idx + 1, len(lines)):
        if re.match(r'^\s*-\s*job_name:', lines[j]) and indent_len(lines[j]) == start_indent:
            end_idx = j
            break

    idx_targets = None
    for k in range(start_idx, end_idx):
        if re.search(r'\btargets:\s*$', lines[k]):
            idx_targets = k
            break
    
    if idx_targets is None:
        sc_indent = start_indent + 2
        new_block = [
            ' ' * sc_indent + 'static_configs:',
            ' ' * (sc_indent + 2) + '- targets:',
            ' ' * (sc_indent + 4) + f'- "{target}"'
        ]
        lines[end_idx:end_idx] = new_block
        yml_path.write_text("\n".join(lines) + "\n")
        print("ADDED_NEW_TARGET_BLOCK")
        sys.exit(0)

    indent_targets_line = indent_len(lines[idx_targets])
    j = idx_targets + 1
    existing = []
    last_target_index = None
    
    while j < end_idx:
        if lines[j].strip() == '':
            j += 1
            continue
        if indent_len(lines[j]) <= indent_targets_line:
            break
        m = re.match(r'^\s*-\s*"?(.*?)"?\s*$', lines[j])
        if m:
            existing.append(m.group(1))
            last_target_index = j
        j += 1

    if target in existing:
        print("EXISTS")
        sys.exit(0)

    if last_target_index is not None:
        insert_idx = last_target_index + 1
        target_indent = indent_len(lines[last_target_index])
    else:
        insert_idx = idx_targets + 1
        target_indent = indent_targets_line + 2

    lines.insert(insert_idx, ' ' * target_indent + f'- "{target}"')
    yml_path.write_text("\n".join(lines) + "\n")
    print("ADDED")
    sys.exit(0)

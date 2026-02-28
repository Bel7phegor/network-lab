#!/usr/bin/env python3
import sys, re
from pathlib import Path

if len(sys.argv) < 3:
    print("USAGE: remove_prom_target.py <prometheus.yml> <target>")
    sys.exit(2)

path = Path(sys.argv[1])
target = sys.argv[2].strip()
if not path.exists():
    print("ERROR: file not found")
    sys.exit(3)

text = path.read_text()
lines = text.splitlines()

def indent_len(s):
    return len(s) - len(s.lstrip(' '))

start_idx = None
for idx, line in enumerate(lines):
    if re.match(r'^\s*-\s*job_name:\s*[\'"]?web-server[\'"]?\s*$', line):
        start_idx = idx
        break

if start_idx is None:
    print("NOTFOUND")
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
    print("NOTFOUND")
    sys.exit(0)

indent_targets_line = indent_len(lines[idx_targets])
j = idx_targets + 1
new_lines = []
removed = False

while j < end_idx:
    if indent_len(lines[j]) <= indent_targets_line:
        break
    m = re.match(r'^\s*-\s*"?(.*?)"?\s*$', lines[j])
    if m and m.group(1) == target:
        removed = True
        j += 1
        continue
    new_lines.append(lines[j])
    j += 1

if removed:
    before = lines[:idx_targets + 1]
    after = lines[j:]
    path.write_text("\n".join(before + new_lines + after) + "\n")
    print("REMOVED")
else:
    print("NOTFOUND")


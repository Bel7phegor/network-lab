#!/usr/bin/env python3
import sys, re
from pathlib import Path

if len(sys.argv) < 3:
	print("USAGE: add_prom_target.py <prometheus.yml> <target>")
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
	new_block = [
		'  - job_name: "web-server"',
		'    static_configs:',
		'      - targets:',
		f'        - "{target}"'
	]
	if any(l.strip().startswith('scrape_configs:') for l in lines):
		for idx, line in enumerate(lines):
			if line.strip().startswith('scrape_configs:'):
				insert_at = idx + 1
				lines[insert_at:insert_at] = new_block
				break
	else:
		lines.append('scrape_configs:')
		lines.extend(new_block)
	path.write_text("\n".join(lines) + "\n")
	print("ADDED")
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
	path.write_text("\n".join(lines) + "\n")
	print("ADDED")
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
path.write_text("\n".join(lines) + "\n")
print("ADDED")
sys.exit(0)

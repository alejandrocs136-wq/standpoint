import glob, json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_GLOB = os.path.join(ROOT, 'data', '*.txt')
APP_PATH = os.path.join(ROOT, 'index.html')
# Reads DATA_GLOB rows "ST|name|div|conf|url[|level]" and injects a compact NATIONAL array into the app.
rows, seen = [], set()
for f in sorted(glob.glob(DATA_GLOB)):
    for line in open(f, encoding='utf-8'):
        parts = [x.strip() for x in line.rstrip('\n').split('|')]
        if len(parts) < 4 or not parts[0] or not parts[1]:
            continue
        st, name, div, conf = parts[0], parts[1], parts[2], parts[3]
        url = parts[4] if len(parts) > 4 else ''
        if st in ('TX', 'OK'):
            continue  # Texas and Oklahoma have hand-built entries with coaches and cities
        url = re.sub(r'^(https?:)?//', '', url).rstrip('/')
        url = re.sub(r'^www\.', '', url, flags=re.I)
        url = re.sub(r'/(landing/index|index\.aspx|index\.html)$', '', url)
        if url.lower() == 'null':
            url = ''
        key = (st, name.lower())
        if key in seen:
            continue
        seen.add(key)
        rows.append([st, name, div, conf, url])
rows.sort(key=lambda r: (r[0], r[1]))
js = '/*NATIONAL_START*/var NATIONAL = ' + json.dumps(rows, ensure_ascii=False, separators=(',', ':')) + ';/*NATIONAL_END*/'
p = APP_PATH
h = open(p, encoding='utf-8').read()
if '/*NATIONAL_START*/' in h:
    h = re.sub(r'/\*NATIONAL_START\*/.*?/\*NATIONAL_END\*/', lambda m: js, h, flags=re.S)
else:
    h = h.replace('  var SCHOOLS = [', '  ' + js + '\n  var SCHOOLS = [', 1)
open(p, 'w', encoding='utf-8').write(h)
from collections import Counter
print(len(rows), 'rows;', dict(Counter(r[2] for r in rows)), 'states:', len(set(r[0] for r in rows)))

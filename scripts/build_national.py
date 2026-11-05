import glob, json, re, os
# Reads data/*.txt rows "ST|name|div|conf|url[|city]" (baseball) and data/softball/*.txt (softball)
# and injects compact NATIONAL and SOFTBALL arrays into the app. ST may be a postal code or a full state name.
# div is I, II, III, NAIA or JUCO.
ROOT = os.environ.get('SP_ROOT', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APP = os.environ.get('SP_APP', os.path.join(ROOT, 'public', 'index.html'))
STATES = {'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR', 'California': 'CA', 'Colorado': 'CO', 'Connecticut': 'CT',
          'Delaware': 'DE', 'District of Columbia': 'DC', 'Florida': 'FL', 'Georgia': 'GA', 'Hawaii': 'HI', 'Idaho': 'ID', 'Illinois': 'IL',
          'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS', 'Kentucky': 'KY', 'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD',
          'Massachusetts': 'MA', 'Michigan': 'MI', 'Minnesota': 'MN', 'Mississippi': 'MS', 'Missouri': 'MO', 'Montana': 'MT',
          'Nebraska': 'NE', 'Nevada': 'NV', 'New Hampshire': 'NH', 'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY',
          'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH', 'Oklahoma': 'OK', 'Oregon': 'OR', 'Pennsylvania': 'PA',
          'Rhode Island': 'RI', 'South Carolina': 'SC', 'South Dakota': 'SD', 'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT',
          'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA', 'West Virginia': 'WV', 'Wisconsin': 'WI', 'Wyoming': 'WY'}


def clean_url(url):
    url = re.sub(r'^(https?:)?//', '', url).rstrip('/')
    url = re.sub(r'^www\.', '', url, flags=re.I)
    url = re.sub(r'/(landing/index|index\.aspx|index\.html)$', '', url)
    return '' if url.lower() == 'null' else url


def read(pattern, skip_tx_ok):
    rows, seen = [], set()
    for f in sorted(glob.glob(pattern)):
        for line in open(f, encoding='utf-8'):
            parts = [x.strip() for x in line.rstrip('\n').split('|')]
            if len(parts) < 4 or not parts[0] or not parts[1]:
                continue
            st = STATES.get(parts[0], parts[0])
            name, div, conf = parts[1], parts[2], parts[3]
            url = clean_url(parts[4]) if len(parts) > 4 else ''
            city = parts[5] if len(parts) > 5 else ''
            if skip_tx_ok and st in ('TX', 'OK'):
                continue  # Texas and Oklahoma baseball have hand-built entries with coaches and cities
            key = (st, re.sub(r'[^a-z0-9]', '', name.lower()))
            if key in seen:
                continue
            seen.add(key)
            row = [st, name, div, conf, url]
            if city:
                row.append(city)
            rows.append(row)
    rows.sort(key=lambda r: (r[0], r[1]))
    return rows


def inject(h, tag, var, rows, anchor):
    js = '/*%s_START*/var %s = ' % (tag, var) + json.dumps(rows, ensure_ascii=False, separators=(',', ':')) + ';/*%s_END*/' % tag
    if '/*%s_START*/' % tag in h:
        return re.sub(r'/\*%s_START\*/.*?/\*%s_END\*/' % (tag, tag), lambda m: js, h, flags=re.S)
    return h.replace(anchor, '  ' + js + '\n' + anchor, 1)


base = read(ROOT + '/data/*.txt', True)
soft = read(ROOT + '/data/softball/*.txt', False)
h = open(APP, encoding='utf-8').read()
h = inject(h, 'NATIONAL', 'NATIONAL', base, '  var SCHOOLS = [')
h = inject(h, 'SOFTBALL', 'SOFTBALL', soft, '  var SCHOOLS = [')
open(APP, 'w', encoding='utf-8').write(h)
from collections import Counter
print('baseball:', len(base), 'rows;', dict(Counter(r[2] for r in base)), 'states:', len(set(r[0] for r in base)))
print('softball:', len(soft), 'rows;', dict(Counter(r[2] for r in soft)), 'states:', sorted(set(r[0] for r in soft)))

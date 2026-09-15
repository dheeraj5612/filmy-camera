#!/usr/bin/env python3
"""Re-read Film Recipes tables with their abbreviated camera-menu labels."""
import json
import re
from pathlib import Path
import hashlib
import time
from bs4 import BeautifulSoup
import collect_public_settings as collector

collector.KEYS += ("Col. Chr. Effect", "Col. Chr. Blue", "EV Comp.", "Grain", "B&W Adjustment")
collector.PATTERN = re.compile(r"(?<!\w)(" + "|".join(re.escape(k) for k in sorted(collector.KEYS, key=len, reverse=True)) + r")\s*:\s*", re.I)
p = Path('/tmp/research/public-settings-staging.json')
data = json.loads(p.read_text())
fetch = collector.Fetcher(1.0)
accepted = []
for index, record in enumerate(data['records']):
    if 'film.recipes/' not in record['url']:
        accepted.append(record)
        continue
    try:
        payload = fetch.get(record['url'])
        root = BeautifulSoup(payload, 'html.parser').select_one('.entry-content')
        blocks = collector.setting_blocks(root)
        if len(blocks) != 1:
            raise ValueError('Ambiguous repaired settings block')
        record.update(settings=blocks[0], sourceSHA256=hashlib.sha256(payload).hexdigest(),
                      retrievedOn=time.strftime('%Y-%m-%d', time.gmtime()))
        accepted.append(record)
    except Exception as error:
        data['failures'].append({'url':record['url'], 'reason':str(error)})
    if index % 20 == 0:
        print(f'Rechecked {index}; accepted {len(accepted)}', flush=True)
data['records'] = accepted
p.write_text(json.dumps(data, ensure_ascii=False, indent=2))
print(f"Repaired {len(accepted)} records", flush=True)

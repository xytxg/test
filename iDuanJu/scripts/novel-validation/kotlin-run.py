"""Run the production Kotlin source engine against the supplied collection, in bounded JVMs."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import sys

classpath, bundle, output = map(Path, sys.argv[1:4])
sources = json.loads(bundle.read_text('utf-8-sig'))
names = {'猫扑中文', '七猫小说', '番茄小说', '书旗小说', '八月文学', '鸟书网', '飘天文学', '望书阁网', '乐读小说'}

def check(pair):
    i, source = pair
    if source.get('bookSourceType', 0) != 0 or 'H' in source.get('bookSourceGroup', ''):
        return {'index': i, 'status': 'skipped-non-target'}
    mode = 'live' if source.get('bookSourceName') in names else 'categories'
    try:
        p = subprocess.run(['java', '-Xmx192m', '-cp', classpath.read_text(), 'app.iduanju.core.NovelCollectionProbe', str(bundle.resolve()), str(i), mode], capture_output=True, text=True, encoding='utf8', errors='replace', timeout=90 if mode == 'live' else 28)
        if p.returncode:
            return {'index': i, 'name': source.get('bookSourceName'), 'status': 'engine-failed', 'exitCode': p.returncode}
        return json.loads(p.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {'index': i, 'name': source.get('bookSourceName'), 'status': 'timeout', 'mode': mode}
    except (ValueError, IndexError):
        return {'index': i, 'name': source.get('bookSourceName'), 'status': 'invalid-report'}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(check, enumerate(sources)))
output.write_text(json.dumps({'bundle_sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(), 'source_count': len(sources), 'results': results}, ensure_ascii=False, indent=2), 'utf8')
print('Report written:', output)

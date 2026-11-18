"""Bounded real-source checks; reports metadata/counts only, not chapter text or credentials."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.request import Request, urlopen

binary, out_dir = sys.argv[1:3]
out = Path(out_dir)
out.mkdir(parents=True, exist_ok=True)
bundle = out / '1335.private.json'
if not bundle.exists():
    req = Request('https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json', headers={'User-Agent': 'Mozilla/5.0'})
    with urlopen(req, timeout=45) as response:
        bundle.write_bytes(response.read(8 * 1024 * 1024))
sources = json.loads(bundle.read_text('utf-8-sig'))
names = {'猫扑中文', '七猫小说', '番茄小说', '书旗小说', '八月文学', '鸟书网', '飘天文学', '望书阁网', '全本小说', '乐读小说'}

def check(pair):
    i, source = pair
    # Read only ordinary text sources; imported scripts remain untrusted.
    group = source.get('bookSourceGroup', '')
    if source.get('bookSourceType', 0) != 0 or 'H' in group or '直播' in group:
        return {'index': i, 'name': source.get('bookSourceName'), 'status': 'skipped-non-target'}
    mode = 'live' if source.get('bookSourceName') in names else 'categories'
    try:
        p = subprocess.run([binary, str(bundle.resolve()), str(i), mode], capture_output=True, text=True, timeout=85 if mode == 'live' else 25)
        if p.returncode:
            return {'index': i, 'name': source.get('bookSourceName'), 'status': 'engine-failed', 'exitCode': p.returncode}
        return json.loads(p.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {'index': i, 'name': source.get('bookSourceName'), 'status': 'timeout', 'mode': mode}
    except (ValueError, IndexError):
        return {'index': i, 'name': source.get('bookSourceName'), 'status': 'invalid-report'}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(check, enumerate(sources)))
(out / 'report.json').write_text(json.dumps({'bundle_sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(), 'source_count': len(sources), 'results': results}, ensure_ascii=False, indent=2), 'utf8')
for result in results:
    print(json.dumps(result, ensure_ascii=False))

# These two sources are release acceptance targets, not optional discovery statistics.
for name in ('番茄小说', '书旗小说'):
    result = next(r for r in results if r.get('name') == name)
    for stage in ('explore', 'search', 'toc', 'chapter1', 'chapter2', 'chapter3', 'offlineCache'):
        if result.get(stage, {}).get('status') != 'ok':
            raise SystemExit(f'{name}: {stage} did not pass; see report.json')

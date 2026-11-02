"""分析服务端返回的 MainQuestData，找出 ??? 任务"""
import re
import json
import glob
import os

logs = sorted(glob.glob(r'D:\EpinelPS\out\logs\app-*.log'), key=os.path.getmtime)
target = None
if not logs:
    print('没有日志')
    raise SystemExit

with open(logs[-1], encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for line in reversed(lines):
    if 'mainQuestList' in line:
        target = line
        break

if not target:
    print('日志里没有 mainQuestList')
    raise SystemExit

print('=== ResGetMainQuestData 分析 ===')
print('  行长度:', len(target), '字符')

matches = re.findall(r'\{\s*"tid":\s*(\d+),\s*"isReceived":\s*(\w+)\s*\}', target)
print('  任务数:', len(matches))

if matches:
    tids = [int(m[0]) for m in matches]
    print('  tid 范围:', min(tids), '~', max(tids))
    print()
    print('  前 5 个:')
    for m in matches[:5]:
        print('    tid=%s isReceived=%s' % m)
    print('  后 10 个:')
    for m in matches[-10:]:
        print('    tid=%s isReceived=%s' % m)

    # 检查是否有缺口
    s = sorted(set(tids))
    gaps = []
    for i in range(1, len(s)):
        if s[i] - s[i-1] > 1:
            gaps.append((s[i-1], s[i]))
    print()
    print('  tid 缺口:', gaps if gaps else '无')

print()
print('=== DB 里的 MainQuestData ===')
u = json.load(open(r'D:\EpinelPS\out\db.json', encoding='utf-8'))['Users'][0]
mq = u.get('MainQuestData') or {}
print('  总数:', len(mq))
if matches:
    db_ids = set(str(k) for k in mq.keys())
    log_ids = set(m[0] for m in matches)
    only_db = db_ids - log_ids
    only_log = log_ids - db_ids
    print('  只在 DB 里:', sorted(only_db, key=lambda x: int(x))[:10] if only_db else '无')
    print('  只在日志里:', sorted(only_log, key=lambda x: int(x))[:10] if only_log else '无')

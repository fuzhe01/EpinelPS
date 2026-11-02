"""诊断：关卡进度与任务链的对应关系
分析 QuestDataRecords 里的 CampaignClear 任务，看每个关卡 ID 对应哪个任务。
"""
import json
import struct
import re

# 从静态数据里读 Quest 表不方便（MemoryPack），
# 改为从 db.json 现有的 MainQuestData 反推
p = r'D:\EpinelPS\out\db.json'
db = json.load(open(p, encoding='utf-8'))
u = db['Users'][0]

mq = u.get('MainQuestData') or {}
keys = sorted(int(k) for k in mq.keys())
print('=== 当前 MainQuestData ===')
print('  数量:', len(keys))
print('  key 范围:', keys[:10], '...', keys[-10:])

# 连续性检查
gaps = []
for i in range(1, len(keys)):
    if keys[i] - keys[i-1] > 1:
        gaps.append((keys[i-1], keys[i]))
print('  不连续的间隔 (%d 处):' % len(gaps))
for g in gaps[:20]:
    print('    %d -> %d (缺 %d 个)' % (g[0], g[1], g[1]-g[0]-1))

print()
print('=== CompletedScenarios 里的章节分布 ===')
cs = u.get('CompletedScenarios') or []
ch = {}
for s in cs:
    m = re.match(r'd_main_(\d+)_', s)
    if m:
        c = int(m.group(1))
        ch[c] = ch.get(c, 0) + 1
if ch:
    print('  涉及章节:', len(ch))
    print('  最小:', min(ch), ' 最大:', max(ch))
    for c in sorted(ch)[:5]:
        print('    章%02d: %d 条' % (c, ch[c]))
    print('    ...')
    for c in sorted(ch)[-5:]:
        print('    章%02d: %d 条' % (c, ch[c]))

print()
print('=== FieldInfoNew 地图 ===')
fi = u.get('FieldInfoNew') or {}
print('  数量:', len(fi))
for k in list(fi.keys())[:10]:
    print('   ', k)
if len(fi) > 10:
    print('   ... 共 %d 个' % len(fi))

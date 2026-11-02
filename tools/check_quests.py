import json
from collections import Counter

u = json.load(open(r'D:\EpinelPS\out\db.json', encoding='utf-8'))['Users'][0]
mq = u.get('MainQuestData') or {}

print('=== MainQuestData 结构 ===')
print('  总数:', len(mq))
vals = Counter()
for k, v in mq.items():
    vals[repr(v)] += 1
print('  值分布:', dict(vals))
print()
sample = list(mq.items())[:5]
print('  样例:')
for k, v in sample:
    print('    %r -> %r' % (k, v))

ks = sorted(int(k) for k in mq)
print()
print('  key 范围:', ks[0], '~', ks[-1])

# 检查是否有缺口
gaps = []
for i in range(1, len(ks)):
    if ks[i] - ks[i-1] > 1:
        gaps.append((ks[i-1], ks[i]))
print('  key 缺口:', gaps[:10] if gaps else '无')

print()
print('=== SubQuestData ===')
sq = u.get('SubQuestData') or {}
print('  总数:', len(sq))
done = sum(1 for v in sq.values() if v is True)
print('  已完成:', done)
print('  未完成:', len(sq) - done)

print()
print('=== 章节开放相关字段 ===')
for k in sorted(u.keys()):
    lk = k.lower()
    if any(s in lk for s in ['chapter', 'campaign', 'chapterclear', 'open']):
        v = u[k]
        if isinstance(v, (list, dict)):
            print('  %-30s %d 项' % (k, len(v)))
            if len(v) <= 60 and len(v) > 0:
                print('     ', json.dumps(v, ensure_ascii=False)[:300])
        else:
            print('  %-30s %s' % (k, v))

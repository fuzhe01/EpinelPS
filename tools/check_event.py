import json

u = json.load(open(r'D:\EpinelPS\out\db.json', encoding='utf-8'))['Users'][0]

print('=== EventInfo（教程激活的）===')
ei = u.get('EventInfo') or {}
print('数量:', len(ei))
for k, v in ei.items():
    print('  key %s -> %s' % (k, json.dumps(v, ensure_ascii=False)))

print()
print('=== LastNormalStageCleared ===')
s = str(u.get('LastNormalStageCleared'))
print('  值:', s)
if len(s) == 7:
    print('  解析: 6 | %s | %s = 第 %d 章 第 %d 关' % (s[1:4], s[4:7], int(s[1:4]), int(s[4:7])))

print()
print('=== 其他可能引用活动的字段 ===')
for k in sorted(u.keys()):
    lk = k.lower()
    if any(s in lk for s in ['event', 'banner', 'notice', 'popup', 'shop', 'pass']):
        v = u[k]
        if isinstance(v, (list, dict)):
            if len(v) > 0:
                print('  %-30s %d 项: %s' % (k, len(v), json.dumps(v, ensure_ascii=False)[:150]))
        else:
            print('  %-30s %s' % (k, v))

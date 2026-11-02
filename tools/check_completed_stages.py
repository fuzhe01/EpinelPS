import json

u = json.load(open(r'D:\EpinelPS\out\db.json', encoding='utf-8'))['Users'][0]
fi = u.get('FieldInfoNew') or {}

print('=== FieldInfoNew 里的 CompletedStages ===')
total = 0
for mapid, data in fi.items():
    cs = data.get('CompletedStages') if isinstance(data, dict) else None
    if cs:
        n = len(cs)
        total += n
        # 解析关卡 ID 的章节
        chapters = {}
        for sid in cs:
            s = str(sid)
            if len(s) == 7 and s[0] == '6':
                ch = int(s[1:4])
                chapters[ch] = chapters.get(ch, 0) + 1
        chstr = ', '.join('%d章:%d关' % (c, chapters[c]) for c in sorted(chapters))
        print('  %-32s %3d 关  [%s]' % (mapid, n, chstr))
    else:
        keys = list(data.keys()) if isinstance(data, dict) else type(data).__name__
        print('  %-32s (无 CompletedStages) keys=%s' % (mapid, keys))

print()
print('  总计 CompletedStages:', total, '关')

print()
print('=== LastNormalStageCleared ===')
print(' ', u.get('LastNormalStageCleared'))

"""清空 EventInfo（活动进度记录）。
complete-all-event-stages 写入了 201 条活动记录，包含客户端资源包里不存在的
未来活动（异常大 ID，如 40126 / 60126），客户端为它们找横幅 sprite
（event_261119）时抛 FileNotFoundException，导致大厅 Home 界面准备失败。
清空后活动进度归零，但活动本身仍可正常进入。
"""
import json
import shutil
import datetime

p = r'D:\EpinelPS\out\db.json'
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, p + '.bak-evt-' + stamp)
print('backup: db.json.bak-evt-' + stamp)

with open(p, encoding='utf-8') as f:
    db = json.load(f)

u = db['Users'][0]
ei = u.get('EventInfo') or {}
print('清空前 EventInfo 数量:', len(ei))
big = sorted([int(k) for k in ei if str(k).isdigit()])[-8:]
print('  最大的几个 ID:', big)

u['EventInfo'] = {}

with open(p, 'w', encoding='utf-8') as f:
    json.dump(db, f, indent=2, ensure_ascii=False)

print('清空后 EventInfo:', len(u['EventInfo']))
print('保留 -> 角色:', len(u.get('Characters', {})), '材料:', len(u.get('Items', {})),
      '皮肤:', len(u.get('CostumeList', {})), '剧情:', len(u.get('CompletedScenarios', [])))

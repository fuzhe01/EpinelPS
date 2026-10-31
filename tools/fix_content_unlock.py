"""把 ContentsOpenUnlocked 全部标记为"动画已播放"，
这样客户端进大厅时不会再逐个弹内容解锁动画（38 个一起弹会把客户端卡死）。
"""
import json
import shutil
import datetime

p = r'D:\EpinelPS\out\db.json'
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, p + '.bak-unlock-' + stamp)
print('backup: db.json.bak-unlock-' + stamp)

with open(p, encoding='utf-8') as f:
    db = json.load(f)

u = db['Users'][0]
c = u.get('ContentsOpenUnlocked', {})
fixed_btn = 0
fixed_popup = 0
for k, v in c.items():
    if not v.get('ButtonAnimationPlayed'):
        v['ButtonAnimationPlayed'] = True
        fixed_btn += 1
    if not v.get('PopupAnimationPlayed'):
        v['PopupAnimationPlayed'] = True
        fixed_popup += 1

print('条目总数        :', len(c))
print('Button 动画修正 :', fixed_btn)
print('Popup  动画修正 :', fixed_popup)

with open(p, 'w', encoding='utf-8') as f:
    json.dump(db, f, indent=2, ensure_ascii=False)
print('saved')

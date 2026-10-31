"""清空 FavoriteItems（收藏品）。
add-all-collections 写入的收藏品里包含"未来活动"的条目（例如 event_261119），
客户端资源包（153.6.10）里没有对应的 sprite 表，导致大厅横幅列表构建时抛
FileNotFoundException，Home 界面准备不出来 → 卡死。
"""
import json
import shutil
import datetime

p = r'D:\EpinelPS\out\db.json'
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, p + '.bak-fav-' + stamp)
print('backup: db.json.bak-fav-' + stamp)

with open(p, encoding='utf-8') as f:
    db = json.load(f)

u = db['Users'][0]
fi = u.get('FavoriteItems') or []
print('清空前 FavoriteItems 数量:', len(fi))
print('  被移除的 Tid:', [i.get('Tid') for i in fi])

u['FavoriteItems'] = []

with open(p, 'w', encoding='utf-8') as f:
    json.dump(db, f, indent=2, ensure_ascii=False)

print('清空后:', len(u['FavoriteItems']))

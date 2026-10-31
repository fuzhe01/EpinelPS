import json
import shutil
import datetime

p = r'D:\EpinelPS\out\db.json'
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, p + '.bak-' + stamp)
print('backup: db.json.bak-' + stamp)

with open(p, 'r', encoding='utf-8') as f:
    db = json.load(f)

uid = 1450543095
users = db.setdefault('Users', [])
if any(u.get('ID') == uid for u in users):
    print('user already present')
else:
    users.append({"ID": uid})
    print('added user', uid)

with open(p, 'w', encoding='utf-8') as f:
    json.dump(db, f, indent=2, ensure_ascii=False)

print('Users now:', json.dumps(db.get('Users'), ensure_ascii=False))
print('keys:', list(db.keys()))

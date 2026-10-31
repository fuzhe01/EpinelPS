import json
import shutil
import datetime

p = r'D:\EpinelPS\out\db.json'
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, p + '.bak-cur-' + stamp)
print('backup:', 'db.json.bak-cur-' + stamp)

with open(p, encoding='utf-8') as f:
    db = json.load(f)

u = db['Users'][0]
cur = u.setdefault('Currency', {})

changes = {
    'FreeCash': 999999,          # 免费宝石
    'CharPremiumTicket': 9999,   # 角色高级招募券
    'ContentStamina': 999,       # 内容体力
}

for k, v in changes.items():
    print('  %-22s %s -> %s' % (k, cur.get(k), v))
    cur[k] = v

with open(p, 'w', encoding='utf-8') as f:
    json.dump(db, f, indent=2, ensure_ascii=False)

print('saved. Currency now:')
for k, v in cur.items():
    print('  %-22s %s' % (k, format(v, ',')))

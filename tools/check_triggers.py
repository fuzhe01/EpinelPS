import sqlite3
import json

db = r'D:\EpinelPS\out\epinelps.db'
con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
cur = con.cursor()

print('=== Triggers 表结构 ===')
cur.execute("PRAGMA table_info(Triggers)")
for r in cur.fetchall():
    print('  ', r)

print()
print('=== Trigger 记录统计 ===')
cur.execute('SELECT Type, COUNT(*) FROM Triggers GROUP BY Type')
rows = cur.fetchall()
if rows:
    for t, n in rows:
        print('  Type=%-6s %d 条' % (t, n))
else:
    print('  (表是空的)')

print()
print('=== ChapterClear 触发器详情 ===')
cur.execute("SELECT * FROM Triggers WHERE Type = 2 OR Type = 3")
rows = cur.fetchall()
print('  数量:', len(rows))
for r in rows[:30]:
    print('   ', r)

print()
print('=== 所有触发器前 20 条 ===')
cur.execute("SELECT * FROM Triggers LIMIT 20")
for r in cur.fetchall():
    print('   ', r)

con.close()

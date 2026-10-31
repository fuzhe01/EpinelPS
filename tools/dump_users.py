import sqlite3
import json

db = r'D:\EpinelPS\out\epinelps.db'
con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
cur = con.cursor()

cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = [r[0] for r in cur.fetchall()]
print("TABLES:", tables)

for t in tables:
    if 'sdk' in t.lower() or 'user' in t.lower():
        print("\n=== %s ===" % t)
        cur.execute('SELECT * FROM "%s"' % t)
        cols = [d[0] for d in cur.description]
        print("COLS:", cols)
        for row in cur.fetchall():
            print(json.dumps(dict(zip(cols, row)), ensure_ascii=False, default=str))

con.close()

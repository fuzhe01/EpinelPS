import sqlite3
import os

db = r'D:\EpinelPS\out\epinelps.db'
print('数据库:', db, '存在:', os.path.exists(db))

try:
    con = sqlite3.connect(db, timeout=10)
    cur = con.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    tables = [r[0] for r in cur.fetchall()]
    print('表 (%d 个):' % len(tables))
    for t in tables:
        print('  ', t)

    print()
    for t in ['__EFMigrationsLock', '__EFMigrationsHistory']:
        if t in tables:
            cur.execute('SELECT * FROM "%s"' % t)
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description]
            print('%s: %d 行, 列=%s' % (t, len(rows), cols))
            for r in rows[:10]:
                print('   ', r)
        else:
            print('%s: 不存在' % t)

    con.close()
except Exception as e:
    print('错误:', type(e).__name__, e)

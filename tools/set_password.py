import sqlite3
import hashlib
import sys

db = r'D:\EpinelPS\out\epinelps.db'
email = '2863329208@qq.com'
new_password = '123456'
h = hashlib.md5(new_password.encode()).hexdigest()

con = sqlite3.connect(db, timeout=20)
cur = con.cursor()
cur.execute("UPDATE SdkUsers SET PasswordHash=? WHERE Email=?", (h, email))
print("rows updated:", cur.rowcount)
con.commit()

cur.execute("SELECT ID, Email, PasswordHash, IsAdmin FROM SdkUsers")
for row in cur.fetchall():
    print(row)
con.close()
print("password set to:", new_password, " md5:", h)

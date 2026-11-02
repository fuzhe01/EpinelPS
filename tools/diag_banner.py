"""诊断 LobbyPrivateBanner 表：找出哪些 banner 是安全的
从静态数据里读 LobbyPrivateBannerTable 拿不到（MemoryPack），
改为从服务端日志里找它实际选中的 banner。
"""
import json
import glob
import re

# 从服务端日志里找 "Active lobby private banners" 的记录
logs = sorted(glob.glob(r'D:\EpinelPS\out\logs\app-*.log'))
print('=== 搜索服务端日志里的 banner 记录 ===')
found = False
for logf in logs:
    try:
        with open(logf, encoding='utf-8', errors='ignore') as f:
            for line in f:
                if 'Active lobby private banners' in line or 'lobby private banner' in line.lower():
                    print('  ', line.strip()[:400])
                    found = True
    except Exception as e:
        pass

if not found:
    print('  (日志里没有，说明日志级别不够或已清理)')

print()
print('=== 当前用户 LobbyPrivateBannerIds ===')
db = json.load(open(r'D:\EpinelPS\out\db.json', encoding='utf-8'))
u = db['Users'][0]
print('  LobbyPrivateBannerIds:', u.get('LobbyPrivateBannerIds'))

print()
print('=== db.json 顶层 ActiveEventBannerIds ===')
print('  ActiveEventBannerIds:', db.get('ActiveEventBannerIds'))

"""解析 MainQuestTable.mpk（MemoryPack 格式）"""
import re
import os

p = r'D:\EpinelPS\tools\sdwork\MainQuestTable.mpk'
b = open(p, 'rb').read()
print('文件大小:', len(b), '字节')

# MemoryPack 通常有头部长度
# 尝试提取可打印字符串看结构
strs = re.findall(rb'[ -~]{4,80}', b)
print('可打印字符串数:', len(strs))
print('前 40 个:')
for s in strs[:40]:
    print('  ', s.decode('ascii', 'replace'))

print()
print('=== 找 Category 枚举值 / 关键字段名 ===')
key_fields = ['Category', 'ConditionId', 'NextMainQuestId', 'Id', 'Title', 'Description']
for kf in key_fields:
    if kf.encode() in b:
        print('  含字段:', kf)
    else:
        print('  无字段:', kf)

print()
print('=== 前 64 字节 hex ===')
print(' ', ' '.join('%02X' % x for x in b[:64]))

print()
print('=== 末尾 64 字节 hex ===')
print(' ', ' '.join('%02X' % x for x in b[-64:]))

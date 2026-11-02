"""从 StaticData 解密出 Quest 表，分析第 50 章的任务

StaticData.pack 双层加密：
  1. 外层: PBKDF2(SmallNumber, Salt2) -> AES-CBC
  2. 内层: PBKDF2(SmallNumber, Salt1) -> CTR
"""
import base64
import json
import os
import struct
import sys

SMALL_NUMBER = base64.b64decode(
    "y8Icb/P1B/UFusrUmCiEH/DROMdh39bmZJqFEz4aagxoDivE33L4xlXkexQ2GDun0SCBItGpGIRlEwvtowDl2Q=="
)
SALT2 = base64.b64decode("BoyYXFlcWbIzIfzw9/yq34XiSg7iKeCQPQL4+tMII5o=")
SALT1 = base64.b64decode("XebMuvW+XhATlhrm+tQo9OEjkbPPSpY+EZWUmrEWNJQ=")

PACK = r'D:\EpinelPS\out\cache\prdenv\153-cb882d4b30\staticdata\data\qa-261029-10b\578481\mpk\StaticData.pack'
WORK = r'D:\EpinelPS\tools\sdwork'

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.backends import default_backend
    HAVE_CRYPTO = True
except ImportError:
    HAVE_CRYPTO = False
    print('需要 cryptography 库: pip install cryptography')
    sys.exit(1)


def pbkdf2(password, salt, iterations=10000, dklen=32):
    import hashlib
    return hashlib.pbkdf2_hmac('sha256', password, salt, iterations, dklen)


def aes_cbc_decrypt(key, iv, data):
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    d = cipher.decryptor()
    return d.update(data) + d.finalize()


def aes_ecb_encrypt_block(key, block):
    cipher = Cipher(algorithms.AES(key), modes.ECB(), backend=default_backend())
    e = cipher.encryptor()
    return e.update(block) + e.finalize()


def ctr_transform(key, counter, data):
    """服务端 DoTransformation：AES-ECB 加密 counter，然后 XOR"""
    key = key[:16]
    counter = bytearray(counter[:16])
    out = bytearray(len(data))
    pos = 0
    while pos < len(data):
        block = aes_ecb_encrypt_block(key, bytes(counter))
        n = min(16, len(data) - pos)
        for i in range(n):
            out[pos + i] = data[pos + i] ^ block[i]
        pos += n
        # 递增计数器
        for k in range(15, -1, -1):
            counter[k] = (counter[k] + 1) & 0xFF
            if counter[k] != 0:
                break
    return bytes(out)


def main():
    os.makedirs(WORK, exist_ok=True)
    raw = open(PACK, 'rb').read()
    print('PACK 大小: %.1f MB' % (len(raw) / 1024 / 1024))

    key2 = pbkdf2(SMALL_NUMBER, SALT2)
    decrypted = aes_cbc_decrypt(key2[:16], key2[16:32], raw)
    print('第一层解密: %.1f MB' % (len(decrypted) / 1024 / 1024))

    # 这是 zip，找 data 条目
    import zipfile
    import io
    outer = zipfile.ZipFile(io.BytesIO(decrypted))
    print('外层 zip 条目:', outer.namelist())
    data_bytes = outer.read('data')
    print('data 条目: %.1f MB' % (len(data_bytes) / 1024 / 1024))

    key3 = pbkdf2(SMALL_NUMBER, SALT1)
    inner_bytes = ctr_transform(key3[:16], key3[16:32], data_bytes)
    print('第二层变换完成: %.1f MB' % (len(inner_bytes) / 1024 / 1024))

    inner = zipfile.ZipFile(io.BytesIO(inner_bytes))
    names = inner.namelist()
    print('内层 zip 条目数:', len(names))

    # 找 Quest 相关
    quests = [n for n in names if 'Quest' in n]
    print()
    print('Quest 相关条目 (%d):' % len(quests))
    for q in quests[:20]:
        print('  ', q)

    # 导出 QuestTable
    print()
    for target in ['QuestTable.mpk', 'Quest.mpk']:
        hits = [n for n in names if n == target or n.endswith('/' + target)]
        for h in hits:
            out = os.path.join(WORK, os.path.basename(h))
            with open(out, 'wb') as f:
                f.write(inner.read(h))
            print('已导出:', out, '(%d 字节)' % os.path.getsize(out))


if __name__ == '__main__':
    main()

"""补齐 CompletedStages 缺口 + 同步 LastNormalStageCleared

原理：
  - FieldInfoNew[地图].CompletedStages 是"已通关关卡 ID"的权威来源
  - 该列表存在空洞（例如第6章缺 6-16/6-17/6-27/6-28/6-29）
  - 客户端遇到空洞会认为进度在前面，导致显示的下一关错乱

策略：
  1. 每张地图的 CompletedStages 补齐成连续序列（从该章第1关到最大已通关关卡）
  2. 可选：扩展到指定章节（--to-chapter N）
  3. LastNormalStageCleared 同步到最高已通关关卡
"""
import json
import sys
import shutil
import datetime
import os

DB = r'D:\EpinelPS\out\db.json'


def load():
    return json.load(open(DB, encoding='utf-8'))


def save(db):
    json.dump(db, open(DB, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)


def backup():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    dst = DB + '.bak-fill-' + stamp
    shutil.copy2(DB, dst)
    print('备份:', os.path.basename(dst))
    return dst


def chapter_of(stage_id):
    """6006001 -> 6"""
    s = str(stage_id)
    if len(s) == 7 and s[0] == '6':
        return int(s[1:4])
    return None


def fill_map(completed, target_max=None):
    """把一组关卡 ID 补齐成连续序列。
    completed: set of stage ids
    target_max: 若指定，补到这个关卡 ID 为止
    返回: (new_set, added_count)
    """
    if not completed and target_max is None:
        return set(), 0

    by_ch = {}
    for sid in completed:
        ch = chapter_of(sid)
        if ch is None:
            continue
        by_ch.setdefault(ch, set()).add(sid)

    if target_max is not None:
        tch = chapter_of(target_max)
        if tch is not None:
            by_ch.setdefault(tch, set())

    result = set()
    for ch, ids in by_ch.items():
        if not ids and target_max is None:
            continue
        max_stage = max(ids) if ids else target_max
        if target_max is not None and chapter_of(target_max) == ch:
            max_stage = max(max_stage or 0, target_max)
        if not max_stage:
            continue
        # 从该章第 1 关补到 max_stage 对应的小关号
        s = str(max_stage)
        last_sub = int(s[4:7]) if len(s) == 7 else 1
        for i in range(1, last_sub + 1):
            result.add(6000000 + ch * 1000 + i)

    # 保留无法解析章节的 ID
    for sid in completed:
        if chapter_of(sid) is None:
            result.add(sid)

    added = result - completed
    return result, len(added)


def main():
    to_chapter = None
    if '--to-chapter' in sys.argv:
        idx = sys.argv.index('--to-chapter')
        if idx + 1 < len(sys.argv):
            to_chapter = int(sys.argv[idx + 1])

    db = load()
    u = db['Users'][0]
    fi = u.get('FieldInfoNew') or {}

    print('=== 补齐前 ===')
    total_before = 0
    for mapid, data in sorted(fi.items()):
        cs = data.get('CompletedStages') or []
        total_before += len(cs)
        if cs:
            chs = sorted({chapter_of(x) for x in cs if chapter_of(x) is not None})
            if chs:
                mx = max(cs)
                print('  %-32s %3d 关  章%s  最大 %d' % (mapid, len(cs), chs, mx))
    print('  总计: %d 关' % total_before)

    backup()

    print()
    print('=== 补齐中 ===')
    total_added = 0
    global_max = 0
    for mapid, data in fi.items():
        cs = data.get('CompletedStages') or []
        if not cs:
            continue

        target = None
        if to_chapter is not None:
            chs = [chapter_of(x) for x in cs if chapter_of(x) is not None]
            if chs and max(chs) <= to_chapter:
                # 这张地图属于 <= target 章节，补到该章最后一关
                # 用该章现有最大值判断，不做跨章扩展
                pass

        newset, added = fill_map(set(cs), target)
        if added > 0 or len(newset) != len(set(cs)):
            data['CompletedStages'] = sorted(newset)
            total_added += added
            if newset:
                global_max = max(global_max, max(newset))
            print('  %-32s %3d -> %3d 关 (+%d)' % (mapid, len(set(cs)), len(newset), added))

    # 同步 LastNormalStageCleared
    old_lns = u.get('LastNormalStageCleared')
    if global_max:
        u['LastNormalStageCleared'] = global_max
        print()
        print('  LastNormalStageCleared: %s -> %d' % (old_lns, global_max))

    save(db)

    print()
    print('=== 补齐后 ===')
    total_after = 0
    for mapid, data in sorted(fi.items()):
        cs = data.get('CompletedStages') or []
        total_after += len(cs)
    print('  总计: %d 关（+%d）' % (total_after, total_added))
    print('  LastNormalStageCleared:', u.get('LastNormalStageCleared'))


if __name__ == '__main__':
    main()

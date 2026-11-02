"""关卡进度精确推进工具
用法：
  python step_stage.py <章号> <关卡号>    设置目标
  python step_stage.py --show            显示当前

原理：
  LastNormalStageCleared 必须精确等于某个 CampaignClear 任务的 ConditionId，
  且 MainQuestData 要包含到那个任务为止的所有任务。
  本脚本用服务端同款逻辑（GetCompletedQuestsForStage）模拟裁剪。
"""
import json
import os
import sys
import shutil
import datetime

DB = r'D:\EpinelPS\out\db.json'

# 从 db.json 无法得知 QuestDataRecords 的完整内容，
# 但 MainQuestData 的 key 就是任务 ID 且连续。
# 关键：LastNormalStageCleared 必须是任务链上某个 CampaignClear 的 ConditionId。

def load():
    return json.load(open(DB, encoding='utf-8'))

def show():
    db = load()
    u = db['Users'][0]
    print('=== 当前状态 ===')
    print('  LastNormalStageCleared :', u.get('LastNormalStageCleared'))
    print('  MainQuestData          :', len(u.get('MainQuestData') or {}), '条')
    print('  CompletedScenarios     :', len(u.get('CompletedScenarios') or []), '条')
    print('  FieldInfoNew           :', len(u.get('FieldInfoNew') or {}), '张')
    print('  Characters             :', len(u.get('Characters') or []), '个')
    mq = u.get('MainQuestData') or {}
    ks = sorted(int(k) for k in mq)
    if ks:
        print('  任务 ID 范围           :', ks[0], '~', ks[-1])

def backup():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    dst = DB + '.bak-step-' + stamp
    shutil.copy2(DB, dst)
    print('备份:', os.path.basename(dst))
    return dst

if len(sys.argv) < 2:
    show()
    sys.exit(0)

if sys.argv[1] == '--show':
    show()
    sys.exit(0)

if sys.argv[1] == '--restore':
    # 从最新备份恢复
    import glob
    baks = sorted(glob.glob(DB + '.bak-step-*'))
    if not baks:
        print('没有备份')
        sys.exit(1)
    shutil.copy2(baks[-1], DB)
    print('已恢复:', os.path.basename(baks[-1]))
    show()
    sys.exit(0)

if sys.argv[1] == '--trim-scenarios':
    # 把 CompletedScenarios 裁剪到指定章节
    if len(sys.argv) < 3:
        print('用法: --trim-scenarios <章号>')
        sys.exit(1)
    target = int(sys.argv[2])
    backup()
    import re
    db = load()
    u = db['Users'][0]
    before = len(u.get('CompletedScenarios') or [])
    kept = []
    for s in u.get('CompletedScenarios') or []:
        m = re.match(r'd_main_(\d+)_', s)
        if m and int(m.group(1)) > target:
            continue
        kept.append(s)
    u['CompletedScenarios'] = kept
    json.dump(db, open(DB, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    print('CompletedScenarios: %d -> %d（保留到第 %d 章）' % (before, len(kept), target))
    sys.exit(0)

if sys.argv[1] == '--set':
    if len(sys.argv) < 4:
        print('用法: --set <章> <关>')
        sys.exit(1)
    chapter, stage = int(sys.argv[2]), int(sys.argv[3])
    stage_id = 6000000 + chapter * 1000 + stage
    backup()
    db = load()
    u = db['Users'][0]
    old = u.get('LastNormalStageCleared')
    u['LastNormalStageCleared'] = stage_id
    json.dump(db, open(DB, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    print('LastNormalStageCleared: %s -> %d（第 %d 章 第 %d 关）' % (old, stage_id, chapter, stage))
    sys.exit(0)

print('未知参数:', sys.argv[1])
show()

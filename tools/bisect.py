# -*- coding: utf-8 -*-
"""
万法阁 · 故障二分部署工具

用途：当游戏内出现「现象只在装了本 mod 时出现」的疑难杂症时，
用最小集合反复部署，定位是哪一层配置/脚本触发的。

用法：
    python tools/bisect.py                    # 全量部署（等同 deploy.py）
    python tools/bisect.py --off lua          # 只部署 XML，不部署 Scripts
    python tools/bisect.py --off gong         # 不部署功法/参悟树/秘籍/Modifier
    python tools/bisect.py --off thing        # 不部署物品/建筑/法宝配方/建造菜单
    python tools/bisect.py --off magic        # 不部署神通 XML
    python tools/bisect.py --off lua,gong     # 组合排除
    python tools/bisect.py --dry              # 只打印将同步的文件

每次部署前会清空目标目录内的对应子目录，避免旧文件残留导致「排除无效」。
"""
from __future__ import print_function

import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME_MODS = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\Mods"
MOD_NAME = u"万法阁"

# 排除项 -> 根目录下要跳过的相对路径前缀（用 / 分隔，大小写不敏感）
EXCLUDE = {
    "lua": ["Scripts"],
    "gong": [
        "Settings/Practice/Gong",
        "Settings/Practice/Tree",
        "Settings/Esoterica",
        "Settings/Modifiers",
        "Settings/Npc/Experience",
    ],
    "magic": ["Settings/Practice/Magic"],
    "thing": [
        "Settings/ThingDef",
        "Settings/Practice/FabaoFormula",
        "Settings/UI",
    ],
}
ALWAYS = ["Info.json", "Preview.png", "README.md"]


def collect(off):
    """返回 [(源绝对路径, 目标相对路径), ...]"""
    off = {o.strip().lower() for o in off if o.strip()}
    bad = off - set(EXCLUDE)
    if bad:
        print(u"[!] 未知排除项：%s（可选：%s）" % (u",".join(sorted(bad)), u",".join(sorted(EXCLUDE))))
        sys.exit(2)
    skip_prefixes = []
    for key in off:
        skip_prefixes += EXCLUDE[key]
    skip_prefixes = [p.replace("\\", "/").lower() for p in skip_prefixes]

    def skipped(rel):
        r = rel.replace("\\", "/").lower()
        for p in skip_prefixes:
            if r == p or r.startswith(p + "/"):
                return True
        return False

    files = []
    for name in ALWAYS:
        src = os.path.join(ROOT, name)
        if os.path.isfile(src):
            files.append((src, name))
    for top in ("Settings", "Scripts"):
        base = os.path.join(ROOT, top)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in filenames:
                src = os.path.join(dirpath, fn)
                rel = os.path.relpath(src, ROOT).replace("\\", "/")
                if skipped(rel):
                    continue
                files.append((src, rel))
    files.sort(key=lambda x: x[1])
    return files, sorted(off), skip_prefixes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--off", default="", help=u"要排除的层，逗号分隔：lua,gong,magic,thing")
    ap.add_argument("--dest", default=GAME_MODS, help=u"游戏 Mods 目录")
    ap.add_argument("--dry", action="store_true", help=u"只打印不写盘")
    args = ap.parse_args()

    files, off, skip_prefixes = collect([x for x in args.off.split(",") if x.strip()])
    dest_root = os.path.join(args.dest, MOD_NAME)

    print(u"[万法阁] 排除层：%s" % (u"、".join(off) if off else u"（无，全量）"))
    print(u"[万法阁] 目标目录：%s" % dest_root)

    if args.dry:
        for _src, rel in files:
            print(u"  + %s" % rel)
        print(u"[万法阁] 共 %d 个文件（dry run，未写盘）" % len(files))
        return

    if not os.path.isdir(args.dest):
        print(u"[!] 游戏 Mods 目录不存在：%s" % args.dest)
        sys.exit(2)

    # 清掉被排除的子树，确保「排除」真的生效
    for p in skip_prefixes:
        victim = os.path.join(dest_root, p.replace("/", os.sep))
        if os.path.isdir(victim):
            shutil.rmtree(victim)
            print(u"  - 移除 %s" % p)

    for src, rel in files:
        dst = os.path.join(dest_root, rel.replace("/", os.sep))
        d = os.path.dirname(dst)
        if d and not os.path.isdir(d):
            os.makedirs(d)
        shutil.copy2(src, dst)

    print(u"[万法阁] 已同步 %d 个文件。请重启游戏（mod 配置在启动时解析）。" % len(files))


if __name__ == "__main__":
    main()

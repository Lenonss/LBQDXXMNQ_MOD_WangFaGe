"""把「万法阁」部署到游戏 Mods 目录（覆盖式同步）。

用法：
    python tools/deploy.py            # 同步到默认游戏路径
    python tools/deploy.py --dry      # 只看会复制哪些文件

只同步 Info.json / Settings / Scripts，docs 与工具脚本不进游戏。
"""
import argparse
import os
import shutil
import sys

GAME_MODS = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\Mods"
MOD_NAME = "万法阁"
SRC_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAYLOAD = ["Info.json", "Preview.png", "README.md", "Settings", "Scripts", "Resources"]


def iter_src():
    for item in PAYLOAD:
        path = os.path.join(SRC_ROOT, item)
        if not os.path.exists(path):
            print(f"[warn] 源缺失：{path}")
            continue
        if os.path.isfile(path):
            yield path, item
        else:
            for root, _dirs, files in os.walk(path):
                for f in files:
                    full = os.path.join(root, f)
                    yield full, os.path.relpath(full, SRC_ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--dest", default=os.path.join(GAME_MODS, MOD_NAME))
    args = ap.parse_args()

    if not os.path.isdir(GAME_MODS):
        sys.exit(f"找不到游戏 Mods 目录：{GAME_MODS}")

    count = 0
    for full, rel in iter_src():
        dst = os.path.join(args.dest, rel)
        if args.dry:
            print(f"{rel} -> {dst}")
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(full, dst)
        count += 1

    print(f"{'将复制' if args.dry else '已复制'} {count} 个文件 -> {args.dest}")


if __name__ == "__main__":
    main()

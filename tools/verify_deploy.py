"""校验工作区与游戏 Mods 目录是否一致（逐文件 SHA-256）。

用法:
    python tools/verify_deploy.py
退出码 0 = 完全一致；1 = 有差异（列出差异项）。
"""
import hashlib
import os
import sys

GAME_MODS = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\Mods"
MOD_NAME = "万法阁"
SRC_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST_ROOT = os.path.join(GAME_MODS, MOD_NAME)
PAYLOAD = ["Info.json", "Preview.png", "README.md", "Settings", "Scripts", "Resources"]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 16), b""):
            h.update(block)
    return h.hexdigest()


def collect(root, rels):
    out = {}
    for rel in rels:
        base = os.path.join(root, rel)
        if os.path.isfile(base):
            out[rel] = base
            continue
        for dirpath, _dirs, files in os.walk(base):
            for name in files:
                full = os.path.join(dirpath, name)
                out[os.path.relpath(full, root)] = full
    return out


def main():
    if not os.path.isdir(DST_ROOT):
        sys.exit(f"找不到部署目录：{DST_ROOT}")
    src = collect(SRC_ROOT, PAYLOAD)
    dst = collect(DST_ROOT, ["."])
    missing = sorted(set(src) - set(dst))
    extra = sorted(set(dst) - set(src))
    differ = [rel for rel in sorted(set(src) & set(dst)) if sha(src[rel]) != sha(dst[rel])]
    print(f"源 {len(src)} 个文件 / 部署 {len(dst)} 个文件")
    for tag, items in (("缺失", missing), ("多余", extra), ("内容不同", differ)):
        if items:
            print(f"[{tag}] {len(items)}")
            for rel in items:
                print("   ", rel)
    if missing or extra or differ:
        sys.exit(1)
    print("一致：全部文件 SHA-256 相同")


if __name__ == "__main__":
    main()

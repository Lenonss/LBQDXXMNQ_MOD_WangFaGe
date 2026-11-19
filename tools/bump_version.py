"""改版本号（Info.json 的整数 Version + 文档与 CHANGELOG 提示）。

用法：
    python tools/bump_version.py 2.1.0      # 写入 Info.json Version=210
    python tools/bump_version.py 2.0.1 --dry

映射规则：Info.json 的 Version 是游戏内整数显示，取 major*100 + minor*10 + patch。
    2.0.0 -> 200    2.1.0 -> 210    2.1.3 -> 213
只改 Info.json；CHANGELOG 由人补写，脚本只做提示。
"""
import argparse
import json
import os
import sys

SRC_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO = os.path.join(SRC_ROOT, "Info.json")


def to_int(ver):
    parts = [int(x) for x in ver.strip().lstrip("vV").split(".")]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts[0], parts[1], parts[2]
    if minor > 9 or patch > 9:
        raise SystemExit("minor/patch 超过 9，映射会撞号，请改用新的 major")
    return major * 100 + minor * 10 + patch


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version", help="语义化版本，如 2.1.0 或 v2.1.0")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    ver = to_int(args.version)
    with open(INFO, "r", encoding="utf-8") as f:
        info = json.load(f)
    old = info.get("Version")
    info["Version"] = ver
    text = json.dumps(info, ensure_ascii=False, indent="\t") + "\n"

    if args.dry:
        print("[dry] Version %s -> %s" % (old, ver))
    else:
        with open(INFO, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("Info.json Version %s -> %s" % (old, ver))

    tag = args.version.strip()
    if not tag.startswith("v"):
        tag = "v" + tag
    print("下一步：")
    print("  1. 在 CHANGELOG.md 顶部补 ## %s" % tag)
    print("  2. python tools/package_release.py --version %s" % tag)
    print("  3. git add -A && git commit -m \"release: %s\"" % tag)
    print("  4. git tag %s && git push origin main --tags" % tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())

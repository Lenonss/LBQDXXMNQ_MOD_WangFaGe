"""打包发版压缩包（PC 与安卓通用）。

用法：
    python tools/package_release.py                 # 版本号取自 Info.json
    python tools/package_release.py --version v2.0.0 # 指定版本（CI 用 tag）
    python tools/package_release.py --out dist

产物：
    dist/万法阁/                 # 与游戏 Mods 目录内结构一致的展开目录
    dist/WangFaGe_v2.0.0.zip    # 解压后得到 万法阁/ 目录，直接丢进 Mods
                                # （外层文件名为纯 ASCII，GitHub 上传不会丢字符）
    dist/SHA256SUMS.txt          # 每个产物的 SHA-256

只打游戏运行所需内容（与 tools/deploy.py 的 PAYLOAD 一致），docs/tools/res 不进包。
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import zipfile

SRC_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAYLOAD = ["Info.json", "Preview.png", "README.md", "Settings", "Scripts", "Resources"]

# Release 资产文件名必须是纯 ASCII：gh 在 C locale 的 runner 上传时会吞掉非 ASCII 字符
ZIP_PREFIX = "WangFaGe"


def read_info():
    with open(os.path.join(SRC_ROOT, "Info.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def iter_payload():
    for item in PAYLOAD:
        path = os.path.join(SRC_ROOT, item)
        if not os.path.exists(path):
            print("[warn] 源缺失：" + path)
            continue
        if os.path.isfile(path):
            yield path, item
            continue
        for base, _dirs, files in os.walk(path):
            for name in files:
                full = os.path.join(base, name)
                yield full, os.path.relpath(full, SRC_ROOT)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="", help="发版版本号，如 v2.0.0；缺省取 Info.json 映射")
    ap.add_argument("--out", default="dist")
    args = ap.parse_args()

    info = read_info()
    mod_name = info["Name"]
    int_ver = int(info.get("Version", 0))
    tag = args.version.strip()
    if not tag:
        tag = "v%d.%d.%d" % (int_ver // 100, (int_ver // 10) % 10, int_ver % 10)
    if not tag.startswith("v"):
        tag = "v" + tag

    out_dir = os.path.join(SRC_ROOT, args.out)
    stage = os.path.join(out_dir, mod_name)
    if os.path.isdir(stage):
        shutil.rmtree(stage)
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    count = 0
    for full, rel in iter_payload():
        dst = os.path.join(stage, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(full, dst)
        count += 1

    zip_path = os.path.join(out_dir, "%s_%s.zip" % (ZIP_PREFIX, tag))
    if os.path.exists(zip_path):
        os.remove(zip_path)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for base, _dirs, files in os.walk(stage):
            for name in files:
                full = os.path.join(base, name)
                arc = os.path.join(mod_name, os.path.relpath(full, stage))
                zf.write(full, arc.replace(os.sep, "/"))

    sums = os.path.join(out_dir, "SHA256SUMS.txt")
    with open(sums, "w", encoding="utf-8", newline="\n") as f:
        for p in (zip_path, os.path.join(SRC_ROOT, "Info.json")):
            f.write("%s  %s\n" % (sha256_of(p), os.path.basename(p)))

    print("打包 %d 个文件 -> %s" % (count, zip_path))
    print("版本 %s（Info.json Version=%d）" % (tag, int_ver))
    print("校验清单 -> %s" % sums)
    print("SHA-256 %s" % sha256_of(zip_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())

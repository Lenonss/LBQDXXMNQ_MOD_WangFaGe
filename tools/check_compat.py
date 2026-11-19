"""双端兼容性静态体检（不依赖游戏，可在 CI 与本地跑）。

检查项：
  1. 编码（错误）：.lua/.xml/.json 必须是 UTF-8 且无 BOM
  2. Info.json（错误）：必填字段齐全、Version 为整数
  3. 资源引用（错误）：文本里出现的图片名必须能找到（支持 TexPath 全路径与 Icon 纯文件名）
  4. 路径分隔符（提示）：XML 的 Spr\\Object\\x.png 是引擎约定，安卓是否同样接受未验证
  5. 触屏风险（提示）：鼠标/键盘 API、悬停事件、固定像素尺寸、内置依赖

用法：
    python tools/check_compat.py            # 有错误则退出码 1
    python tools/check_compat.py --strict   # 提示也算失败
"""
import argparse
import json
import os
import sys

SRC_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".codegraph", "dist", "__pycache__", "res", "docs"}
TEXT_EXT = {".lua", ".xml", ".json"}
ASSET_EXT = (".png", ".jpg", ".jpeg", ".fnt", ".fui")
BS = chr(92)

errors = []
warns = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warns.append(msg)


def walk(skip_docs=True):
    for base, dirs, files in os.walk(SRC_ROOT):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            full = os.path.join(base, name)
            rel = os.path.relpath(full, SRC_ROOT).replace(os.sep, "/")
            yield full, rel


def build_asset_index():
    """文件名 -> 相对路径列表，大小写以磁盘为准。"""
    index = {}
    for full, rel in walk():
        low = rel.lower()
        if not low.endswith(ASSET_EXT):
            continue
        index.setdefault(os.path.basename(rel), []).append(rel)
    return index


def case_exact_exists(rel):
    """逐级比对真实目录项，安卓文件系统大小写敏感。"""
    cur = SRC_ROOT
    for seg in rel.split("/"):
        if seg in ("", "."):
            continue
        try:
            names = os.listdir(cur)
        except OSError:
            return False
        if seg not in names:
            return False
        cur = os.path.join(cur, seg)
    return True


def check_encoding(full, rel):
    with open(full, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        err(rel + "：带 UTF-8 BOM，请去掉")
        raw = raw[3:]
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as e:
        err(rel + "：不是 UTF-8（" + str(e) + "）")


def read_text(full):
    with open(full, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def quoted_tokens(text):
    for quote in ('"', "'"):
        parts = text.split(quote)
        for idx in range(1, len(parts), 2):
            yield parts[idx]


def check_assets(rel, text, index):
    seen = set()
    for tok in quoted_tokens(text):
        low = tok.lower()
        if not low.endswith(ASSET_EXT) or "://" in tok or tok in seen:
            continue
        seen.add(tok)
        ref = tok.replace(BS, "/").strip()
        while ref.startswith("./"):
            ref = ref[2:]
        ref = ref.strip("/")
        candidates = [ref, "Resources/" + ref]
        hit = ""
        for cand in candidates:
            if case_exact_exists(cand):
                hit = cand
                break
        if hit:
            continue
        base = os.path.basename(ref)
        found = index.get(base, [])
        if found:
            continue
        err("%s：找不到资源 %s（按文件名在所有资源里也搜不到）" % (rel, tok))


def check_backslash(rel, text):
    for i, line in enumerate(text.splitlines(), 1):
        if BS not in line:
            continue
        low = line.lower()
        if any(ext in low for ext in ASSET_EXT):
            warn("%s:%d：路径用了反斜杠（引擎约定，安卓待验证）-> %s" % (rel, i, line.strip()[:100]))
        elif "resources" in low or "scripts" in low:
            err("%s:%d：脚本/资源目录写成反斜杠 -> %s" % (rel, i, line.strip()[:100]))


RISKS = [
    ("GetMouseButtonDown", "鼠标左键，触屏无此事件"),
    ("GetMouseButtonUp", "鼠标左键，触屏无此事件"),
    ("GetMouseButton(", "鼠标按键，触屏无此事件"),
    ("GetKeyDown", "键盘按键，手机上无键盘"),
    ("onRollOver", "悬停高亮，触屏没有 hover"),
    ("onRollOut", "悬停高亮，触屏没有 hover"),
    ("SimpleWindow", "依赖内置 SimpleWindow，需确认移动版存在"),
    ("MagicHelper", "依赖内置 MagicHelper，需确认移动版存在"),
    ("ThingHelper", "依赖内置 ThingHelper，需确认移动版存在"),
]


def check_touch_risk(rel, text):
    for i, line in enumerate(text.splitlines(), 1):
        for pat, why in RISKS:
            if pat in line:
                warn("%s:%d：%s -> %s" % (rel, i, why, line.strip()[:100]))
        stripped = line.strip()
        for key in ("WIN_W", "WIN_H"):
            if stripped.startswith(key) and "=" in stripped:
                if any(ch.isdigit() for ch in stripped.split("=", 1)[1]):
                    warn("%s:%d：固定像素尺寸，小屏需钳位/自适应 -> %s" % (rel, i, stripped[:100]))
                break


def check_info():
    path = os.path.join(SRC_ROOT, "Info.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            info = json.load(f)
    except Exception as e:
        err("Info.json 解析失败：" + str(e))
        return
    for key in ("Name", "DisplayName", "Desc", "GameVersion", "Version"):
        if key not in info:
            err("Info.json 缺字段：" + key)
    if not isinstance(info.get("Version"), int):
        err("Info.json 的 Version 必须是整数（当前 %r）" % (info.get("Version"),))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="提示也计入失败")
    args = ap.parse_args()

    index = build_asset_index()
    for full, rel in walk():
        ext = os.path.splitext(rel)[1].lower()
        if ext not in TEXT_EXT:
            continue
        check_encoding(full, rel)
        text = read_text(full)
        check_assets(rel, text, index)
        check_backslash(rel, text)
        check_touch_risk(rel, text)
    check_info()

    for m in warns:
        print("[warn] " + m)
    for m in errors:
        print("[err ] " + m)
    print("")
    print("检查完成：%d 错误 / %d 提示" % (len(errors), len(warns)))
    if errors or (args.strict and warns):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

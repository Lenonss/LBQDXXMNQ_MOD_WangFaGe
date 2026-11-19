#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""扫描原版 Settings 生成「官方配置字段观测统计」。

用途：为 docs/官方字段参考.md 提供取值范围依据。
输出：docs/官方字段统计.md（自动生成，勿手改）。

用法：
    python tools/gen_field_docs.py            # 写 docs/官方字段统计.md
    python tools/gen_field_docs.py --stdout   # 只打印
"""
import sys
import os
import glob
import pathlib
import re
import xml.etree.ElementTree as ET
from collections import defaultdict, Counter

DEFAULT_GAME = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator"
GAME = os.path.join(DEFAULT_GAME, "Settings")
OUT = os.path.join("docs", "官方字段统计.md")

# 结构定义：(中文名, 用于匹配的标签名, 扫描哪些目录)
TARGETS = [
    ("功法根节点 Gong", "Gong", ["Practice/Gong"]),
    ("功法阶段 Stage", "Stage", ["Practice/Gong"]),
    ("瓶颈 Neck", "Neck", ["Practice/Gong"]),
    ("秘籍 Esoterica", "Esoterica", ["Esoterica"]),
    ("参悟树节点 Node", "Node", ["Practice/Tree"]),
    ("神通 Magic", "Magic", ["Practice/Magic"]),
    ("Modifier", "Modifier", ["Modifiers"]),
    ("法宝配方 Fabao", "Fabao", ["Practice/FabaoFormula"]),
    ("物品 Item", "Item", ["ThingDef/Item"]),
    ("建筑 Building", "Building", ["ThingDef/Building"]),
]

NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")


def iter_xml(rel_dirs):
    for rel in rel_dirs:
        base = os.path.join(GAME, rel.replace("/", os.sep))
        for path in glob.glob(os.path.join(base, "**", "*.xml"), recursive=True):
            try:
                yield path, ET.parse(path).getroot()
            except ET.ParseError:
                continue


def describe(values, total):
    """把一组字符串取值压成一句话描述。"""
    uniq = sorted(set(values))
    nums = [v for v in uniq if NUM_RE.match(v)]
    if len(nums) == len(uniq) and nums:
        f = [float(v) for v in nums]
        lo, hi = min(f), max(f)
        if lo == hi:
            return "数值，恒为 `%s`" % uniq[0]
        ints = all(v.isdigit() or (v.startswith("-") and v[1:].isdigit()) for v in uniq)
        if ints:
            return "数值 %d–%d（%d 种）" % (int(lo), int(hi), len(uniq))
        return "数值 %g–%g（%d 种）" % (lo, hi, len(uniq))
    def clip(v):
        v = re.sub(r"\s+", " ", v).strip()
        return v if len(v) <= 24 else v[:22] + "…"

    if len(uniq) <= 8:
        return "枚举：" + "、".join("`%s`" % clip(v) for v in uniq)
    return "%d 种取值，如 %s …" % (len(uniq), "、".join("`%s`" % clip(v) for v in uniq[:3]))


def scan(tag, rel_dirs):
    """返回 (元素数, {字段: {count, values}}, {属性: {count, values}})"""
    elems = 0
    child = defaultdict(lambda: {"count": 0, "values": [], "text": 0})
    attrs = defaultdict(lambda: {"count": 0, "values": []})
    for path, root in iter_xml(rel_dirs):
        for el in root.iter(tag):
            elems += 1
            for a, v in el.attrib.items():
                attrs[a]["count"] += 1
                if len(attrs[a]["values"]) < 400:
                    attrs[a]["values"].append(v)
            for c in list(el):
                key = c.tag
                rec = child[key]
                rec["count"] += 1
                txt = (c.text or "").strip()
                if txt:
                    if len(rec["values"]) < 400:
                        rec["values"].append(txt)
                else:
                    rec["text"] += 1
    return elems, child, attrs


def render():
    lines = ["# 官方配置字段统计（自动生成）", ""]
    lines.append("> 由 `tools/gen_field_docs.py` 扫描原版 `Settings/` 生成，**勿手改**。")
    lines.append("> 统计口径为「原版数据里实际出现过的写法」，不是引擎允许的全部取值；语义与坑见 `docs/官方字段参考.md`。")
    lines.append("")
    lines.append("| 结构 | 原版出现次数 |")
    lines.append("|---|---|")
    stats = []
    for name, tag, dirs in TARGETS:
        elems, child, attrs = scan(tag, dirs)
        stats.append((name, tag, elems, child, attrs))
        lines.append("| %s `<%s>` | %d |" % (name, tag, elems))
    lines.append("")

    for name, tag, elems, child, attrs in stats:
        lines.append("## %s `<%s>`" % (name, tag))
        lines.append("")
        if elems == 0:
            lines.append("_原版无此节点。_")
            lines.append("")
            continue
        if attrs:
            lines.append("### XML 属性")
            lines.append("")
            lines.append("| 属性 | 出现次数 | 观测取值 |")
            lines.append("|---|---|---|")
            for k in sorted(attrs, key=lambda x: -attrs[x]["count"]):
                r = attrs[k]
                lines.append("| `%s` | %d | %s |" % (k, r["count"], describe(r["values"], elems)))
            lines.append("")
        if child:
            lines.append("### 子元素")
            lines.append("")
            lines.append("| 子元素 | 出现次数 | 观测取值 |")
            lines.append("|---|---|---|")
            for k in sorted(child, key=lambda x: -child[x]["count"]):
                r = child[k]
                if r["values"]:
                    desc = describe(r["values"], elems)
                elif r["text"]:
                    desc = "空标签（容器型）"
                else:
                    desc = "无文本"
                lines.append("| `%s` | %d | %s |" % (k, r["count"], desc.replace("|", "\\|")))
            lines.append("")
    return "\n".join(lines) + "\n"



# ---------------------------------------------------------------- 属性速查
WORKSPACE = pathlib.Path.cwd()
PROP_DIR = pathlib.Path(GAME) / "Property"


def gen_property_doc() -> str:
    def text_of(node, tag):
        ele = node.find(tag)
        if ele is None or ele.text is None:
            return ""
        return ele.text.strip()

    rows = []
    for path in sorted(PROP_DIR.glob("*.xml")):
        try:
            root = ET.parse(str(path)).getroot()
        except ET.ParseError:
            continue
        for prop in root.iter("Property"):
            name = prop.get("Name", "")
            if not name:
                continue
            rows.append((
                name,
                text_of(prop, "DisplayName"),
                text_of(prop, "PropertyType"),
                text_of(prop, "BaseValue"),
                text_of(prop, "MinValue"),
                text_of(prop, "MaxValue"),
                text_of(prop, "SupportCustom"),
                text_of(prop, "Desc"),
                path.name,
            ))
    rows.sort(key=lambda r: r[0].lower())
    out = ["# 角色属性速查（自动生成）", ""]
    out.append("> 生成器：`tools/gen_field_docs.py`；数据源：原版 `Settings/Property/*.xml`。")
    out.append("> 共 %d 条。Modifier 的 `<li Name>` 只能写这里存在的属性名。" % len(rows))
    out.append("")
    out.append("| 属性名 | 中文名 | 类型 | 基础值 | 最小 | 最大 | 可自定义 | 说明 |")
    out.append("|---|---|---|---|---|---|---|---|")
    def cell(v):
        return str(v).replace("|", "\\|")

    for name, disp, ptype, base, lo, hi, custom, desc, _src in rows:
        d = re.sub(r"\s+", " ", desc).strip()
        if len(d) > 46:
            d = d[:44] + "…"
        out.append("| `%s` | %s | %s | %s | %s | %s | %s | %s |" % (
            cell(name), cell(disp or "-"), cell(ptype or "-"), cell(base or "-"),
            cell(lo or "-"), cell(hi or "-"), cell(custom or "-"), cell(d or "-")))
    out.append("")
    return "\n".join(out)


def main() -> int:
    global GAME, OUT
    argv = sys.argv[1:]
    for flag in ("--game", "--out"):
        if flag in argv:
            val = argv[argv.index(flag) + 1]
            if flag == "--game":
                GAME = os.path.join(val, "Settings") if not val.rstrip("\\/").endswith("Settings") else val
            else:
                global WORKSPACE
                WORKSPACE = pathlib.Path(val)
    docs = pathlib.Path(GAME)
    if not docs.exists():
        fail("找不到游戏目录：%s" % GAME)
        return 2

    doc = render()

    if "--stdout" in argv:
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        print(doc)
        return 0

    out_path = WORKSPACE / "docs" / "官方字段统计.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(doc, encoding="utf-8")
    print("已生成 %s（%d 字符）" % (out_path, len(doc)))

    prop_doc = gen_property_doc()
    prop_path = WORKSPACE / "docs" / "属性速查.md"
    prop_path.write_text(prop_doc, encoding="utf-8")
    print("已生成 %s（%d 行）" % (prop_path, prop_doc.count("\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())

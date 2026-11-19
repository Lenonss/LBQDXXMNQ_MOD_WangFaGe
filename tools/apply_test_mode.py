# -*- coding: utf-8 -*-
"""把衍天诀切成"测试模式"：参悟树与秘籍门槛全部拉到最低，方便实机验证。

用法：python tools/apply_test_mode.py           # 开启测试模式
      python tools/apply_test_mode.py --restore # 只还原 Lua 境界门槛

注意：界面按 <Level> 分行渲染（每行 12 格）。把所有节点压到 Qi 一行会让
其余三行全空、看起来像"界面空了"，所以这里只重排每行内的 Index，
不动 Level。
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TREE = os.path.join(ROOT, "Settings", "Practice", "Tree", "Gong_YanTian.xml")
ESO = os.path.join(ROOT, "Settings", "Esoterica", "Esoterica_YanTian.xml")
DEF = os.path.join(ROOT, "Scripts", "Gong", "YanTian", "def.lua")

LUA_GATE_FILES = [
    ("Scripts/Gong/YanTian/derive.lua", [("def.stageDerive", "def.gateDerive")]),
    ("Scripts/Gong/YanTian/guard.lua", [("def.stageFinal", "def.gateFinal")]),
    ("Scripts/Gong/YanTian/hall.lua", [("def.stageFinal", "def.gateFinal")]),
    ("Scripts/Gong/YanTian/heal.lua", [
        ("(c.stage or 0) >= def.stageFly and c.heal", "(c.stage or 0) >= def.gateFly and c.heal"),
        ("(c.stage or 0) < def.stageFly then", "(c.stage or 0) < def.gateFly then"),
    ]),
    ("Scripts/WFG/ui/main_window.lua", [
        ("WFG.YanTianDef.stageDerive", "WFG.YanTianDef.gateDerive"),
        ("WFG.YanTianDef.stageFinal", "WFG.YanTianDef.gateFinal"),
    ]),
    ("Scripts/Magic/WFG_Magics.lua", [
        ("WFG.YanTianDef.stageFly", "WFG.YanTianDef.gateFly"),
        ("WFG.YanTianDef.stageDerive", "WFG.YanTianDef.gateDerive"),
    ]),
]


def read(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def test_tree():
    s = read(TREE)
    # 1) 清空前置：任何节点都不再被前置锁住
    s = re.sub(r"<PreUnit>\s*(<li>[^<]*</li>\s*)*</PreUnit>", "<PreUnit>\n\t\t</PreUnit>", s)
    # 2) 每个境界行内的 Index 从 0 连排（保持分行，避免整行空掉）
    rows = {}

    def repl(m):
        lv = m.group(1)
        i = rows.get(lv, 0)
        rows[lv] = i + 1
        return "<Level>%s</Level>%s<Index>%d</Index>" % (lv, m.group(2), i)

    s = re.sub(r"<Level>([A-Za-z0-9]+)</Level>(\s*)<Index>\d+</Index>", repl, s)
    write(TREE, s)
    return len(re.findall(r"<Node ", s)), rows


def test_eso():
    s = read(ESO)
    s = re.sub(r"<GLevel>[A-Za-z0-9]+</GLevel>", "<GLevel>Qi</GLevel>", s)
    s = re.sub(r"<Difficulty>\d+</Difficulty>", "<Difficulty>1</Difficulty>", s)
    write(ESO, s)
    return len(re.findall(r"<Esoterica Name=", s))


def patch_lua(test_mode):
    changed = []
    for rel, pairs in LUA_GATE_FILES:
        p = os.path.join(ROOT, rel.replace("/", os.sep))
        s = read(p)
        o = s
        for a, b in pairs:
            s = s.replace(a, b) if test_mode else s.replace(b, a)
        if s != o:
            write(p, s)
            changed.append(rel)

    s = read(DEF)
    start, end = "-- >>> WFG_TEST_MODE", "-- <<< WFG_TEST_MODE"
    block = (
        start + "\n"
        "-- 测试模式：true 时所有境界门槛归零（参悟树/秘籍门槛已下放练气期），\n"
        "-- 仅为实机验证用；正式版改 false 或执行 tools/apply_test_mode.py --restore。\n"
        "D.test = " + ("true" if test_mode else "false") + "\n"
        "D.gateFly, D.gateDerive, D.gateGuard, D.gateFinal =\n"
        "\tD.stageFly, D.stageDerive, D.stageGuard, D.stageFinal\n"
        "if D.test then\n"
        "\tD.gateFly, D.gateDerive, D.gateGuard, D.gateFinal = 0, 0, 0, 0\n"
        "end\n" + end
    )
    if start in s:
        s = re.sub(re.escape(start) + r".*?" + re.escape(end), block, s, flags=re.S)
    else:
        anchor = "D.stageFinal  = 12   -- 天门\n"
        assert anchor in s, "def.lua 锚点丢失，请手工插入测试模式块"
        s = s.replace(anchor, anchor + "\n" + block + "\n")
    write(DEF, s)
    return changed


if __name__ == "__main__":
    if "--restore" in sys.argv:
        patch_lua(False)
        print("Lua 境界门槛已还原为正式值（XML 未改动）")
    else:
        nodes, rows = test_tree()
        n = test_eso()
        ch = patch_lua(True)
        print("参悟树 %d 个节点：前置已清空，Index 按行重排 %s" % (nodes, rows))
        print("秘籍 %d 本 -> GLevel=Qi / Difficulty=1" % n)
        print("Lua 门槛 -> gate*（测试期 0）：%s" % (", ".join(ch) if ch else "无改动"))

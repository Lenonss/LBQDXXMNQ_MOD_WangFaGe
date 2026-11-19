# -*- coding: utf-8 -*-
"""
AC​S（了不起的修仙模拟器 v0.995）功法配置字段级调研脚本（只读）。

用途：
  统计原版 Settings/Practice/Gong 全部功法、官方 Example、第三方 mod、创意工坊
  以及本 mod「万法阁」的 Gong / Tree / Esoterica / Modifier 配置，输出：
    - report.json  机器可读的全量统计
    - report.txt   人读摘要
  供 docs/调研-功法字段差异.md 引用。

约定：所有 XML 以 utf-8-sig 读取（原版文件带 BOM）。
运行：python tools/survey_gong.py
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

GAME = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator"
WS = r"E:\Program Files (x86)\Steam\steamapps\workshop\content\955900"
MODS = os.path.join(GAME, "Mods")
OURS = r"D:\Work\MOD_Dev\了不起的修仙模拟器\万法阁"
OUT_DIR = os.path.join(OURS, "tools")
REPORT_JSON = os.path.join(OUT_DIR, "survey_report.json")
REPORT_TXT = os.path.join(OUT_DIR, "survey_report.txt")

# 原版 Gong 目录里除 .xml 外的子目录：Body / God 各有功法
VANILLA_GONG_DIR = os.path.join(GAME, "Settings", "Practice", "Gong")
VANILLA_TREE_DIR = os.path.join(GAME, "Settings", "Practice", "Tree")
VANILLA_ESO = os.path.join(GAME, "Settings", "Esoterica")
VANILLA_MOD = os.path.join(GAME, "Settings", "Modifiers")
VANILLA_PROP = os.path.join(GAME, "Settings", "Property")


def load(path):
    with open(path, "rb") as f:
        raw = f.read()
    return ET.fromstring(raw.decode("utf-8-sig"))


def walk_files(root, exts=(".xml",)):
    out = []
    if not os.path.isdir(root):
        return out
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in (".git",)]
        for fn in fns:
            if fn.lower().endswith(exts):
                out.append(os.path.join(dp, fn))
    return sorted(out)


def short(path):
    """相对某个基准的展示路径。"""
    for base, tag in ((GAME, "GAME"), (WS, "WS"), (OURS, "OURS")):
        if path.startswith(base):
            return tag + "/" + os.path.relpath(path, base).replace("\\", "/")
    return path.replace("\\", "/")


# ---------------------------------------------------------------- 采集来源
def collect_sources():
    src = {}

    van = []
    for p in walk_files(VANILLA_GONG_DIR):
        rel = os.path.relpath(p, VANILLA_GONG_DIR).replace("\\", "/")
        if rel.lower().endswith(".xml"):
            van.append(p)
    src["vanilla"] = van

    # 官方 Example（只取 Settings 下、非 Language 镜像）
    ex = [p for p in walk_files(os.path.join(MODS, "Example"))
          if os.sep + "Settings" + os.sep in p and "Language" not in p]
    src["example"] = ex

    third = []
    for name in ("JianLaiGongFa", "诸天万法"):
        third += walk_files(os.path.join(MODS, name))
    src["thirdparty"] = third

    ws = []
    for d in sorted(os.listdir(WS)) if os.path.isdir(WS) else []:
        p = os.path.join(WS, d)
        if os.path.isdir(p):
            ws += walk_files(p)
    src["workshop"] = ws

    src["ours"] = walk_files(os.path.join(OURS, "Settings"))
    return src


# ---------------------------------------------------------------- 通用节点统计
def tag_stats(node, counter, attr_counter, path=""):
    """递归统计某棵子树里所有元素标签与属性。"""
    for ch in list(node):
        counter[ch.tag] += 1
        for a in ch.attrib:
            attr_counter[(ch.tag, a)] += 1
        tag_stats(ch, counter, attr_counter, path + "/" + ch.tag)


def get_gong_roots(files):
    """返回 [(path, root_tag, [Gong,...])]。"""
    out = []
    for p in files:
        try:
            r = load(p)
        except Exception as e:  # noqa: BLE001
            out.append((p, "PARSE_ERROR:" + str(e), []))
            continue
        gongs = []
        if r.tag == "Gong":
            gongs = [r]
        else:
            gongs = r.findall(".//Gong")
        out.append((p, r.tag, gongs))
    return out


def text_of(el, tag, default=None):
    if el is None:
        return default
    c = el.find(tag)
    if c is None:
        return default
    return (c.text or "").strip()


def survey_gong(files, label):
    data = {
        "label": label,
        "file_count": len(files),
        "gong_count": 0,
        "root_tags": Counter(),
        "child_tags": Counter(),
        "child_missing": Counter(),   # 该 Gong 未出现的子元素
        "gong_attrs": Counter(),
        "element_kind": Counter(),
        "gong_kind": Counter(),
        "practice_type": Counter(),
        "skill_set": Counter(),
        "empty_skill_set": 0,
        "hide": Counter(),
        "stage_level": Counter(),
        "stage_level_by_gong": [],
        "stage_name_pattern": Counter(),
        "stage_child_tags": Counter(),
        "neck_kind": Counter(),
        "neck_attrs": Counter(),
        "neck_child_by_kind": defaultdict(Counter),
        "neck_child_all": Counter(),
        "neck_loc": Counter(),
        "value_range": [],
        "error": [],
        "files": [],
    }
    roots = get_gong_roots(files)
    for p, root_tag, gongs in roots:
        if root_tag.startswith("PARSE_ERROR"):
            data["error"].append((short(p), root_tag))
            continue
        data["root_tags"][root_tag] += 1
        for g in gongs:
            data["gong_count"] += 1
            data["files"].append(short(p))
            for a in g.attrib:
                data["gong_attrs"][a] += 1
            kids = [c.tag for c in list(g)]
            for k in kids:
                data["child_tags"][k] += 1
            for known in ("DisplayName", "Desc", "SelectDesc", "FiveBaseNeed",
                          "SkillSetName", "ElementKind", "Skill", "Stages",
                          "GongKind", "Hide", "PracticeType", "Name"):
                if known not in kids and known != "Name":
                    data["child_missing"][known] += 1
            data["element_kind"][text_of(g, "ElementKind", "<MISSING>")] += 1
            data["gong_kind"][text_of(g, "GongKind", "<MISSING>")] += 1
            data["practice_type"][g.attrib.get("PracticeType", "<none>")] += 1
            ss = text_of(g, "SkillSetName", "<MISSING>")
            if ss == "":
                data["empty_skill_set"] += 1
                data["skill_set"]["<EMPTY>"] += 1
            else:
                data["skill_set"][ss] += 1
            data["hide"][text_of(g, "Hide", "<absent>")] += 1
            st = g.find("Stages")
            levels = []
            if st is not None:
                for s in st.findall("Stage"):
                    lv = s.attrib.get("Level", "<none>")
                    data["stage_level"][lv] += 1
                    levels.append(lv)
                    nm = s.attrib.get("Name", "")
                    data["stage_name_pattern"][re.sub(r"\d+", "#", nm)] += 1
                    for c in list(s):
                        data["stage_child_tags"][c.tag] += 1
                    v = text_of(s, "Value")
                    if v:
                        try:
                            data["value_range"].append(int(v))
                        except ValueError:
                            pass
                    for n in s.findall(".//Neck"):
                        kind = n.attrib.get("Kind", "<none>")
                        data["neck_kind"][kind] += 1
                        for a in n.attrib:
                            data["neck_attrs"][a] += 1
                        try:
                            data["neck_loc"][round(float(n.attrib.get("Location", "-1")), 2)] += 1
                        except ValueError:
                            pass
                        for c in list(n):
                            data["neck_child_all"][c.tag] += 1
                            data["neck_child_by_kind"][kind][c.tag] += 1
            data["stage_level_by_gong"].append(
                {"file": short(p), "name": g.attrib.get("Name"), "levels": levels,
                 "stages": len(levels)})

    # Counter 里的 defaultdict 需要转 dict
    data["neck_child_by_kind"] = {k: dict(v) for k, v in data["neck_child_by_kind"].items()}
    for k in ("root_tags", "child_tags", "child_missing", "gong_attrs", "element_kind",
              "gong_kind", "practice_type", "skill_set", "hide", "stage_level",
              "stage_name_pattern", "stage_child_tags", "neck_kind", "neck_attrs",
              "neck_child_all"):
        data[k] = dict(data[k])
    data["neck_loc"] = {str(k): v for k, v in sorted(data["neck_loc"].items())}
    if data["value_range"]:
        data["value_range_stats"] = {
            "min": min(data["value_range"]), "max": max(data["value_range"]),
            "count": len(data["value_range"])}
    data.pop("value_range", None)
    return data


# ---------------------------------------------------------------- Esoterica
def survey_esoterica(files, label):
    d = {"label": label, "file_count": len(files), "count": 0,
         "child_tags": Counter(), "type": Counter(), "star": Counter(),
         "glevel": Counter(), "difficulty": Counter(), "icon": Counter(),
         "element": Counter(), "magics_count": Counter(), "modifier_count": Counter(),
         "has_magics": 0, "has_modifier": 0, "by_type": {}, "errors": []}
    for p in files:
        try:
            r = load(p)
        except Exception as e:  # noqa: BLE001
            d["errors"].append((short(p), str(e)))
            continue
        for e in r.findall(".//Esoterica"):
            d["count"] += 1
            for c in list(e):
                d["child_tags"][c.tag] += 1
            d["type"][text_of(e, "Type", "<MISSING>")] += 1
            _t = text_of(e, "Type", "<MISSING>")
            bt = d["by_type"].setdefault(_t, Counter())
            bt["_n"] += 1
            for fld in ("StarLevel", "Icon", "Difficulty", "GLevel", "Element",
                        "Magics", "Modifier", "Desc", "EffectDesc", "Hide"):
                if e.find(fld) is not None:
                    bt[fld] += 1
            d["star"][text_of(e, "StarLevel", "<MISSING>")] += 1
            d["glevel"][text_of(e, "GLevel", "<MISSING>")] += 1
            d["difficulty"][text_of(e, "Difficulty", "<MISSING>")] += 1
            d["element"][text_of(e, "Element", "<MISSING>")] += 1
            ic = text_of(e, "Icon", "<MISSING>")
            d["icon"][ic] += 1
            m = e.find("Magics")
            if m is not None:
                d["has_magics"] += 1
                d["magics_count"][len(m.findall("li"))] += 1
            else:
                d["magics_count"]["<none>"] += 1
            mo = e.find("Modifier")
            if mo is not None:
                d["has_modifier"] += 1
                if (mo.text or "").strip():
                    d["modifier_count"][1] += 1
                d["modifier_count"]["<children %d>" % len(list(mo))] += 1
            else:
                d["modifier_count"]["<none>"] += 1
    for k in ("child_tags", "type", "star", "glevel", "difficulty", "icon",
              "element", "magics_count", "modifier_count"):
        d[k] = dict(d[k])
    d["by_type"] = {t: dict(c) for t, c in d["by_type"].items()}
    return d


# ---------------------------------------------------------------- Modifier
def survey_modifier(files, label):
    d = {"label": label, "file_count": len(files), "count": 0,
         "type": Counter(), "has_maxstack": 0, "has_duration": 0, "has_display": 0,
         "maxstack_val": Counter(), "duration_val": Counter(), "display_val": Counter(),
         "prop_add": Counter(), "prop_names": Counter(), "child_tags": Counter(),
         "prop_counts": Counter(), "errors": []}
    for p in files:
        try:
            r = load(p)
        except Exception as e:  # noqa: BLE001
            d["errors"].append((short(p), str(e)))
            continue
        for m in r.findall(".//Modifier"):
            d["count"] += 1
            for c in list(m):
                d["child_tags"][c.tag] += 1
            d["type"][m.attrib.get("Type", "<none>")] += 1
            ms = m.find("MaxStack")
            if ms is not None:
                d["has_maxstack"] += 1
                d["maxstack_val"][(ms.text or "").strip()] += 1
            du = m.find("Duration")
            if du is not None:
                d["has_duration"] += 1
                d["duration_val"][(du.text or "").strip()] += 1
            di = m.find("Display")
            if di is not None:
                d["has_display"] += 1
                d["display_val"][(di.text or "").strip()] += 1
            props = m.find("Properties")
            n = 0
            if props is not None:
                lis = props.findall("li")
                n = len(lis)
                for li in lis:
                    d["prop_names"][li.attrib.get("Name", "<none>")] += 1
                    for a in li.attrib:
                        if a != "Name":
                            d["prop_add"][a] += 1
            d["prop_counts"][n] += 1
    for k in ("type", "prop_add", "prop_names", "child_tags", "prop_counts",
              "maxstack_val", "duration_val", "display_val"):
        d[k] = dict(d[k])
    return d


# ---------------------------------------------------------------- 属性全量表
def collect_property_names():
    names = set()
    files = walk_files(VANILLA_PROP)
    for p in files:
        try:
            r = load(p)
        except Exception:  # noqa: BLE001
            continue
        for el in r.iter():
            n = el.attrib.get("Name")
            if n and el.tag in ("Property", "li", "Prop"):
                names.add(n)
    return sorted(names), len(files)


# ---------------------------------------------------------------- 参悟树
def survey_tree(files, label):
    """参悟树 Node 统计：子元素频次、Level 分布、Index 范围、DaoHang/Depth。"""
    d = {"label": label, "file_count": len(files), "nodes": 0,
         "child_tags": Counter(), "level": Counter(), "index": Counter(),
         "line_len": Counter(), "dao_hang": Counter(), "depth": Counter(),
         "gong_ref": Counter(), "attrs": Counter()}
    for p in files:
        try:
            r = load(p)
        except Exception:  # noqa: BLE001
            continue
        for n in r.iter("Node"):
            d["nodes"] += 1
            for a in n.attrib:
                d["attrs"][a] += 1
            for c in list(n):
                d["child_tags"][c.tag] += 1
            lv = text_of(n, "Level", "<MISSING>")
            d["level"][lv] += 1
            try:
                d["index"][int(text_of(n, "Index"))] += 1
            except Exception:  # noqa: BLE001
                d["index"][text_of(n, "Index", "<MISSING>")] += 1
            ln_ = text_of(n, "Line")
            if ln_ is not None:
                d["line_len"][len(ln_.split(","))] += 1
            d["dao_hang"][text_of(n, "DaoHang", "<MISSING>")] += 1
            d["depth"][text_of(n, "Depth", "<MISSING>")] += 1
            d["gong_ref"][n.attrib.get("Gong", "<none>")] += 1
    for k in ("child_tags", "level", "index", "line_len", "dao_hang", "depth", "attrs"):
        d[k] = dict(d[k])
    d["gong_ref"] = dict(d["gong_ref"])
    return d


# ---------------------------------------------------------------- 属性值域
def prop_value_stats(files, targets):
    """给定属性名，返回原版 Modifier 里 AddV/AddP/BAddV/BAddP 的取值样本。"""
    out = {t: Counter() for t in targets}
    for p in files:
        try:
            r = load(p)
        except Exception:  # noqa: BLE001
            continue
        for m in r.iter("Modifier"):
            props = m.find("Properties")
            if props is None:
                continue
            for li in props.findall("li"):
                nm = li.attrib.get("Name")
                if nm in out:
                    for a, v in li.attrib.items():
                        if a != "Name":
                            out[nm]["%s=%s" % (a, v)] += 1
    return {k: dict(v) for k, v in out.items()}


# ---------------------------------------------------------------- 行号定位
def lxml_root(path):
    """用 lxml 读同一份 XML，保留 sourceline；失败返回 None。"""
    try:
        from lxml import etree
    except Exception:  # noqa: BLE001
        return None
    try:
        with open(path, "rb") as f:
            data = f.read()
        if data.startswith(b"\xef\xbb\xbf"):
            data = data[3:]
        return etree.fromstring(data)
    except Exception:  # noqa: BLE001
        return None


def ln(el):
    return getattr(el, "sourceline", None) or 0


def locate_ours(ours_files):
    """输出我们 4 个文件的关键节点 + 行号，供差异表引用。"""
    out = []
    for p in ours_files:
        r = lxml_root(p)
        if r is None:
            continue
        name = short(p)
        out.append("\n--- %s (%d lines)" % (name, file_len(p)))
        gong = next((x for x in r.iter("Gong")), None)
        if gong is not None:
            r = gong
        if r.tag == "Gong":
            out.append("  L%d <Gong %s>" % (ln(r), dict(r.attrib)))
            for c in r:
                if c.tag == "SkillSetName":
                    out.append("  L%d <SkillSetName>%r 空=%s"
                               % (ln(c), c.text, not (c.text or "").strip()))
                elif c.tag in ("Stages",):
                    for st in c.findall("Stage"):
                        necks = st.find("Necks")
                        nk = [(n.attrib.get("Kind"), n.attrib.get("Location"), ln(n))
                              for n in (necks.findall("Neck") if necks is not None else [])]
                        vals = [x.text for x in st.findall("Value")]
                        out.append("  L%d Stage@Level=%s Name=%s Value=%s Necks=%d"
                                   % (ln(st), st.attrib.get("Level"), st.attrib.get("Name"),
                                      ",".join(vals), len(nk)))
                        for kind, loc, l2 in nk:
                            out.append("        L%d Neck Kind=%s Location=%s" % (l2, kind, loc))
                elif len(list(c)) > 0:
                    out.append("  L%d <%s> children=%d" % (ln(c), c.tag, len(list(c))))
                else:
                    t = (c.text or "").strip()
                    out.append("  L%d <%s>%s" % (ln(c), c.tag, (" = " + t[:60]) if t else ""))
        elif r.find(".//Esoterica") is not None and r.find(".//Node") is None:
            for e in r.findall(".//Esoterica"):
                f = {}
                for k in ("StarLevel", "GLevel", "Difficulty", "Type", "Icon",
                          "Element", "Modifier", "Magics", "EffectDesc"):
                    x = e.find(k)
                    if x is not None:
                        f[k] = (ln(x), (x.text or "").strip()[:40], len(list(x)))
                out.append("  L%d <Esoterica %s> %s" % (ln(e), dict(e.attrib), f))
        elif r.find(".//Modifier") is not None:
            for m in r.findall(".//Modifier"):
                props = m.find("Properties")
                plist = [(li.attrib, ln(li)) for li in (props.findall("li") if props is not None else [])]
                vals = {}
                for k in ("Type", "MaxStack", "Duration", "Display"):
                    x = m.find(k)
                    if x is not None:
                        vals[k] = (ln(x), (x.text or "").strip())
                out.append("  L%d <Modifier %s> %s" % (ln(m), dict(m.attrib), vals))
                for a, l2 in plist:
                    out.append("        L%d li %s" % (l2, a))
        elif r.find(".//Node") is not None:
            for n in r.findall(".//Node"):
                f = {}
                for k in ("Level", "Index", "DaoHang", "Depth", "Esoterica", "Line", "DisplayName"):
                    x = n.find(k)
                    if x is not None:
                        f[k] = (ln(x), (x.text or "").strip()[:30])
                out.append("  L%d <%s %s> %s" % (ln(n), n.tag, dict(n.attrib), f))
        else:
            out.append("  (root=%s, 未识别的根节点)" % r.tag)
    return out


def file_len(path):
    try:
        with open(path, "rb") as f:
            return f.read().count(b"\n") + 1
    except Exception:  # noqa: BLE001
        return -1


# ---------------------------------------------------------------- 差异对比
def field_diff(ours, baseline):
    """对比单个 Gong 的子元素集合与基线（原版全量）。"""
    def fields_of(data):
        return set(data["child_tags"])
    return {
        "ours_fields": sorted(fields_of(ours)),
        "baseline_fields": sorted(fields_of(baseline)),
        "ours_only": sorted(fields_of(ours) - fields_of(baseline)),
        "baseline_only": sorted(fields_of(baseline) - fields_of(ours)),
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    src = collect_sources()

    def gong_only(files):
        out = []
        for p in files:
            try:
                r = load(p)
            except Exception:  # noqa: BLE001
                continue
            if r.tag == "Gong" or r.findall(".//Gong"):
                out.append(p)
        return out

    report = {"sources": {k: [short(p) for p in v] for k, v in src.items()}}

    report["gong"] = {}
    for label in ("vanilla", "example", "thirdparty", "workshop", "ours"):
        fs = gong_only(src[label])
        report["gong"][label] = survey_gong(fs, label)

    eso_files = {}
    for label, root in (("vanilla", VANILLA_ESO),):
        eso_files[label] = walk_files(root)
    eso_files["ours"] = [p for p in src["ours"] if "Esoterica" in p]
    eso_files["example"] = [p for p in src["example"] if "Esoterica" in p]
    eso_files["thirdparty"] = [p for p in src["thirdparty"] if "Esoterica" in p]
    report["esoterica"] = {k: survey_esoterica(v, k) for k, v in eso_files.items()}

    mod_files = {"vanilla": walk_files(VANILLA_MOD)}
    mod_files["ours"] = [p for p in src["ours"] if "Modifier" in p]
    mod_files["example"] = [p for p in src["example"] if "Modifier" in p]
    mod_files["thirdparty"] = [p for p in src["thirdparty"] if "Modifier" in p]
    report["modifier"] = {k: survey_modifier(v, k) for k, v in mod_files.items()}

    props, npropfiles = collect_property_names()
    report["property_names"] = props
    report["property_file_count"] = npropfiles

    report["field_diff"] = field_diff(report["gong"]["ours"], report["gong"]["vanilla"])

    # 参悟树
    tree_files = {"vanilla": walk_files(VANILLA_TREE_DIR)}
    tree_files["ours"] = [p for p in src["ours"] if "Tree" in p]
    tree_files["thirdparty"] = [p for p in src["thirdparty"] if "Tree" in p]
    tree_files["example"] = [p for p in src["example"] if "Tree" in p]
    report["tree"] = {k: survey_tree(v, k) for k, v in tree_files.items()}

    # 我们 Modifier 用到的属性，在原版里的取值样本
    our_props = sorted(report["modifier"]["ours"]["prop_names"])
    report["our_prop_samples"] = prop_value_stats(walk_files(VANILLA_MOD), our_props)

    with open(REPORT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)

    # ---------------- 人读摘要
    L = []
    def w(s=""):
        L.append(s)

    w("=" * 78)
    w("AC​S 功法字段调研 · 自动统计")
    w("=" * 78)
    for label in ("vanilla", "example", "thirdparty", "workshop", "ours"):
        g = report["gong"][label]
        w("\n### %s : files=%d gongs=%d" % (label, g["file_count"], g["gong_count"]))
        if g.get("error"):
            w("  ERRORS: %s" % g["error"])
        w("  root_tags: %s" % g["root_tags"])
        w("  child_tags: %s" % dict(sorted(g["child_tags"].items(), key=lambda x: -x[1])))
        w("  gong_attrs: %s" % g["gong_attrs"])
        w("  child_missing: %s" % g["child_missing"])
        w("  ElementKind: %s" % g["element_kind"])
        w("  GongKind: %s" % g["gong_kind"])
        w("  PracticeType: %s" % g["practice_type"])
        w("  SkillSetName: %s (empty=%d)" % (g["skill_set"], g["empty_skill_set"]))
        w("  Hide: %s" % g["hide"])
        w("  Stage.Level: %s" % dict(sorted(g["stage_level"].items(), key=lambda x: str(x[0]))))
        w("  StageNamePattern: %s" % g["stage_name_pattern"])
        w("  StageChildTags: %s" % dict(sorted(g["stage_child_tags"].items(), key=lambda x: -x[1])))
        w("  NeckKind: %s" % g["neck_kind"])
        w("  NeckAttrs: %s" % g["neck_attrs"])
        w("  NeckChildAll: %s" % dict(sorted(g["neck_child_all"].items(), key=lambda x: -x[1])))
        for k, v in g["neck_child_by_kind"].items():
            w("    NeckKind[%s] -> %s" % (k, dict(sorted(v.items(), key=lambda x: -x[1]))))
        w("  Value: %s" % g.get("value_range_stats"))
        w("  PerGongStages: %s" % [(x["name"], x["levels"]) for x in g["stage_level_by_gong"]])

    for label in ("vanilla", "example", "thirdparty", "ours"):
        e = report["esoterica"][label]
        w("\n### Esoterica %s : files=%d count=%d" % (label, e["file_count"], e["count"]))
        w("  tags: %s" % dict(sorted(e["child_tags"].items(), key=lambda x: -x[1])))
        w("  Type=%s" % e["type"])
        w("  StarLevel=%s" % e["star"])
        w("  GLevel=%s" % e["glevel"])
        w("  Difficulty=%s" % e["difficulty"])
        w("  Icon(unique=%d)=%s" % (len(e["icon"]), list(e["icon"].items())[:12]))
        w("  Element=%s" % e["element"])
        w("  MagicsCount=%s" % e["magics_count"])
        w("  ModifierCount=%s" % e["modifier_count"])
        for t, c in sorted(e["by_type"].items(), key=lambda x: -x[1]["_n"]):
            n = c["_n"]
            w("    Type[%s] n=%d 字段覆盖率: %s" % (
                t, n, {k: "%d/%d" % (v, n) for k, v in c.items() if k != "_n"}))

    for label in ("vanilla", "example", "thirdparty", "ours"):
        m = report["modifier"][label]
        w("\n### Modifier %s : files=%d count=%d" % (label, m["file_count"], m["count"]))
        w("  tags: %s" % dict(sorted(m["child_tags"].items(), key=lambda x: -x[1])))
        w("  Type=%s" % m["type"])
        w("  MaxStack=%d Duration=%d Display=%d" % (m["has_maxstack"], m["has_duration"], m["has_display"]))
        w("  PropAdd=%s" % m["prop_add"])
        w("  PropNameCount=%d" % len(m["prop_names"]))
        w("  PropCountsPerModifier=%s" % m["prop_counts"])
        w("  MaxStack值=%s" % m["maxstack_val"])
        w("  Duration值=%s" % m["duration_val"])
        w("  Display值=%s" % m["display_val"])

    w("\n### Property names: files=%d unique=%d" % (npropfiles, len(props)))
    w("  " + ", ".join(props))

    w("\n### Field diff (ours vs vanilla)")
    for k, v in report["field_diff"].items():
        w("  %s: %s" % (k, v))

    for label in ("vanilla", "example", "thirdparty", "ours"):
        t = report["tree"].get(label) or {}
        if not t:
            continue
        w("\n### 参悟树 %s : files=%d nodes=%d" % (label, t["file_count"], t["nodes"]))
        w("  node_attrs=%s" % t["attrs"])
        w("  child_tags=%s" % dict(sorted(t["child_tags"].items(), key=lambda x: -x[1])))
        w("  Level=%s" % t["level"])
        w("  Index=%s" % t["index"])
        w("  Line字段数=%s" % t["line_len"])
        w("  DaoHang=%s" % t["dao_hang"])
        w("  Depth=%s" % t["depth"])

    w("\n### 我们 Modifier 属性在原版中的取值样本")
    for k, v in report["our_prop_samples"].items():
        w("  %s -> %s" % (k, v))

    w("\n" + "=" * 78)
    w("附：我们 4 个文件的关键节点 + 行号（差异表引用源）")
    w("=" * 78)
    key_files = [p for p in src["ours"]
                 if ("Practice" + os.sep + "Gong" in p) or ("Practice" + os.sep + "Tree" in p)
                 or (os.sep + "Esoterica" + os.sep in p) or (os.sep + "Modifiers" + os.sep in p)]
    for line in locate_ours(key_files):
        w(line)

    txt = "\n".join(L)
    with open(REPORT_TXT, "w", encoding="utf-8") as f:
        f.write(txt)
    print(txt)
    print("\n[written] %s\n[written] %s" % (REPORT_JSON, REPORT_TXT))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

# -*- coding: utf-8 -*-
"""Scan ACS workshop mods + local mods for UI-related assets."""
import json
import os
import re
import sys

WS = r"E:\Program Files (x86)\Steam\steamapps\workshop\content\955900"
GAME_MODS = r"E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\Mods"
OUT = r"D:\Work\MOD_Dev\了不起的修仙模拟器\万法阁\docs\_scan_result.json"


def read_info(d):
    """Return (DisplayName, Author, ModVersion, raw_keys) from Info.json (BOM tolerant)."""
    p = os.path.join(d, "Info.json")
    if not os.path.isfile(p):
        # maybe nested one level
        return None
    enc = None
    for e in ("utf-8-sig", "utf-16", "gbk"):
        try:
            with open(p, "r", encoding=e) as f:
                txt = f.read()
            enc = e
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    if enc is None:
        return {"error": "decode failed"}
    try:
        j = json.loads(txt)
    except Exception as ex:
        return {"error": "json: %s" % ex, "enc": enc}
    return j


def walk_files(root):
    out = []
    for dp, dn, fn in os.walk(root):
        for f in fn:
            out.append(os.path.join(dp, f))
    return out


UI_LIB_PAT = re.compile(
    r"(uil?ib|fgui|fairygui|simplewindow|uihelper|ui_helper|uikit|uiframework|"
    r"ui_frame|windowmanager|window_manager|guilib|uilib|widget)", re.I)


def main():
    rows = []
    roots = [("workshop", WS), ("local", GAME_MODS)]
    for kind, base in roots:
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if not os.path.isdir(d):
                continue
            # some workshop dirs may contain a nested mod folder
            probe = d
            info = read_info(d)
            if info is None:
                subs = [x for x in os.listdir(d) if os.path.isdir(os.path.join(d, x))]
                found = False
                for s in subs:
                    if os.path.isfile(os.path.join(d, s, "Info.json")):
                        probe = os.path.join(d, s)
                        info = read_info(probe)
                        found = True
                        break
                if not found:
                    info = {"error": "no Info.json"}
            files = walk_files(probe)
            rel = [os.path.relpath(f, probe).replace("\\", "/") for f in files]
            fui = [r for r in rel if r.lower().endswith("fui.bytes") or r.lower().endswith(".fui")]
            window_lua = [r for r in rel if re.search(r"Scripts/Window/.*\.lua$", r, re.I)]
            uilua = [r for r in rel if re.search(r"\.lua$", r, re.I) and UI_LIB_PAT.search(
                os.path.basename(r))]
            uilua_dir = [r for r in rel if re.search(r"\.lua$", r, re.I) and UI_LIB_PAT.search(
                "/".join(r.split("/")[-3:-1]))]
            li = [r for r in rel if re.search(r"(license|licence|copying|readme|作者|声明)", os.path.basename(r), re.I)]
            disp = ""
            author = ""
            ver = ""
            if isinstance(info, dict) and "error" not in info:
                for k in ("DisplayName", "displayName", "name", "Name"):
                    if k in info:
                        disp = str(info[k])
                        break
                for k in ("Author", "author"):
                    if k in info:
                        author = str(info[k])
                        break
                for k in ("ModVersion", "version", "Version"):
                    if k in info:
                        ver = str(info[k])
                        break
            rows.append({
                "kind": kind, "id": name, "path": probe,
                "display": disp, "author": author, "version": ver,
                "info_err": (info or {}).get("error") if isinstance(info, dict) else None,
                "n_files": len(files),
                "fui": sorted(set(fui)),
                "window_lua": sorted(set(window_lua)),
                "ui_lib_lua": sorted(set(uilua + uilua_dir)),
                "legal": sorted(set(li))[:12],
                "has_settings": any(r.startswith("Settings/") for r in rel),
                "has_scripts": any(r.startswith("Scripts/") for r in rel),
            })
    # sort: most UI files first
    rows.sort(key=lambda r: (-len(r["fui"]), -len(r["window_lua"]), r["id"]))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)
    print("mods:", len(rows))
    for r in rows:
        print("%-9s %-12s fui=%d win=%d lib=%d | %s | %s" % (
            r["kind"], r["id"], len(r["fui"]), len(r["window_lua"]),
            len(r["ui_lib_lua"]), (r["display"] or "?")[:34], (r["author"] or "-")[:14]))


if __name__ == "__main__":
    main()

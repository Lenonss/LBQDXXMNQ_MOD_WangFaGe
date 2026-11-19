# -*- coding: utf-8 -*-
"""一次性补丁：物品真名链 + 素材库名字持久化 + 每帧回调 + 定点造物。

幂等：已打过的补丁会因 old 串不存在而跳过（并打印 SKIP）。
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
edits = []


def patch(rel, old, new, label):
    edits.append((rel, old, new, label))


# ---------------------------------------------------------------- item.lua
patch(
    "Scripts/WFG/item.lua",
    """local function safeGet(obj, key)
\tif obj == nil then return nil end
\tlocal ok, v = pcall(function() return obj[key] end)
\tif ok then return v end
\treturn nil
end
""",
    """local function safeGet(obj, key)
\tif obj == nil then return nil end
\tlocal ok, v = pcall(function() return obj[key] end)
\tif ok then return v end
\treturn nil
end

-- 是否纯 ASCII（用来识别「英文键名冒充显示名」）
local function isAscii(s)
\tif type(s) ~= "string" or s == "" then return false end
\treturn s:find("^[\\32-\\126]+$") ~= nil
end
""",
    "item: isAscii",
)

patch(
    "Scripts/WFG/item.lua",
    "-- 取物品/建筑定义（ThingMgr:GetDef 是唯一真实存在的入口）",
    """-- 实体显示名：走引擎原生 GetName()（物品浮窗标题同源，见 Wnd_TipPopPanel.cs:410）
-- 玩家制成品在创建时会把「材质+类型」写进 m_szName，GetName() 才拿得到，
-- 直接读 def.ThingName 只能拿到内部键名。
function I:ThingName(thing)
\tif thing == nil then return nil end
\tlocal ok, v = pcall(function() return thing:GetName() end)
\tif ok and type(v) == "string" and v ~= "" then return v end
\tlocal dn = self:DefName(thing)
\tif dn ~= nil then return self:Show(dn) end
\treturn nil
end

-- 取物品/建筑定义（ThingMgr:GetDef 是唯一真实存在的入口）""",
    "item: ThingName",
)

patch(
    "Scripts/WFG/item.lua",
    """\tif name == nil then
\t\t-- 兜底：去掉类型前缀，至少不是一串英文键名
\t\tname = defName:gsub("^Item_", ""):gsub("^Building_", ""):gsub("^WFG_", "")
\tend""",
    """\tif name == nil or name == defName or isAscii(name) then
\t\t-- 没有中文名：不再拿英文键名冒充显示名，交给调用方显示「未知物品」
\t\tname = ""
\tend""",
    "item: 去掉英文兜底",
)

patch(
    "Scripts/WFG/item.lua",
    """-- 由物品实体取显示名：优先实体自带，再回退到定义
function I:NameOf(thing)
\tif thing == nil then return "未知物品" end
\tfor _, key in ipairs({ "ThingName", "DisplayName" }) do
\t\tlocal v = safeGet(thing, key)
\t\tif type(v) == "string" and v ~= "" then return v end
\tend
\tlocal dn = self:DefName(thing)
\tif dn ~= nil then return self:DefDisplayName(dn) end
\treturn "未知物品"
end""",
    """-- 由物品实体取显示名：优先引擎 GetName()，取不到再回退到定义
function I:NameOf(thing)
\tif thing == nil then return "未知物品" end
\tlocal v = self:ThingName(thing)
\tif type(v) == "string" and v ~= "" then return v end
\treturn "未知物品"
end

-- 定义名 → 可展示名字（取不到给中文兜底，不暴露英文键名）
function I:Show(defName)
\tlocal s = self:DefDisplayName(defName or "")
\tif type(s) == "string" and s ~= "" then return s end
\treturn "未知物品"
end""",
    "item: NameOf/Show",
)

patch(
    "Scripts/WFG/item.lua",
    """function I:Create(defName, quality, count, npc)
\tif defName == nil then return false end
\tcount = math.max(1, math.floor(count or 1))
\tquality = math.max(1, math.min(5, math.floor(quality or 1)))
\tlocal key = npcKey(npc)""",
    """function I:Create(defName, quality, count, npc, gridKey)
\tif defName == nil then return false end
\tcount = math.max(1, math.floor(count or 1))
\tquality = math.max(1, math.min(5, math.floor(quality or 1)))
\tlocal key = gridKey
\tif type(key) ~= "number" or key <= 0 then key = npcKey(npc) end""",
    "item: Create 支持指定格",
)

# ---------------------------------------------------------------- derive.lua
patch(
    "Scripts/Gong/YanTian/derive.lua",
    """\tif old ~= nil and old.q >= q then
\t\t-- 已收录且品级不高于已有：免费刷新信息
\t\tif not silent then log("%s 已在素材库中（品级 %d），无需重复解析", defName, old.q) end
\t\treturn true, "已收录"
\tend""",
    """\tif old ~= nil and old.q >= q then
\t\t-- 已收录且品级不高于已有：免费刷新信息（顺便补上显示名）
\t\told.name = WFG.item:NameOf(thing)
\t\tif not silent then log("%s 已在素材库中（品级 %d），无需重复解析", defName, old.q) end
\t\treturn true, "已收录"
\tend""",
    "derive: 重复解析补名",
)

patch(
    "Scripts/Gong/YanTian/derive.lua",
    """\tc.lib[defName] = { q = q, lv = lv, n = (old and old.n or 0) + 1 }
\tlog("解析 %s（%d 阶 / 品级 %d），消耗灵气 %d", defName, lv, q, cost)
\treturn true, string.format("解析成功：%s（品级 %d）", WFG.item:DefDisplayName(defName), q)""",
    """\tc.lib[defName] = {
\t\tq = q, lv = lv,
\t\tn = (old and old.n or 0) + 1,
\t\tname = WFG.item:NameOf(thing),
\t}
\tlog("解析 %s（%d 阶 / 品级 %d），消耗灵气 %d", defName, lv, q, cost)
\treturn true, string.format("解析成功：%s（品级 %d）", WFG.item:Show(defName), q)""",
    "derive: 解析存名",
)

patch(
    "Scripts/Gong/YanTian/derive.lua",
    """-- 从素材库创造
function D:Create(M, npc, defName, count)""",
    """-- 从素材库创造（gridKey 可选：指定落点格；不传则落在施法者脚下）
function D:Create(M, npc, defName, count, gridKey)""",
    "derive: Create 签名",
)

patch(
    "Scripts/Gong/YanTian/derive.lua",
    """\tif not WFG.item:Create(defName, e.q, count, npc) then
\t\treturn false, "创造失败（造物接口异常，详见日志）"
\tend
\tWFG:Safe(function() npc:AddLing(-cost) end)
\tlog("创造 %s × %d（品级 %d），消耗灵气 %d", defName, count, e.q, cost)
\treturn true, string.format("创造成功：%s × %d", WFG.item:DefDisplayName(defName), count)""",
    """\tif not WFG.item:Create(defName, e.q, count, npc, gridKey) then
\t\treturn false, "创造失败（造物接口异常，详见日志）"
\tend
\tWFG:Safe(function() npc:AddLing(-cost) end)
\tlog("创造 %s × %d（品级 %d），消耗灵气 %d", defName, count, e.q, cost)
\treturn true, string.format("创造成功：%s × %d", WFG.item:Show(defName), count)""",
    "derive: Create 传落点",
)

patch(
    "Scripts/Gong/YanTian/derive.lua",
    "-- 素材库列表（按等阶、定义名排序）",
    """-- 只算不扣：给创造确认窗用的报价（数量、消耗、是否够）
function D:QuoteCreate(M, npc, defName, count)
\tlocal def = WFG.YanTianDef
\tlocal c = M ~= nil and M:Char(npc, true) or nil
\tlocal out = { ok = false, reason = "", cost = 0, ling = 0, maxLing = 0, enough = false, maxBatch = 0 }
\tif c == nil then out.reason = "未找到角色数据" return out end
\tlocal e = c.lib and c.lib[defName]
\tif e == nil then out.reason = "素材库中没有此物" return out end
\tif (c.stage or 0) < def.gateDerive then out.reason = "尚未踏入衍天境" return out end

\tcount = math.max(1, math.floor(count or 1))
\tlocal maxBatch = def:BatchMax(c.stage)
\tif count > maxBatch then out.reason = string.format("单次最多创造 %d 件", maxBatch) return out end

\tlocal cost = def:CreateCost(e.lv, e.q) * count
\tif count >= 10 then cost = math.floor(cost * 0.9) end
\tout.ok = true
\tout.count = count
\tout.cost = cost
\tout.quality = e.q
\tout.maxBatch = maxBatch
\tout.ling = WFG:Ling(npc)
\tout.maxLing = WFG:MaxLing(npc)
\tout.enough = out.ling >= cost
\treturn out
end

-- 素材库列表（按等阶、定义名排序）""",
    "derive: QuoteCreate",
)

patch(
    "Scripts/Gong/YanTian/derive.lua",
    """\t\ttb[#tb + 1] = { name = WFG.item:DefDisplayName(defName), defName = defName, q = e.q, lv = e.lv, n = e.n or 0 }""",
    """\t\ttb[#tb + 1] = {
\t\t\tname = (e.name ~= nil and e.name ~= "") and e.name or WFG.item:Show(defName),
\t\t\tdefName = defName, q = e.q, lv = e.lv, n = e.n or 0,
\t\t}""",
    "derive: List 用库内名字",
)

# ---------------------------------------------------------------- module.lua
patch(
    "Scripts/Gong/YanTian/module.lua",
    """\t\t\tlib[#lib + 1] = defName .. "|" .. tostring(v.q or 1) .. "|" .. tostring(v.lv or 0)""",
    """\t\t\tlocal nm = tostring(v.name or ""):gsub("|", "/")
\t\t\tlib[#lib + 1] = defName .. "|" .. tostring(v.q or 1) .. "|" .. tostring(v.lv or 0) .. "|" .. nm""",
    "module: 存档写名字",
)

patch(
    "Scripts/Gong/YanTian/module.lua",
    """\t\t\tif #parts >= 3 then
\t\t\t\tlib[parts[1]] = { q = tonumber(parts[2]) or 1, lv = tonumber(parts[3]) or 0 }
\t\t\telseif #parts == 1 then
\t\t\t\tlib[parts[1]] = { q = 1, lv = 0 }
\t\t\tend""",
    """\t\t\tif #parts >= 3 then
\t\t\t\tlib[parts[1]] = {
\t\t\t\t\tq = tonumber(parts[2]) or 1,
\t\t\t\t\tlv = tonumber(parts[3]) or 0,
\t\t\t\t\tname = parts[4],
\t\t\t\t}
\t\t\telseif #parts == 1 then
\t\t\t\tlib[parts[1]] = { q = 1, lv = 0 }
\t\t\tend""",
    "module: 读档读名字",
)

# ---------------------------------------------------------------- core.lua
patch(
    "Scripts/WFG/core.lua",
    """------------------------------------------------------------------------
-- 加载顺序无关：core 若晚于模块加载，把提前登记 pending 的模块补注册""",
    """------------------------------------------------------------------------
-- 每帧回调：选点等需要逐帧采样的场景（定时器会漏掉 GetMouseButtonDown）
------------------------------------------------------------------------
WFG.stepHooks = WFG.stepHooks or {}

function WFG:OnStep(fn)
\tif type(fn) ~= "function" then return end
\ttable.insert(WFG.stepHooks, fn)
\treturn fn
end

function WFG:RemoveStep(fn)
\tfor i = #WFG.stepHooks, 1, -1 do
\t\tif WFG.stepHooks[i] == fn then table.remove(WFG.stepHooks, i) end
\tend
end

function WFG:StepAll(dt)
\tlocal list = WFG.stepHooks
\tfor i = 1, #list do
\t\tlocal ok, err = pcall(list[i], dt)
\t\tif not ok then WFG:Error("step.hook", err) end
\tend
end

------------------------------------------------------------------------
-- 加载顺序无关：core 若晚于模块加载，把提前登记 pending 的模块补注册""",
    "core: step hooks",
)

# ---------------------------------------------------------------- boot.lua
patch(
    "Scripts/WFG/boot.lua",
    """function tbWG:OnStep(dt)
\tWFG:StepTimers(dt)
end""",
    """function tbWG:OnStep(dt)
\tWFG:StepTimers(dt)
\tif WFG.StepAll ~= nil then WFG:StepAll(dt) end
end""",
    "boot: 每帧派发",
)


def main():
    dry = "--dry" in sys.argv
    fails = 0
    for rel, old, new, label in edits:
        p = ROOT / rel
        text = p.read_text(encoding="utf-8")
        if new in text:
            print(f"SKIP  {label}  (already applied)")
            continue
        cnt = text.count(old)
        if cnt != 1:
            print(f"FAIL  {label}  (matched {cnt})")
            fails += 1
            continue
        if not dry:
            p.write_text(text.replace(old, new, 1), encoding="utf-8")
        print(f"OK    {label}")
    print(f"\n{len(edits)} edits, {fails} failed{', DRY RUN' if dry else ''}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

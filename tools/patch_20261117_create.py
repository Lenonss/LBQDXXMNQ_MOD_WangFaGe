# -*- coding: utf-8 -*-
import io, sys

def read(p):
    with io.open(p, encoding="utf-8") as f: return f.read()
def write(p, s):
    with io.open(p, "w", encoding="utf-8", newline="\n") as f: f.write(s)

def sub(s, old, new, path, expect=1):
    n = s.count(old)
    if n != expect:
        print("FAIL %s expect %d got %d :: %r" % (path, expect, n, old[:60])); return s, False
    print("ok   %s" % path)
    return s.replace(old, new), True

okall = True

# 1. 解析窗：用收录时记下的游戏名
p = "Scripts/WFG/ui/derive_window.lua"
s = read(p)
s, a = sub(s, 'row("物品", WFG.item:DefDisplayName(q.defName or ""))',
              'row("物品", q.name or WFG.item:Show(q.defName or ""))', p)
okall &= a
write(p, s)

# 2. 主面板三处取名
p = "Scripts/WFG/ui/main_window.lua"
s = read(p)
for old, new in [
    ('col(C_OK, e.name or WFG.item:DefDisplayName(e.defName or "")),',
     'col(C_OK, e.name or WFG.item:Show(e.defName or "")),'),
    ('string.format("选定素材：%s\\n以灵气重构其形，需多少件？", WFG.item:DefDisplayName(defName)),',
     'string.format("选定素材：%s\\n以灵气重构其形，需多少件？", WFG.item:Show(defName)),'),
    ('string.format("%s（品级%d）", e.name or WFG.item:DefDisplayName(e.defName or ""), e.q)',
     'string.format("%s（品级%d）", e.name or WFG.item:Show(e.defName or ""), e.q)'),
]:
    s, a = sub(s, old, new, p); okall &= a
write(p, s)

# 3. 神通 XML：新增「衍天·创造」
p = "Settings/Practice/Magic/Magic_YanTian.xml"
s = read(p)
block = """		<!-- 衍天：创造物品（独立界面）-->
		<Magic Name="WFG_Magic_Create" Type="Class">
			<DisplayName>衍天·创造</DisplayName>
			<Desc>打开素材库，择物、择量，再于地上择一处落点，以灵气重铸之。</Desc>
			<Icon>res\\Sprs\\ui\\icon_jichu</Icon>
			<Kind>None</Kind>
			<CostLing>0</CostLing>
			<Penalty>0</Penalty>
			<Param1>4</Param1>
			<SelectMode>None</SelectMode>
			<ClassName>WFG_Magic_Create</ClassName>
		</Magic>

"""
s, a = sub(s, "\t</List>\n</Magics>", block + "\t</List>\n</Magics>", p); okall &= a
write(p, s)

# 4. 秘籍：创造本挂上神通
p = "Settings/Esoterica/Esoterica_YanTian.xml"
s = read(p)
old = """		<EffectDesc>[size=10][color=#D06508]习得神通：衍天·创造\\n消耗灵气，从素材库中创造已解析的物品，可批量。[/color][/size]
	</Esoterica>"""
new = """		<EffectDesc>[size=10][color=#D06508]习得神通：衍天·创造\\n消耗灵气，从素材库中创造已解析的物品，可批量。[/color][/size]
		<Magics>
			<li>WFG_Magic_Create</li>
		</Magics>
	</Esoterica>"""
s, a = sub(s, old, new, p); okall &= a
write(p, s)

# 5. Lua 神通处理
p = "Scripts/Magic/WFG_Magics.lua"
s = read(p)
block = """------------------------------------------------------------------
-- 衍天 · 创造
------------------------------------------------------------------
local M_Create = tbTable:GetMagic("WFG_Magic_Create")

function M_Create:EnableCheck(npc)
	if not isYanTian(npc) then return false end
	local mod = WFG:GetModule("yantian")
	if mod == nil then return false end
	local c = mod:Char(npc, false)
	return c ~= nil and (c.stage or 0) >= WFG.YanTianDef.gateDerive
end

function M_Create:MagicEnter(IDs, IsThing)
	local ok, err = pcall(function() WFG.ui.create:Open(self.bind) end)
	if not ok then
		WFG:Error("magic.create", err)
		msgbox("创造界面打开失败（详见日志）", "衍天")
		return -1
	end
	return 1
end

function M_Create:MagicStep(dt, duration)
	return 1
end

return true"""
s, a = sub(s, "return true", block, p); okall &= a
write(p, s)

print("ALL_OK" if okall else "SOME_FAILED")

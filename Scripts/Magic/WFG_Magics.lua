--[[
    万法阁 · 衍天诀神通集合
    四个 Class 型神通同在此文件注册：面板 / 自愈开关 / 衍天解析 / 主动渡劫。
]]

local tbTable = GameMain:GetMod("MagicHelper")

local function isYanTian(npc)
	local ok, r = pcall(function() return WFG.npc:GetGongName(npc) == WFG.YanTianDef.gong end)
	if not ok then return false end
	return r == true
end

local function msgbox(text, title)
	pcall(function() world:ShowMsgBox(text, title or "万法阁") end)
	WFG:Log("[神通] %s", tostring(text))
end

------------------------------------------------------------------
-- 万法阁面板
------------------------------------------------------------------
local M_Panel = tbTable:GetMagic("WFG_Magic_Panel")

function M_Panel:EnableCheck(npc)
	return isYanTian(npc)
end

function M_Panel:MagicEnter(IDs, IsThing)
	WFG.ui:Show("home")
	return 1
end

function M_Panel:MagicStep(dt, duration)
	return 1
end

------------------------------------------------------------------
-- 凝练衍天珠：打开数量选择窗
------------------------------------------------------------------
local M_NingZhu = tbTable:GetMagic("WFG_Magic_NingZhu")

function M_NingZhu:EnableCheck(npc)
	return isYanTian(npc)
end

function M_NingZhu:MagicEnter(IDs, IsThing)
	local npc = self.bind
	if npc == nil and WFG.ui.TargetNpc ~= nil then npc = WFG.ui:TargetNpc() end
	local ok, err = pcall(function() WFG.ui.ningzhu:Open(npc) end)
	if not ok then
		WFG:Error("magic.ningzhu", err)
		msgbox("凝练衍天珠界面打开失败（详见日志）")
		return -1
	end
	return 1
end

function M_NingZhu:MagicStep(dt, duration)
	return 1
end

------------------------------------------------------------------
-- 本命法宝：旧版神通（已废弃，仅保留定义兼容旧存档）
-- 共享建筑的交互已移到「衍天数据中心 / 衍天能源中心」建筑上的「管理」按钮。
------------------------------------------------------------------
local M_Hall = tbTable:GetMagic("WFG_Magic_Hall")

function M_Hall:EnableCheck(npc)
	return false
end

function M_Hall:MagicEnter(IDs, IsThing)
	return -1
end

function M_Hall:MagicStep(dt, duration)
	return 1
end

------------------------------------------------------------------
-- 自愈程序 启停
------------------------------------------------------------------
local function bindHeal(M)
	if M == nil then return end

function M:EnableCheck(npc)
	if not isYanTian(npc) then return false end
	local mod = WFG:GetModule("yantian")
	if mod == nil then return false end
	local c = mod:Char(npc, false)
	return c ~= nil and (c.stage or 0) >= WFG.YanTianDef.gateFly
end

function M:MagicEnter(IDs, IsThing)
	local mod = WFG:GetModule("yantian")
	WFG:Log("[自愈程序] 收到启停指令 bind=%s", tostring(self.bind ~= nil and WFG.npc:Id(self.bind) or "nil"))
	local ok, res, text = pcall(function() return WFG.YanTian.heal:Toggle(mod, self.bind) end)
	if ok and res then
		-- 只切换、不弹窗：按钮文案与图标本身就是状态
		WFG:Log("[自愈程序] %s", tostring(text))
	else
		WFG:Error("magic.heal", tostring(text))
	end
	return 1
end

function M:MagicStep(dt, duration)
	return 1
end

------------------------------------------------------------------
end

-- 注意：Lua 类名取的是 MagicDef.ClassName，不是神通名。
-- 引擎 MagicBase.Init 执行 NewMagicClass(def.ClassName)（ToilMagicNormal.cs:57 → PracticeMgr.cs:1189 → MagicBase.cs:13），
-- 自愈拆成 HealOn / HealOff 两个 def，但两者 ClassName 都是 WFG_Magic_HealToggle，
-- 所以方法必须绑到 ClassName 这个类表上；绑 HealOn / HealOff 只会得到两张没人使用的空类，
-- 表现为「按钮能点、EnableCheck 恒真、MagicEnter 什么也不做」——即点开启/关闭都没反应。
bindHeal(tbTable:GetMagic("WFG_Magic_HealToggle"))


-- 衍天 · 解析
------------------------------------------------------------------
local M_Derive = tbTable:GetMagic("WFG_Magic_Derive")

function M_Derive:EnableCheck(npc)
	if not isYanTian(npc) then return false end
	local mod = WFG:GetModule("yantian")
	if mod == nil then return false end
	local c = mod:Char(npc, false)
	return c ~= nil and (c.stage or 0) >= WFG.YanTianDef.gateDerive
end

function M_Derive:TargetCheck(k, t)
	if t == nil then return false end
	local ok, name = pcall(function() return WFG.item:DefName(t) end)
	return ok and name ~= nil
end

function M_Derive:MagicEnter(IDs, IsThing)
	self.targetId = nil
	pcall(function()
		if IDs ~= nil and IDs.Count ~= nil and IDs.Count > 0 then
			self.targetId = IDs[0]
		end
	end)
	if self.targetId == nil then
		msgbox("未能锁定目标物品", "衍天")
		return -1
	end

	local thing = nil
	pcall(function() thing = ThingMgr:FindThingByID(self.targetId) end)
	if thing == nil then
		msgbox("目标已不在", "衍天")
		return -1
	end

	-- 不立刻解析：先弹确认窗，由玩家点「开始解析」再扣灵气
	local ok, err = pcall(function() WFG.ui.derive:Open(self.bind, thing) end)
	if not ok then
		WFG:Error("magic.derive", err)
		msgbox("解析界面打开失败（详见日志）", "衍天")
		return -1
	end
	-- 施法本身不产出结果，确认与扣费都在弹窗里完成，这里立即收招
	return 0
end

function M_Derive:MagicStep(dt, duration)
	return 1
end

function M_Derive:MagicLeave(success)
	-- 成败与提示都交给确认窗，这里保持安静
end

------------------------------------------------------------------
-- 避天机 · 渡劫
------------------------------------------------------------------
local M_Ascend = tbTable:GetMagic("WFG_Magic_Ascend")

function M_Ascend:EnableCheck(npc)
	if not isYanTian(npc) then return false end
	return WFG.YanTian.guard:Active(nil, npc)
end

function M_Ascend:MagicEnter(IDs, IsThing)
	local mod = WFG:GetModule("yantian")
	local ok, res, text = pcall(function() return WFG.YanTian.guard:Ascend(mod, self.bind, true) end)
	if ok and res then
		msgbox(text, "避天机")
	else
		msgbox(ok and text or "天机紊乱，渡劫未能引动", "避天机")
	end
	return 1
end

function M_Ascend:MagicStep(dt, duration)
	return 1
end

------------------------------------------------------------------
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
	-- 先选地块（SelectTarget=Point），再开面板；keys 是地图格 key，isthing=false
	local key = nil
	local list = IDs or self.grids
	if IsThing ~= true and list ~= nil then
		local n = (list.Count ~= nil) and list.Count or #list
		if n > 0 then
			key = list[0]
			if key == nil then key = list[1] end
		end
	end
	WFG:Log("[magic.create] 目标地块 key=%s isthing=%s", tostring(key), tostring(IsThing))
	local ok, err = pcall(function() WFG.ui.create:Open(self.bind, key) end)
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

return true

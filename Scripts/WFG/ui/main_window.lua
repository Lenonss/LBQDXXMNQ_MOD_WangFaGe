--[[
    万法阁 · 主界面（SimpleWindow 版）
    仅用 SetHtml + AddButton + AddLable 组合，保证在无自定义 .fui 包时可用。
    页面：总览 / 素材库 / 天机（本命法宝入口已移到两座奇观建筑上）
    交互：素材库用 ShowStoryBox 选项做「选物 → 选数量」两段对话，避免依赖输入框。
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("WFG_Main")

WFG.ui.page = WFG.ui.page or "home"
WFG.ui.sel = WFG.ui.sel or 1

-- 米色卷轴底上可读的配色（浅金/浅灰在米色上几乎看不见）
local C_GOLD = "#6B4A16"   -- 标题与强调：深琥珀
local C_DIM  = "#6A5233"   -- 次要：中褐
local C_OK   = "#1D6B3A"   -- 正向：墨绿
local C_WARN = "#8F2B1B"   -- 负向：绛红

local WIN_W  = 760
local WIN_H  = 600
local BW     = 96
local GAP    = 16

-- 每页按钮：按行分组，行内按钮整体居中
local ROWS = {
	tab   = { { "WFG_TabHome", "总览" }, { "WFG_TabLib", "素材库" }, { "WFG_TabGuard", "天机" },
	          { "WFG_Refresh", "刷新" } },
	home  = {},
	lib   = { { "WFG_Create", "创造" }, { "WFG_Prev", "上页" }, { "WFG_Next", "下页" } },
	guard = { { "WFG_ChooseStay", "留世渡劫" }, { "WFG_ChooseAscend", "登仙而去" },
	          { "WFG_AscendNow", "引动雷劫" } },
}

local function rowStart(n)
	return math.floor((WIN_W - (n * BW + (n - 1) * GAP)) / 2)
end

local BATCH = { 1, 10, 100 }
local PER_PAGE = 8

local function col(color, text)
	return string.format("[color=%s]%s[/color]", color, text)
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(text, title or "万法阁") end)
	WFG:Log("[面板] %s", tostring(text))
end

-- 按页显示/隐藏按钮
local BTN_GROUP = {
	home  = {},
	lib   = { "WFG_Create", "WFG_Prev", "WFG_Next" },
	guard = { "WFG_ChooseStay", "WFG_ChooseAscend", "WFG_AscendNow" },
}
local ALL_BUTTONS = {}
for _, tb in pairs(BTN_GROUP) do
	for i = 1, #tb do ALL_BUTTONS[#ALL_BUTTONS + 1] = tb[i] end
end

function WFG.ui:Layout()
	local page = WFG.ui.page or "home"
	local visible = {
		tab   = true,
		home  = page == "home",
		lib   = page == "lib",
		guard = page == "guard",
	}
	local pane = nil
	pcall(function() pane = tbWindow.window.contentPane end)
	if pane == nil then return end
	for group, show in pairs(visible) do
		local list = ROWS[group]
		if list ~= nil then
			for _, item in ipairs(list) do
				local ok, child = pcall(function() return pane:GetChild(item[1]) end)
				if ok and child ~= nil then
					local done = pcall(function() child.visible = show end)
					if not done then
						pcall(function() child:SetVisible(show) end)
					end
				end
			end
		end
	end
end
-- 找到当前查看的角色
function WFG.ui:TargetNpc()
	local list = WFG.npc.list or {}
	for i = 1, #list do
		local npc = list[i]
		if WFG.npc:GetGongName(npc) == WFG.YanTianDef.gong then
			return npc
		end
	end
	return list[1]
end

------------------------------------------------------------------
-- 总览
------------------------------------------------------------------
function WFG.ui:HtmlHome(npc, mod)
	local out = {}
	local def = WFG.YanTianDef
	out[#out + 1] = col(C_GOLD, "衍天诀 · 灵子道途") .. "<br/><br/>"
	if npc == nil then
		out[#out + 1] = col(C_DIM, "未找到可查看的角色。")
		return table.concat(out)
	end
	local c = mod:Char(npc, true)
	local stage = (c and c.stage) or 1
	out[#out + 1] = string.format("道途：%s<br/>", col(C_OK, WFG.npc:GetName(npc)))
	out[#out + 1] = string.format("境界：%s（第 %d 境）<br/>", col(C_GOLD, def.stageName[stage] or "未知"), stage)
	out[#out + 1] = string.format("灵气：%s / %s<br/>", WFG:Ling(npc), WFG:MaxLing(npc))
	out[#out + 1] = string.format("气血：%s / %s<br/>", WFG:Prop(npc, "Hp"), WFG:Prop(npc, "MaxHp"))
	out[#out + 1] = string.format("素材库：%s 种<br/>", col(C_GOLD, tostring(mod:LibCount(mod:Char(npc, false)))))
	-- 本命法宝是真实物品：这里只显示佩带状态，管理入口在两座奇观建筑上
	local hall = WFG.YanTian.hall
	local stMat, stEng = "unavailable", "unavailable"
	if hall ~= nil and hall.EquipState ~= nil then
		stMat = hall:EquipState(npc, "mat")
		stEng = hall:EquipState(npc, "eng")
	end
	local function eq(st)
		if st == "equipped" then return col(C_OK, "已佩带") end
		if st == "inactive" then return col(C_WARN, "待认主") end
		if st == "unavailable" then return col(C_WARN, "检测不可用") end
		return col(C_DIM, "未佩带")
	end
	out[#out + 1] = string.format("本命法宝：灵析剑 %s ｜ 灵源剑 %s<br/>", eq(stMat), eq(stEng))
	-- 衍天佩：只读显示佩戴与已解锁项；炼石仍需玩家主动点神通
	local pei = WFG.YanTian and WFG.YanTian.pei
	if pei ~= nil then
		local okp, equipped = pcall(function() return pei:IsEquipped(npc) end)
		if okp and equipped then
			local okn, learned = pcall(function() return pei:LearnedCount(npc) end)
			if not okn or type(learned) ~= "number" then learned = 0 end
			out[#out + 1] = string.format("衍天佩：%s（已学 %d/14）<br/>", col(C_OK, "已佩戴"), learned)
			local oks, sum = pcall(function() return pei:UnlockSummary(npc) end)
			if oks and type(sum) == "string" and sum ~= "" then
				out[#out + 1] = col(C_DIM, "解锁：" .. sum) .. "<br/>"
			end
		else
			out[#out + 1] = string.format("衍天佩：%s<br/>", col(C_DIM, "未佩戴（手工台：1 衍天珠 + 10 任意木料）"))
		end
	end
	out[#out + 1] = col(C_DIM, "共享总库与能源核心由对应的奇观建筑管理：点击建筑上的「管理」。") .. "<br/>"
	local healTxt = col(C_DIM, "已关闭")
	if c and c.heal == 1 then
		local healRate, hpRate = 0, 0
		if WFG.YanTian.heal and WFG.YanTian.heal.RateOf then
			local _, r = WFG.YanTian.heal:RateOf(npc)
			healRate = r or 0
		end
		if WFG.YanTian.heal and WFG.YanTian.heal.HpRateOf then
			hpRate = WFG.YanTian.heal:HpRateOf(npc) or 0
		end
		if healRate > 0.01 or hpRate > 0.01 then
			healTxt = col(C_OK, string.format("运行中（回灵 +%.2f/秒 · 回血 +%.2f/秒）", healRate, hpRate))
		else
			healTxt = col(C_OK, "运行中")
		end
	end
	out[#out + 1] = string.format("自愈程序：%s<br/>", healTxt)
	out[#out + 1] = string.format("避天机：%s<br/>", (c and c.path ~= nil) and col(C_OK, "已择道途") or col(C_DIM, "天机昭然"))
	local pathName = "未定"
	if c and c.path == "stay" then pathName = "留世渡劫"
	elseif c and c.path == "ascend" then pathName = "登仙而去" end
	out[#out + 1] = string.format("渡劫抉择：%s<br/>", col(C_GOLD, pathName))
	return table.concat(out)
end

------------------------------------------------------------------
-- 素材库
------------------------------------------------------------------
function WFG.ui:LibList(npc, mod)
	local tb = {}
	if npc == nil or mod == nil then return tb end
	local c = mod:Char(npc, false)
	if c == nil or (c.stage or 0) < WFG.YanTianDef.gateDerive then return tb end
	return WFG.YanTian.derive:List(mod, npc)
end

function WFG.ui:HtmlLib(npc, mod)
	local out = {}
	out[#out + 1] = col(C_GOLD, "素材库") .. "<br/>"
	if npc == nil then
		out[#out + 1] = col(C_DIM, "未找到可查看的角色。")
		return table.concat(out)
	end
	local c = mod:Char(npc, true)
	if c == nil or (c.stage or 0) < WFG.YanTianDef.gateDerive then
		out[#out + 1] = col(C_DIM, "需踏入衍天境（第 8 境）方可解析与创造。")
		return table.concat(out)
	end
	local tb = self:LibList(npc, mod)
	if #tb == 0 then
		out[#out + 1] = col(C_DIM, "尚无收录。以「衍天·解析」神通解析物品即可收录。")
		return table.concat(out)
	end
	local pages = math.max(1, math.ceil(#tb / PER_PAGE))
	if WFG.ui.sel > pages then WFG.ui.sel = pages end
	if WFG.ui.sel < 1 then WFG.ui.sel = 1 end
	local from = (WFG.ui.sel - 1) * PER_PAGE + 1
	local to = math.min(#tb, from + PER_PAGE - 1)
	out[#out + 1] = string.format("%s<br/>", col(C_DIM, string.format("第 %d / %d 页，共 %d 种", WFG.ui.sel, pages, #tb)))
	for i = from, to do
		local e = tb[i]
		out[#out + 1] = string.format("[%d] %s · %s · %s · %s<br/>", i,
			col(C_OK, e.name or WFG.item:Show(e.defName or "")),
			col(C_WARN, "品级" .. tostring(e.q)),
			col(C_LABEL, string.format("材料%d/品级%d", #(e.stuffs or {}), #(e.quals or {}))),
			col(C_DIM, string.format("造1件耗灵%d", WFG.YanTianDef:CreateCost(e.lv, e.q, nil, npc))))
	end
	out[#out + 1] = "<br/>" .. col(C_DIM, "点「创造」选择物品与数量；点「上页 / 下页」翻看。")
	return table.concat(out)
end

------------------------------------------------------------------
-- 天机
------------------------------------------------------------------
function WFG.ui:HtmlGuard(npc, mod)
	local out = {}
	out[#out + 1] = col(C_GOLD, "天机") .. "<br/><br/>"
	if npc == nil then return table.concat(out) end
	local c = mod:Char(npc, true)
	if c == nil then return table.concat(out) end
	if not WFG.YanTian.guard:Active(mod, npc) then
		out[#out + 1] = col(C_DIM, "尚未习得「避天机程序」。习得后天劫倒计时不再推进。")
		return table.concat(out)
	end
	out[#out + 1] = "已蒙蔽天机：天劫倒计时不再自行推进。<br/>"
	local pathName = "尚未抉择"
	if c.path == "stay" then pathName = "留世渡劫"
	elseif c.path == "ascend" then pathName = "登仙而去" end
	out[#out + 1] = string.format("已定道途：%s<br/>", col(C_GOLD, pathName))
	if (c.stage or 0) < WFG.YanTianDef.gateFinal then
		out[#out + 1] = col(C_DIM, "需臻至天门境（第 12 境）方可引动雷劫。")
	else
		out[#out + 1] = col(C_DIM, "择「留世」则渡劫后仍在人间；择「登仙」则渡劫后离世而去。")
	end
	return table.concat(out)
end

------------------------------------------------------------------
-- 刷新与显示
------------------------------------------------------------------
function WFG.ui:Refresh()
	local npc = self:TargetNpc()
	local mod = WFG:GetModule("yantian")
	if mod == nil then
		tbWindow:SetHtml(string.format("<p align='center'>%s</p>", col(C_WARN, "模块未加载。")))
		return
	end
	local page = WFG.ui.page or "home"
	local html
	if page == "lib" then
		html = self:HtmlLib(npc, mod)
	elseif page == "guard" then
		html = self:HtmlGuard(npc, mod)
	else
		html = self:HtmlHome(npc, mod)
	end
	tbWindow:SetHtml(string.format("<p align='center'>%s</p>", html))
	self:Layout()
end

function WFG.ui:Show(page)
	if page == "hall" then page = "home" end
	if page ~= nil then WFG.ui.page = page end
	tbWindow:Show()
	self:Refresh()
end

------------------------------------------------------------------
-- 创造：选物 → 选数量（都用 ShowStoryBox，避免输入框）
------------------------------------------------------------------
function WFG.ui:DoCreate(defName, count)
	local mod = WFG:GetModule("yantian")
	local npc = self:TargetNpc()
	if mod == nil or npc == nil then return end
	local ok, res, text = pcall(function()
		return WFG.YanTian.derive:Create(mod, npc, defName, count)
	end)
	if not ok then
		WFG:Error("ui.create", res)
		say("创造失败（详见日志）")
	else
		say(text or (res and "创造成功" or "未能创造"), "衍天")
	end
	self:Refresh()
end

function WFG.ui:AskCount(defName)
	local options = {}
	for i = 1, #BATCH do options[i] = string.format("创造 %d 件", BATCH[i]) end
	local function cb(s)
		local idx = tonumber(s)
		if idx == nil then return nil end
		if idx == 0 then idx = 1 end
		local n = BATCH[idx]
		if n == nil then return nil end
		WFG.ui:DoCreate(defName, n)
		return "已尝试创造 " .. tostring(n) .. " 件"
	end
	pcall(function()
		world:ShowStoryBox(
			string.format("选定素材：%s\n以灵气重构其形，需多少件？", WFG.item:Show(defName)),
			"衍天·创造", options, cb)
	end)
end

function WFG.ui:AskItem()
	local mod = WFG:GetModule("yantian")
	local npc = self:TargetNpc()
	if mod == nil or npc == nil then return end
	local tb = self:LibList(npc, mod)
	if #tb == 0 then
		say("素材库尚空。先用「衍天·解析」收录物品。")
		return
	end
	local off = (WFG.ui.sel - 1) * PER_PAGE
	local options, names = {}, {}
	for i = 1, PER_PAGE do
		local e = tb[off + i]
		if e == nil then break end
		options[#options + 1] = string.format("%s（品级%d）", e.name or WFG.item:Show(e.defName or ""), e.q)
		names[#names + 1] = e.defName or e.name
	end
	if #options == 0 then
		WFG.ui.sel = 1
		return self:AskItem()
	end
	local function cb(s)
		local idx = tonumber(s)
		if idx == nil or idx == 0 then return nil end
		local name = names[idx]
		if name == nil then return nil end
		WFG.ui:AskCount(name)
		return nil
	end
	pcall(function()
		world:ShowStoryBox(
			string.format("素材库 · 第 %d 页\n择一物，追溯其构造：", WFG.ui.sel),
			"衍天·创造", options, cb)
	end)
end

------------------------------------------------------------------
-- 窗口
------------------------------------------------------------------
function tbWindow:DebugDump()
	local pane = nil
	pcall(function() pane = self.window.contentPane end)
	if pane == nil then
		WFG:Log("[面板] contentPane 取不到")
		return
	end
	local n = -1
	pcall(function() n = pane.numChildren end)
	WFG:Log("[面板] numChildren=%s w=%s h=%s", tostring(n), tostring(pane.width), tostring(pane.height))
	for i = 0, (n or 0) - 1 do
		pcall(function()
			local ch = pane:GetChildAt(i)
			if ch ~= nil then
				WFG:Log("[面板] #%s name=%s title=%s x=%s y=%s w=%s h=%s vis=%s",
					tostring(i), tostring(ch.name), tostring(ch.title),
					tostring(ch.x), tostring(ch.y), tostring(ch.width), tostring(ch.height),
					tostring(ch.visible))
			end
		end)
	end
end

function tbWindow:OnInit()
	self:SetTitle("万法阁 · 衍天诀")
	self:SetSize(WIN_W, WIN_H)

	local y = {
		tab   = WIN_H - 64,
		home  = WIN_H - 122,
		lib   = WIN_H - 122,
		guard = WIN_H - 122,
	}
	for _, group in ipairs({ "tab", "home", "lib", "guard" }) do
		local list = ROWS[group]
		local x = rowStart(#list)
		for i, item in ipairs(list) do
			self:AddButton(item[1], item[2], x + (i - 1) * (BW + GAP), y[group])
		end
	end

	WFG.ui.tbWindow = self
end
function tbWindow:OnShown()
	pcall(function() self.window:Center() end)
	pcall(function() tbWindow:DebugDump() end)
	WFG.ui:Refresh()
end

function tbWindow:OnObjectEvent(eventType, obj, context)
	if eventType ~= "onClick" or obj == nil then return end
	local n = obj.name
	if n == "WFG_TabHome" then
		WFG.ui.page = "home"
	elseif n == "WFG_TabLib" then
		WFG.ui.page = "lib"
	elseif n == "WFG_TabGuard" then
		WFG.ui.page = "guard"
	elseif n == "WFG_Refresh" then
		WFG.ui:Refresh()
		return
	elseif n == "WFG_Prev" then
		WFG.ui.sel = math.max(1, (WFG.ui.sel or 1) - 1)
		WFG.ui:Refresh()
		return
	elseif n == "WFG_Next" then
		WFG.ui.sel = (WFG.ui.sel or 1) + 1
		WFG.ui:Refresh()
		return
	elseif n == "WFG_Create" then
		local npc = WFG.ui:TargetNpc()
		if npc == nil then
			say("未找到修炼衍天诀的角色")
		else
			local ok, err = pcall(function() WFG.ui.create:Open(npc) end)
			if not ok then WFG:Error("ui.create", err) say("创造界面打开失败（详见日志）") end
		end
		return
	elseif n == "WFG_ChooseStay" then
		WFG.ui:GuardChoose("stay")
		return
	elseif n == "WFG_ChooseAscend" then
		WFG.ui:GuardChoose("ascend")
		return
	elseif n == "WFG_AscendNow" then
		WFG.ui:AscendNow()
		return
	else
		return
	end
	WFG.ui:Refresh()
end

------------------------------------------------------------------
-- 天机页动作
------------------------------------------------------------------
function WFG.ui:GuardChoose(path)
	local mod = WFG:GetModule("yantian")
	local npc = self:TargetNpc()
	if mod == nil or npc == nil then return end
	local ok, res, text = pcall(function() return WFG.YanTian.guard:Choose(mod, npc, path) end)
	if not ok then
		WFG:Error("ui.guard", res)
		say("操作失败（详见日志）")
	else
		say(text or (res and "已定道途" or "未能定夺"), "避天机")
	end
	self:Refresh()
end

function WFG.ui:AscendNow()
	local mod = WFG:GetModule("yantian")
	local npc = self:TargetNpc()
	if mod == nil or npc == nil then return end
	local c = mod:Char(npc, true)
	local staying = (c ~= nil and c.path ~= "ascend")
	local ok, res, text = pcall(function() return WFG.YanTian.guard:Ascend(mod, npc, staying) end)
	if not ok then
		WFG:Error("ui.ascend", res)
		say("渡劫未能引动（详见日志）", "避天机")
	else
		say(text or (res and "天劫已至" or "未能渡劫"), "避天机")
	end
	self:Refresh()
end

WFG.ui.window = tbWindow
return WFG.ui

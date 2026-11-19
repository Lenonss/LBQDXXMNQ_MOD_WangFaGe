--[[
    万法阁 · 衍天创造界面（小乾坤界式）
    - 外壳与数据中心相同：FairyGUI.Window + InGame/RemoteStorage
    - 顶部：类别页签 + 品质/品阶/五行筛选条 + 搜索
    - 网格：图标、名称、库存；悬停浮窗
    - 单击选中，2 秒内再点进入确认
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_DIM   = "#7A6A55"
local C_WARN  = "#8F2B1B"

local function col(c, t)
	-- 底栏是 GRichTextField，颜色标记必须用 HTML
	return string.format("<font color=\"%s\">%s</font>", c, tostring(t))
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(tostring(text), title or "万法阁") end)
	WFG:Log("[创造界面] %s", tostring(text))
end

local function nowSec()
	local t = 0
	pcall(function() t = CS.UnityEngine.Time.realtimeSinceStartup end)
	return tonumber(t) or 0
end

local KINDS = {
	{ id = "all",   text = "全部" },
	{ id = "mat",   text = "材料" },
	{ id = "equip", text = "装备" },
	{ id = "cons",  text = "消耗" },
	{ id = "prac",  text = "修炼" },
	{ id = "misc",  text = "杂项" },
}
local QUALS = {
	{ 0, "品质：全部" }, { 1, "品质：糟糕" }, { 2, "品质：一般" },
	{ 3, "品质：优秀" }, { 4, "品质：精品" }, { 5, "品质：无" },
}
local TIERS = { 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local ELEMS = {
	{ "all", "五行：全部" }, { "none", "五行：无" }, { "jin", "五行：金" },
	{ "mu", "五行：木" }, { "shui", "五行：水" }, { "huo", "五行：火" }, { "tu", "五行：土" },
}
local CHIP_SPECS = {
	{ id = "qual", text = "品质：全部" },
	{ id = "tier", text = "品阶：不限" },
	{ id = "elem", text = "五行：全部" },
}

local function tierOptions()
	local out = {}
	for _, v in ipairs(TIERS) do
		out[#out + 1] = { v, (v >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(v)) }
	end
	return out
end

local function dropdownSpecs(s)
	local qtext = "品质：全部"
	for _, v in ipairs(QUALS) do if v[1] == s.qual then qtext = v[2] break end end
	local etext = "五行：全部"
	for _, v in ipairs(ELEMS) do if v[1] == s.elem then etext = v[2] break end end
	return {
		{ id = "qual", text = qtext, options = QUALS, value = s.qual },
		{ id = "tier", text = (s.tier >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(s.tier)), options = tierOptions(), value = s.tier },
		{ id = "elem", text = etext, options = ELEMS, value = s.elem },
	}
end

local function fresh()
	return { kind = "all", qual = 0, tier = 12, elem = "all", keyword = "" }
end

local function matchKind(e, kind)
	if kind == "all" then return true end
	return (e.kind or "misc") == kind
end

local function matchQual(e, qual)
	if qual == 0 then return true end
	if qual == 5 then return (e.q or 1) >= 5 end
	return (e.q or 1) == qual
end

local function matchTier(e, tier)
	if tier >= 12 then return true end
	return (e.tier or e.lv or 1) <= tier
end

local function matchElem(e, elem)
	if elem == "all" then return true end
	return (e.el or "none") == elem
end

local C = WFG.ui.create or {}
WFG.ui.create = C

-- 文件加载顺序不保证 fgui_browser 在 create_window 之前，必须懒加载
local browser = nil
local function shell()
	if browser ~= nil then return browser end
	local api = WFG.ui.browser
	if api == nil then
		WFG:Error("ui.create", "fgui_browser.lua 未加载")
		return nil
	end
	browser = api.new({ key = "create", title = "衍天 · 创造", mode = "grid" })
	return browser
end

function C:CurrentSel()
	local defName = self.selDef
	if defName == nil then return nil end
	for _, e in ipairs(self.filtered or {}) do
		if e.defName == defName then return e end
	end
	return nil
end

function C:Reload(keepPage)
	local mod = WFG:GetModule("yantian")
	local list = {}
	local D = WFG.YanTian and WFG.YanTian.derive
	if mod ~= nil and D ~= nil and D.List ~= nil then
		local ok, v = pcall(function() return D:List(mod, self.npc) end)
		if ok and type(v) == "table" then list = v end
	end
	local s = self.state or fresh()
	local key = s.keyword or ""
	local out = {}
	for _, e in ipairs(list) do
		if matchKind(e, s.kind) and matchQual(e, s.qual) and matchTier(e, s.tier) and matchElem(e, s.elem) then
			local name = tostring(e.name or e.defName or "")
			if key == "" or string.find(name, key, 1, true) ~= nil then
				out[#out + 1] = e
			end
		end
	end
	self.filtered = out
	self:Render()
end

function C:Render()
	local b = shell()
	if b == nil or not b:Ensure() then return end
	local shown = self.filtered or {}
	local sel = self:CurrentSel()
	local hint = sel ~= nil and "已选 1 项" or "单击选中，再点确认"
	local footer = string.format("%s　·　%s",
		col(C_LABEL, string.format("共 %d 种", #shown)),
		col(C_LABEL, hint))
	if self.tile ~= nil then
		footer = footer .. "　" .. col(C_DIM, "落点已选")
	end
	b:SetItems(shown, {
		-- 创造页不显示库存数字；素材是否可造由列表本身表达
		showCount = false,
		tipKind = "create",
		selectedDef = self.selDef,
		onPick = function(e) self:Pick(e) end,
		emptyText = "当前筛选没有可创造之物",
	})
	b:SetFooter(footer)
end

function C:Pick(e)
	if e == nil then return end
	local now = nowSec()
	if self.selDef == e.defName and self.pickArm == true and (now - (self.pickAt or 0)) <= 2 then
		self.selDef = nil
		self.pickArm = false
		self:Render()
		self:Choose(e)
		return
	end
	self.selDef = e.defName
	self.pickArm = true
	self.pickAt = now
	self:Render()
end

function C:Choose(e)
	if e == nil then return end
	WFG:Log("[create] 双击素材：def=%s name=%s q=%s lv=%s n=%s",
		tostring(e.defName), tostring(e.name), tostring(e.q), tostring(e.tier), tostring(e.n))
	local ok, err = pcall(function() WFG.ui.confirm:Open(self.npc, e, nil, self.tile) end)
	if not ok then WFG:Error("create.confirm", err) end
end

function C:SetFilterValue(id, value)
	local s = self.state or fresh()
	if id == "qual" then s.qual = tonumber(value) or 0
	elseif id == "tier" then s.tier = tonumber(value) or 12
	elseif id == "elem" then s.elem = tostring(value or "all") end
	self:UpdateChips()
	self:Reload(true)
end

function C:CycleChip(id)
	local s = self.state or fresh()
	if id == "qual" then
		local idx = 1
		for i, v in ipairs(QUALS) do if v[1] == s.qual then idx = i break end end
		s.qual = QUALS[idx % #QUALS + 1][1]
	elseif id == "tier" then
		local idx = 1
		for i, v in ipairs(TIERS) do if v == s.tier then idx = i break end end
		s.tier = TIERS[idx % #TIERS + 1]
	elseif id == "elem" then
		local idx = 1
		for i, v in ipairs(ELEMS) do if v[1] == s.elem then idx = i break end end
		s.elem = ELEMS[idx % #ELEMS + 1][1]
	end
	self:UpdateChips()
	self:Reload(true)
end
function C:UpdateChips()
	local s = self.state or fresh()
	local qualText = "品质：全部"
	for _, v in ipairs(QUALS) do if v[1] == s.qual then qualText = v[2] break end end
	local tierText = (s.tier >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(s.tier))
	local elemText = "五行：全部"
	for _, v in ipairs(ELEMS) do if v[1] == s.elem then elemText = v[2] break end end
	local b = shell()
	if b == nil then return end
	b:SetDropdownText("qual", qualText)
	b:SetDropdownText("tier", tierText)
	b:SetDropdownText("elem", elemText)
end

function C:SetFilter(kind)
	self.state = self.state or fresh()
	self.state.kind = kind or "all"
	local b = shell()
	if b ~= nil then b:SelectTab(self.state.kind) end
	self:Reload(true)
end

function C:SetKeyword(text)
	self.state = self.state or fresh()
	self.state.keyword = text or ""
	self:Reload(true)
end

function C:Refresh()
	self:Reload(true)
end

function C:Open(npc, tile)
	self.npc = npc
	self.tile = tile
	self.state = fresh()
	self.selDef = nil
	self.pickArm = false
	self.filtered = {}

	local b = shell()
	if b == nil or not b:Ensure() then
		WFG:Error("create.open", "官方窗口壳初始化失败")
		say("创造界面初始化失败（详见日志）")
		return
	end
	b:SetTitle("衍天 · 创造")
	b:SetMode("grid")
	b:SetTabs(KINDS, self.state.kind, function(id)
		self.state.kind = id
		self:Reload(true)
	end)
	b:SetDropdowns(dropdownSpecs(self.state), function(id, v) self:SetFilterValue(id, v) end)
	b:SetSearchHandler(function(text)
		self.state.keyword = text or ""
		self:Reload(true)
	end)
	self:UpdateChips()
	self:Reload(true)
	b:Show()
	WFG:Log("[create] 打开创造界面：%s", tostring(npc and npc.Name))
end

function C:Close()
	self.tile = nil
	if browser ~= nil then browser:Close() end
end

function C:SelText()
	local e = self:CurrentSel()
	if e == nil then return "" end
	return e.name or e.defName or "?"
end

function C:PickReady()
	return self.selDef ~= nil and self.pickArm == true
end

return C

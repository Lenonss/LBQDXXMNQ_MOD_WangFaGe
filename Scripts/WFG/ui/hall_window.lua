--[[
    万法阁 · 奇观建筑管理窗
    - 衍天数据中心：官方小乾坤界风格，只展示共享素材，不显示角色
    - 衍天能源中心：同一官方窗口壳，先指定交互角色，再管理取用参数
    - 不再使用 Wnd_Simple：UI_WindowEmpty 是整屏模板，无法可靠缩小
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_DIM   = "#7A6A55"
local C_WARN  = "#8F2B1B"
local C_OK    = "#1D6B3A"

local function col(c, t)
	-- 能源窗正文是 GRichTextField，颜色标记必须用 HTML
	return string.format("<font color=\"%s\">%s</font>", c, tostring(t))
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(tostring(text), title or "万法阁") end)
	WFG:Log("[奇观界面] %s", tostring(text))
end

local function cb0(fn)
	local out = nil
	pcall(function() out = CS.FairyGUI.EventCallback0(fn) end)
	return out
end

local function addClick(o, fn)
	if o == nil then return end
	pcall(function()
		local f = cb0(fn)
		if f ~= nil then o.onClick:Add(f) else o.onClick:Add(fn) end
	end)
end

local function setVisible(o, v)
	if o == nil then return end
	pcall(function() o.visible = v and true or false end)
end

local function modRef()
	return WFG.GetModule and WFG:GetModule("yantian") or nil
end

local function showName(defName, e)
	if e ~= nil and e.name ~= nil and tostring(e.name) ~= "" then return tostring(e.name) end
	local ok, name = pcall(function() return WFG.item:Show(defName) end)
	if ok and name ~= nil and tostring(name) ~= "" then return tostring(name) end
	return tostring(defName)
end

local function cfgValue(cfg, key, default)
	local v = cfg and cfg[key]
	if type(v) ~= "number" or v <= 0 then return default end
	return v
end

local function equipText(st)
	if st == "equipped" then return col(C_OK, "已佩带") end
	if st == "inactive" then return col(C_WARN, "待认主") end
	if st == "unavailable" then return col(C_WARN, "检测不可用") end
	return col(C_DIM, "未佩带")
end

local function isYanNpc(npc)
	if npc == nil then return false end
	local ok, g = pcall(function() return WFG.npc:GetGongName(npc) end)
	return ok and g == (WFG.YanTianDef and WFG.YanTianDef.gong)
end

local MAT_CATS = {
	{ id = "all",   text = "全部" },
	{ id = "mat",   text = "材料" },
	{ id = "equip", text = "装备" },
	{ id = "cons",  text = "消耗" },
	{ id = "prac",  text = "修炼" },
	{ id = "misc",  text = "杂项" },
}

local QUAL_OPTS = {
	{ 0, "品质：全部" }, { 1, "品质：糟糕" }, { 2, "品质：一般" },
	{ 3, "品质：优秀" }, { 4, "品质：精品" }, { 5, "品质：无" },
}
local TIER_OPTS = { 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local ELEM_OPTS = {
	{ "all", "五行：全部" }, { "none", "五行：无" }, { "jin", "五行：金" },
	{ "mu", "五行：木" }, { "shui", "五行：水" }, { "huo", "五行：火" }, { "tu", "五行：土" },
}
local MAT_CHIPS = {
	{ id = "qual", text = "品质：全部" },
	{ id = "tier", text = "品阶：不限" },
	{ id = "elem", text = "五行：全部" },
}

local function tierOptions()
	local out = {}
	for _, v in ipairs(TIER_OPTS) do
		out[#out + 1] = { v, (v >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(v)) }
	end
	return out
end

local function qualText(q)
	for _, v in ipairs(QUAL_OPTS) do if v[1] == q then return v[2] end end
	return "品质：全部"
end

local function elemText(e)
	for _, v in ipairs(ELEM_OPTS) do if v[1] == e then return v[2] end end
	return "五行：全部"
end

local function filterSpecs(q, t, e)
	return {
		{ id = "qual", text = qualText(q), options = QUAL_OPTS, value = q },
		{ id = "tier", text = (t >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(t)), options = tierOptions(), value = t },
		{ id = "elem", text = elemText(e), options = ELEM_OPTS, value = e },
	}
end

local function sortedPool(pool)
	local arr = {}
	for defName, e in pairs((pool and pool.items) or {}) do
		local meta = {}
		pcall(function() meta = WFG.item:Meta(defName) or {} end)
		arr[#arr + 1] = {
			defName = defName,
			name = showName(defName, e),
			q = e.q or 1,
			lv = e.lv or meta.lv or 1,
			kind = meta.kind or "misc",
			el = meta.el or "none",
			stuffs = e.stuffs or {},
			quals = e.quals or {},
		}
	end
	table.sort(arr, function(a, b)
		if a.lv ~= b.lv then return a.lv < b.lv end
		return a.name < b.name
	end)
	return arr
end

local function matShell()
	if WFG.ui.browser == nil then
		WFG:Error("ui.hall", "fgui_browser.lua 未加载")
		return nil
	end
	if WFG.ui.hallMatBrowser == nil then
		WFG.ui.hallMatBrowser = WFG.ui.browser.new({ key = "hallMat", title = "衍天数据中心", mode = "grid" })
	end
	return WFG.ui.hallMatBrowser
end

local M = WFG.ui.hallMat or {}
WFG.ui.hallMat = M

-----------------------------------------------------------------------
-- 衍天数据中心
function M:Open(bind)
	self.bind = bind
	self.cat = self.cat or "all"
	self.keyword = self.keyword or ""
	self.qual = self.qual or 0
	self.tier = self.tier or 12
	self.elem = self.elem or "all"
	local b = matShell()
	if b == nil then return end
	b:SetTitle("衍天数据中心")
	b:SetMode("grid")
	b:SetTabs(MAT_CATS, self.cat, function(id)
		self.cat = id
		self:Render()
	end)
	b:SetDropdowns(filterSpecs(self.qual, self.tier, self.elem), function(id, v) self:SetFilter(id, v) end)
	b:SetSearchHandler(function(text)
		self.keyword = text or ""
		self:Render()
	end)
	self:UpdateChips()
	self:Render()
	b:Show()
end

function M:Render()
	local b = matShell()
	if b == nil then return end
	local all = {}
	local mod = modRef()
	local hall = WFG.YanTian and WFG.YanTian.hall
	if mod ~= nil and hall ~= nil then
		all = sortedPool(hall:MatPool(mod))
	end
	local shown = {}
	local cat = self.cat or "all"
	local key = self.keyword or ""
	local qual = self.qual or 0
	local tier = self.tier or 12
	local elem = self.elem or "all"
	for i = 1, #all do
		local e = all[i]
		local q = e.q or 1
		local okQual = qual == 0 or (qual == 5 and q >= 5) or q == qual
		local okTier = tier >= 12 or (e.lv or 1) <= tier
		local okElem = elem == "all" or (e.el or "none") == elem
		if (cat == "all" or e.kind == cat) and okQual and okTier and okElem
			and (key == "" or string.find(e.name, key, 1, true) ~= nil) then
			shown[#shown + 1] = e
		end
	end
	b:SetItems(shown, {
		showCount = false,
		tipKind = "material",
		emptyText = "当前筛选没有素材",
	})
	local built = 0
	if hall ~= nil and mod ~= nil then
		pcall(function() built = hall:BuiltCount(mod, "mat") end)
	end
	local footer = string.format("%s　·　%s",
		col(C_LABEL, "已收录 " .. tostring(#shown) .. " 种素材"),
		col(C_LABEL, "已建成 " .. tostring(built) .. " 座"))
	if #shown == 0 then
		footer = footer .. "　" .. col(C_DIM, "当前筛选无结果")
	end
	b:SetFooter(footer)
end

function M:CycleChip(id)
	self.qual = self.qual or 0
	self.tier = self.tier or 12
	self.elem = self.elem or "all"
	if id == "qual" then
		local idx = 1
		for i, v in ipairs(QUAL_OPTS) do if v[1] == self.qual then idx = i break end end
		self.qual = QUAL_OPTS[idx % #QUAL_OPTS + 1][1]
	elseif id == "tier" then
		local idx = 1
		for i, v in ipairs(TIER_OPTS) do if v == self.tier then idx = i break end end
		self.tier = TIER_OPTS[idx % #TIER_OPTS + 1]
	elseif id == "elem" then
		local idx = 1
		for i, v in ipairs(ELEM_OPTS) do if v[1] == self.elem then idx = i break end end
		self.elem = ELEM_OPTS[idx % #ELEM_OPTS + 1][1]
	end
	self:UpdateChips()
	self:Render()
end

function M:SetFilter(id, value)
	if id == "qual" then self.qual = tonumber(value) or 0
	elseif id == "tier" then self.tier = tonumber(value) or 12
	elseif id == "elem" then self.elem = tostring(value or "all") end
	self:UpdateChips()
	self:Render()
end

function M:UpdateChips()
	local b = matShell()
	if b == nil then return end
	self.qual = self.qual or 0
	self.tier = self.tier or 12
	self.elem = self.elem or "all"
	local qualText = "品质：全部"
	for _, v in ipairs(QUAL_OPTS) do if v[1] == self.qual then qualText = v[2] break end end
	local tierText = (self.tier >= 12) and "品阶：不限" or ("品阶：≤" .. tostring(self.tier))
	local elemText = "五行：全部"
	for _, v in ipairs(ELEM_OPTS) do if v[1] == self.elem then elemText = v[2] break end end
	b:SetDropdownText("qual", qualText)
	b:SetDropdownText("tier", tierText)
	b:SetDropdownText("elem", elemText)
end


function M:Refresh()
	self:Render()
end

function M:Close()
	local b = matShell()
	if b ~= nil then b:Close() end
end

-----------------------------------------------------------------------
-- 衍天能源中心
-----------------------------------------------------------------------
local E = WFG.ui.hallEng or {}
WFG.ui.hallEng = E
local engBrowser = nil
local function engShell()
	if engBrowser ~= nil then return engBrowser end
	local B = WFG.ui.browser
	if B == nil then
		WFG:Error("ui.hall", "fgui_browser.lua 未加载")
		return nil
	end
	engBrowser = B.new({ key = "hallEng", title = "衍天能源中心", mode = "blank" })
	return engBrowser
end

local E_BTN = {
	{ "WFG_EDepLing", "存入一半", "dep" },
	{ "WFG_EWithLing", "取用一半", "with" },
	{ "WFG_EMode", "切换模式", "mode" },
	{ "WFG_EReset", "重置已用", "reset" },
	{ "WFG_EThMinus", "阈值-10%", "th-" },
	{ "WFG_EThPlus", "阈值+10%", "th+" },
	{ "WFG_ELimMinus", "限额-10万", "lim-" },
	{ "WFG_ELimPlus", "限额+10万", "lim+" },
	{ "WFG_EBurstMinus", "单次-1千", "burst-" },
	{ "WFG_EBurstPlus", "单次+1千", "burst+" },
	{ "WFG_ESelect", "重选角色", "select" },
	{ "WFG_ERefresh", "刷新", "refresh" },
	{ "WFG_EClose", "关闭", "close" },
}

function E:EnsurePanel()
	if self.panel ~= nil then return true end
	local b = engShell()
	if b == nil then return false end
	if not b:Ensure() then return false end
	b:SetTitle("衍天能源中心")
	b:SetMode("blank")
	local paneW, paneH = 470, 524
	pcall(function() paneW = b.pane.width; paneH = b.pane.height end)
	local pad = b.gridX or 21
	local gw = math.max(360, (tonumber(paneW) or 470) - pad * 2)
	local gh = math.max(380, (tonumber(paneH) or 524) - 96)
	self.panel = CS.FairyGUI.GComponent()
	self.panel:SetSize(gw, gh)
	b:AddPanel(self.panel)
	self.panel:SetXY(pad, 72)

	self.status = CS.FairyGUI.GRichTextField()
	-- 默认 autoSize=Both 会把正文缩成内容宽度，导致整段偏左；先固定满宽再写文字
	pcall(function() self.status.autoSize = CS.FairyGUI.AutoSizeType.None end)
	self.status:SetSize(gw, 180)
	self.status:SetXY(0, 4)
	pcall(function() self.status.align = CS.FairyGUI.AlignType.Center end)
	pcall(function() self.status.color = CS.UnityEngine.Color(0.16, 0.12, 0.07, 1) end)
	self.panel:AddChild(self.status)

	local function label(text, x, y, w, align)
		local t = CS.FairyGUI.GRichTextField()
		pcall(function() t.autoSize = CS.FairyGUI.AutoSizeType.None end)
		t:SetSize(w, 24)
		t:SetXY(x, y)
		pcall(function() t.color = CS.UnityEngine.Color(0.35, 0.27, 0.16, 1) end)
		if align ~= nil then pcall(function() t.align = align end) end
		t.text = text
		self.panel:AddChild(t)
		return t
	end

	self.sliders = {}
	local function slider(key, text, minV, maxV, y)
		local lab = label(text, 0, y + 2, 82, nil)
		local obj = nil
		pcall(function() obj = UIPackage.CreateObject("InGame", "SliderH") end)
		local s = obj and obj.asSlider or nil
		if s == nil then
			WFG:Error("ui.hallEng", "SliderH 加载失败")
			return
		end
		s:SetSize(gw - 174, 28, false)
		s:SetXY(84, y)
		s.min = minV
		s.max = maxV
		s.wholeNumbers = true
		s.value = minV
		self.panel:AddChild(s)
		local val = label("", gw - 84, y + 3, 84, CS.FairyGUI.AlignType.Right)
		local rec = { s = s, label = lab, value = val, key = key }
		self.sliders[key] = rec
		local function changed()
			if self.syncingSlider then return end
			local v = math.floor(tonumber(s.value) or minV)
			val.text = self:SliderText(key, v)
			self:ApplySlider(key, v)
		end
		pcall(function()
			local f = cb0(changed)
			if f ~= nil then s.onChanged:Add(f) else s.onChanged:Add(changed) end
		end)
		local function released()
			if not self.syncingSlider then self:Render() end
		end
		pcall(function()
			local f = cb0(released)
			if f ~= nil then s.onGripTouchEnd:Add(f) else s.onGripTouchEnd:Add(released) end
		end)
		return rec
	end
	slider("th", "补灵阈值", 10, 90, 190)
	slider("lim", "取用限额", 10, 1000, 228)
	slider("burst", "单次取用", 1, 1000, 266)

	self.hint = label("拖动滑条即时保存；数值随角色存档。", 0, gh - 34, gw, CS.FairyGUI.AlignType.Center)
	pcall(function() self.hint.fontSize = 12 end)

	self.btns = {}
	self.btnRows = {}
	local function row(names, y)
		local list = {}
		for i = 1, #names do
			local spec = names[i]
			local btn = b:MakeFlatButton(spec[2], 96, 28)
			if btn ~= nil then
				self.panel:AddChild(btn)
				pcall(function()
					local tf = btn:GetChildAt(1)
					if tf ~= nil then tf.fontSize = 12 end
				end)
				self.btns[spec[1]] = btn
				list[#list + 1] = btn
				addClick(btn, function()
					if spec[1] == "WFG_EMode" then self:OpenModeMenu(btn) else self:DoEnergy(spec[3]) end
				end)
			end
		end
		self.btnRows[#self.btnRows + 1] = { items = list, y = y }
	end
	row({ E_BTN[1], E_BTN[2], E_BTN[3], E_BTN[4] }, math.max(0, gh - 124))
	row({ E_BTN[11], E_BTN[12], E_BTN[13] }, math.max(0, gh - 72))
	self:RefreshButtons()
	return true
end

function E:SliderText(key, v)
	if key == "th" then return string.format("%d%%", v) end
	if key == "lim" then return WFG:Num(v * 10000) end
	if key == "burst" then return WFG:Num(v * 1000) end
	return tostring(v)
end

function E:ApplySlider(key, v)
	local mod, hall, npc, yan = self:State()
	if mod == nil or hall == nil or npc == nil or not yan then return end
	local ok, err
	if key == "th" then
		ok, err = pcall(function() return hall:SetThreshold(mod, npc, v / 100) end)
	elseif key == "lim" then
		ok, err = pcall(function() return hall:SetLimit(mod, npc, math.floor(v) * 10000) end)
	elseif key == "burst" then
		ok, err = pcall(function() return hall:SetBurst(mod, npc, math.floor(v) * 1000) end)
	else
		return
	end
	if not ok then WFG:Error("ui.hallEng.slider", err) end
end

function E:State()
	local mod = modRef()
	local hall = WFG.YanTian and WFG.YanTian.hall
	local npc = self.npc
	local yan = isYanNpc(npc)
	local canUse = false
	if mod ~= nil and hall ~= nil and yan then
		canUse = hall:EquipState(npc, "eng") == "equipped"
	end
	return mod, hall, npc, yan, canUse
end

function E:OpenModeMenu(btn)
	local b = engShell()
	if b == nil then return end
	local x = (self.panel and self.panel.x or 0) + (btn and btn.x or 0)
	local top = (self.panel and self.panel.y or 0) + (btn and btn.y or 0)
	local y = top + (btn and btn.height or 28) + 6
	local mode = 1
	local mod = modRef()
	if mod ~= nil and self.npc ~= nil and isYanNpc(self.npc) then
		local c = mod:Char(self.npc, true)
		local def = WFG.YanTianDef
		mode = cfgValue(c and c.fabao, "mode", def.fabao.defaultMode)
	end
	b:ShowOptionPopupAt(x, y, 160, { { 1, "实时获取" }, { 2, "充满获取" } },
		function(v) self:SetModeValue(v) end, mode, top)
end

function E:SetModeValue(v)
	local mod, hall, npc, yan = self:State()
	if mod == nil or hall == nil or npc == nil or not yan then
		say("未修炼衍天诀，不能调整供灵模式。", "衍天能源中心")
		return
	end
	local ok, res, text = pcall(function() return hall:SetMode(mod, npc, v) end)
	if not ok then
		WFG:Error("hall.mode", tostring(res))
		say("切换供灵模式失败。", "衍天能源中心")
		return
	end
	if res == false then say(text or "切换供灵模式失败。", "衍天能源中心") end
	self:Render()
end

function E:LayoutButtons()
	if self.panel == nil or self.btnRows == nil then return end
	local gw = 0
	pcall(function() gw = self.panel.width end)
	if gw == nil or gw <= 0 then gw = 428 end
	local gap = 8
	for _, row in ipairs(self.btnRows) do
		local vis = {}
		for _, btn in ipairs(row.items or {}) do
			local v = false
			pcall(function() v = (btn.visible == true) end)
			if v then vis[#vis + 1] = btn end
		end
		local total = #vis * 96
		if #vis > 1 then total = total + (#vis - 1) * gap end
		local x = math.max(0, math.floor((gw - total) / 2))
		for _, btn in ipairs(vis) do
			pcall(function() btn:SetXY(x, row.y) end)
			x = x + 96 + gap
		end
	end
end

function E:RefreshButtons()
	if self.btns == nil then return end
	local _, _, _, yan, canUse = self:State()
	local mode = 1
	local mod = modRef()
	if mod ~= nil and self.npc ~= nil and yan then
		local c = mod:Char(self.npc, true)
		local def = WFG.YanTianDef
		mode = cfgValue(c and c.fabao, "mode", def.fabao.defaultMode)
	end
	for _, btn in pairs(self.btns) do setVisible(btn, false) end
	for _, rec in pairs(self.sliders or {}) do
		setVisible(rec.label, false)
		setVisible(rec.s, false)
		setVisible(rec.value, false)
	end
	setVisible(self.btns.WFG_ESelect, true)
	setVisible(self.btns.WFG_ERefresh, true)
	setVisible(self.btns.WFG_EClose, true)
	if not yan then self:LayoutButtons() return end
	setVisible(self.btns.WFG_EDepLing, canUse)
	setVisible(self.btns.WFG_EWithLing, canUse)
	setVisible(self.btns.WFG_EMode, true)
	setVisible(self.btns.WFG_EReset, true)
	pcall(function()
		local tf = self.btns.WFG_EMode:GetChildAt(1)
		if tf ~= nil then tf.text = (mode == 1) and "模式：实时获取" or "模式：充满获取" end
	end)
	local function showSlider(key)
		local rec = self.sliders and self.sliders[key]
		if rec ~= nil then
			setVisible(rec.label, true)
			setVisible(rec.s, true)
			setVisible(rec.value, true)
		end
	end
	if mode == 1 then
		showSlider("th")
		showSlider("lim")
	else
		showSlider("burst")
	end
	self:LayoutButtons()
end

function E:Render()
	if not self:EnsurePanel() then return end
	local out = {}
	local mod, hall, npc, yan, canUse = self:State()
	if mod == nil or hall == nil then
		self.status.text = col(C_WARN, "衍天诀模块未加载。")
		self:RefreshButtons()
		return
	end
	local pool = hall:EngPool(mod)
	local cap = tonumber(pool.cap) or 0
	local ling = tonumber(pool.ling) or 0
	local pct = (cap > 0) and math.floor(ling / cap * 100) or 0
	local built = 0
	pcall(function() built = hall:BuiltCount(mod, "eng") end)
	out[#out + 1] = string.format("%s：%s · %s",
		col(C_TITLE, "共享核心"),
		col(C_VALUE, string.format("%s / %s（%d%%）", WFG:Num(ling), WFG:Num(cap), pct)),
		col(C_DIM, "已建成 " .. tostring(built) .. " 座"))
	local mode = 1
	local cfg = nil
	if npc == nil then
		out[#out + 1] = col(C_WARN, "尚未指定交互角色。")
		out[#out + 1] = col(C_DIM, "点击下方「重选角色」，或由佩带已认主灵源剑的修士从指令栏打开。")
	else
		local st = hall:EquipState(npc, "eng")
		local name = npc
		pcall(function() name = WFG.npc:GetName(npc) end)
		out[#out + 1] = string.format("%s：%s（%s）",
			col(C_LABEL, "交互角色"), col(C_VALUE, tostring(name)),
			yan and col(C_OK, "衍天诀") or col(C_WARN, "非衍天诀"))
		out[#out + 1] = string.format("%s：%s　%s：%s",
			col(C_LABEL, "灵源剑"), equipText(st),
			col(C_LABEL, "自身灵气"), string.format("%s / %s", WFG:Ling(npc), WFG:MaxLing(npc)))
		if yan then
			local c = mod:Char(npc, true)
			cfg = c and c.fabao or nil
			local def = WFG.YanTianDef
			mode = cfgValue(cfg, "mode", def.fabao.defaultMode)
			out[#out + 1] = string.format("%s：%s", col(C_LABEL, "供灵模式"),
				col(C_VALUE, mode == 1 and "实时获取" or "充满获取"))
			if mode == 1 then
				local p = cfgValue(cfg, "x", def.fabao.defaultThresholdPct)
				local limit = cfgValue(cfg, "limit", def.fabao.defaultLimit)
				out[#out + 1] = string.format("%s：%s　%s：%s",
					col(C_LABEL, "补灵阈值"), col(C_VALUE, string.format("%d%%", math.floor(p * 100 + 0.5))),
					col(C_LABEL, "已用/限额"), col(C_VALUE, string.format("%s / %s", WFG:Num((cfg and cfg.used) or 0), WFG:Num(limit))))
			else
				local burst = cfgValue(cfg, "burst", def.fabao.defaultBurst)
				out[#out + 1] = string.format("%s：%s", col(C_LABEL, "单次取用"), col(C_VALUE, WFG:Num(burst)))
			end
			if canUse then
				out[#out + 1] = col(C_OK, "灵源剑已认主，核心按当前参数自动供灵。")
			else
				out[#out + 1] = col(C_WARN, "未佩剑：参数可预设，存取与自动供灵需佩剑后生效。")
			end
			out[#out + 1] = col(C_DIM, "拖滑条调整；存入/取用作用于共享核心。")
		else
			out[#out + 1] = col(C_WARN, "该角色不修衍天诀，不能管理衍天能源中心。")
		end
	end
	self.status.text = table.concat(out, "<br/>")
	pcall(function() self.status:SetSize(self.panel.width, 180) end)
	if yan and npc ~= nil and cfg ~= nil and self.sliders ~= nil then
		local def = WFG.YanTianDef
		self.syncingSlider = true
		local function sync(key, v)
			local rec = self.sliders[key]
			if rec ~= nil and rec.s ~= nil then
				rec.s.value = v
				rec.value.text = self:SliderText(key, math.floor(v))
			end
		end
		if mode == 1 then
			local p = cfgValue(cfg, "x", def.fabao.defaultThresholdPct)
			local limit = cfgValue(cfg, "limit", def.fabao.defaultLimit)
			sync("th", math.max(10, math.min(90, math.floor(p * 100 + 0.5))))
			sync("lim", math.max(10, math.min(1000, math.floor(limit / 10000 + 0.5))))
		else
			local burst = cfgValue(cfg, "burst", def.fabao.defaultBurst)
			sync("burst", math.max(1, math.min(1000, math.floor(burst / 1000 + 0.5))))
		end
		self.syncingSlider = false
	end
	self:RefreshButtons()
end
function E:DoEnergy(cmd)
	local mod, hall, npc, yan, canUse = self:State()
	if mod == nil or hall == nil then return end
	if cmd == "select" then
		self:SelectNpc(self.bind)
		return
	end
	if cmd == "close" then
		self:Close()
		return
	end
	if cmd == "refresh" then
		self:Render()
		return
	end
	if npc == nil then
		say("请先指定交互角色。", "衍天能源中心")
		return
	end
	if (cmd == "dep" or cmd == "with") and not canUse then
		say("需衍天诀且佩带已认主的灵源剑。", "衍天能源中心")
		return
	end
	if not yan then
		say("该角色不修衍天诀，不能管理衍天能源中心。", "衍天能源中心")
		return
	end

	local ok, res, text
	if cmd == "dep" then
		ok, res, text = pcall(function() return hall:DepositLing(mod, npc, math.floor((WFG:Ling(npc) or 0) * 0.5)) end)
	elseif cmd == "with" then
		ok, res, text = pcall(function() return hall:WithdrawLing(mod, npc, math.floor((hall:EngPool(mod).ling or 0) * 0.5)) end)
	elseif cmd == "mode" then
		local c = mod:Char(npc, true)
		local def = WFG.YanTianDef
		local mode = cfgValue(c and c.fabao, "mode", def.fabao.defaultMode)
		ok, res, text = pcall(function() return hall:SetMode(mod, npc, (mode == 1) and 2 or 1) end)
	elseif cmd == "reset" then
		ok, res, text = pcall(function() return hall:ResetLimit(mod, npc) end)
	else
		local c = mod:Char(npc, true)
		local def = WFG.YanTianDef
		local cfg = c and c.fabao or {}
		local pct = cfgValue(cfg, "x", def.fabao.defaultThresholdPct)
		local limit = cfgValue(cfg, "limit", def.fabao.defaultLimit)
		local burst = cfgValue(cfg, "burst", def.fabao.defaultBurst)
		if cmd == "th-" then
			ok, res, text = pcall(function() return hall:SetThreshold(mod, npc, pct - 0.1) end)
		elseif cmd == "th+" then
			ok, res, text = pcall(function() return hall:SetThreshold(mod, npc, pct + 0.1) end)
		elseif cmd == "lim-" then
			ok, res, text = pcall(function() return hall:SetLimit(mod, npc, limit - 100000) end)
		elseif cmd == "lim+" then
			ok, res, text = pcall(function() return hall:SetLimit(mod, npc, limit + 100000) end)
		elseif cmd == "burst-" then
			ok, res, text = pcall(function() return hall:SetBurst(mod, npc, burst - 10000) end)
		elseif cmd == "burst+" then
			ok, res, text = pcall(function() return hall:SetBurst(mod, npc, burst + 10000) end)
		else
			return
		end
	end
	if not ok then
		WFG:Error("ui.hallEng", res)
		say("操作失败（详见日志）", "衍天能源中心")
	else
		say(text or (res and "完成" or "未能完成"), "衍天能源中心")
	end
	self:Render()
end

function E:SelectNpc(bind)
	self.bind = bind
	self.npc = nil
	local wl = WorldLua or world
	local cb = nil
	local okCb = pcall(function()
		cb = wl:GetSelectNpcCallback(function(rs)
			local n = 0
			pcall(function() n = rs.Count end)
			if n == nil or n <= 0 then return end
			local thing = nil
			pcall(function() thing = CS.XiaWorld.ThingMgr.Instance:FindThingByID(rs[0]) end)
			if thing ~= nil then self:OpenNpc(thing) end
		end)
	end)
	if not (okCb and cb ~= nil) then
		WFG:Error("hall.select", "GetSelectNpcCallback 失败")
		self:Show()
		return
	end
	local ok, err = pcall(function()
		CS.Wnd_SelectNpc.Instance:Select(cb, g_emNpcRank.Normal, 1, 1, nil, nil, "选择与衍天能源中心交互的角色")
	end)
	if not ok then
		WFG:Error("hall.select", err)
		self:Show()
	end
end

function E:Show()
	if self.npc ~= nil and not isYanNpc(self.npc) then
		self.npc = nil
		if engBrowser ~= nil then engBrowser:Close() end
		say("该角色未修炼衍天诀，不能打开衍天能源中心。", "衍天能源中心")
		return
	end
	if not self:EnsurePanel() then return end
	local b = engShell()
	if b == nil then return end
	b:SetTitle("衍天能源中心")
	self:Render()
	b:Show()
end

function E:Open(bind)
	self.bind = bind
	self.npc = nil
	self:Show()
end

function E:OpenNpc(npc)
	if not isYanNpc(npc) then
		self.npc = nil
		if engBrowser ~= nil then engBrowser:Close() end
		say("该角色未修炼衍天诀，不能打开衍天能源中心。", "衍天能源中心")
		return
	end
	self.npc = npc
	self:Show()
end

function E:Close()
	if engBrowser ~= nil then engBrowser:Close() end
end

WFG.ui.hallMatWindow = nil
WFG.ui.hallEngWindow = nil

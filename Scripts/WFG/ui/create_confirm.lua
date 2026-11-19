--[[
    万法阁 · 衍天创造确认窗（v2）
    布局（560×470，全部控件横向居中）：
        标题牌（frame.title）
        y= 52  信息条带（素材/阶/品级/材料/库存）
        y=180  材料行：[材料] [◀] [名称] [▶]
        y=216  品级行：[品级] [◀] [n 品] [▶]
        y=252  数量行：[数量] [滑条] [输入框]
        y=288  储灵行：[储灵] [滑条] [输入框]
        y=330  报价两行
        y=406  [确认并选点] [取消]
    说明：内置下拉框（UI_ComboBox）在 mod 上下文未验证可用，
    这里用 ◀▶ 选择器实现同等能力（同样走 OnObjectEvent 分发）。
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("WFG_CreateConfirm")

local URL_BTN   = "ui://0xrxw6g7hdhl18"   -- 内置按钮
local URL_LABEL = "ui://0xrxw6g7nd594l"   -- 内置文字
local URL_SLD   = "ui://0xrxw6g7hdhl1e"   -- 内置横向滑条（InGameBinder.cs:218 UI_SliderH）
local URL_INPUT = "ui://0xrxw6g7hdhl1c"   -- 内置输入框（UI_InputTextField，child1 = GTextInput）

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_ACCENT= "#8A5A0F"
local C_WARN  = "#8F2B1B"

local WIN_W, WIN_H = 600, 520

local C = WFG.ui.confirm or {}
WFG.ui.confirm = C

local QUAL_NAME = { "糟糕", "一般", "优秀", "精品", "极品" }

------------------------------------------------------------------------
-- 小工具
------------------------------------------------------------------------
local function col(color, text)
	return string.format("[color=%s]%s[/color]", color, text)
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(text, title or "衍天·创造") end)
	WFG:Log("[创造确认] %s", tostring(text))
end

local function cb0(fn)
	local out = nil
	pcall(function() out = CS.FairyGUI.EventCallback0(fn) end)
	return out
end

-- 卡片底板：浅色半透明矩形 + 细描边，用来分块，避免整窗一片糊
local function addRect(x, y, w, h, fill, line)
	local g = nil
	pcall(function() g = CS.FairyGUI.GGraph() end)
	if g == nil then return nil end
	pcall(function()
		g:DrawRect(w, h, 1,
			line or CS.UnityEngine.Color(0.70, 0.58, 0.34, 0.55),
			fill or CS.UnityEngine.Color(0.995, 0.97, 0.90, 0.55))
	end)
	pcall(function() g.touchable = false end)
	pcall(function() tbWindow.window:AddObj(g, x, y) end)
	return g
end

local function addRaw(url, name, x, y, w, h)
	local obj = nil
	local ok = pcall(function() obj = tbWindow:AddObjectFromUrl(url, x, y) end)
	if not ok or obj == nil then
		WFG:Log("[confirm] 取控件失败：%s（%s）", tostring(name), tostring(url))
		return nil
	end
	pcall(function() obj.name = name end)
	if w ~= nil and h ~= nil then
		pcall(function() obj:SetSize(w, h, true) end)
	end
	return obj
end

local function addBtn(name, text, x, y, w, h)
	local b = addRaw(URL_BTN, name, x, y, w, h)
	if b == nil then return nil end
	pcall(function() b.title = (text or "") end)
	return b
end

local function addLabel(name, text, x, y, w, h)
	local l = addRaw(URL_LABEL, name, x, y, w, h)
	if l == nil then return nil end
	pcall(function() l.title = (text or "") end)
	return l
end

local function setTitle(obj, text)
	if obj == nil then return end
	pcall(function() obj.title = text end)
end

local function setVisible(obj, show)
	if obj == nil then return end
	local ok = pcall(function() obj.visible = show end)
	if not ok then pcall(function() obj:SetVisible(show) end) end
end

local function setXY(obj, x, y)
	if obj == nil then return end
	pcall(function() obj:SetXY(x, y) end)
end

local function mod()
	return WFG.GetModule and WFG:GetModule("yantian") or nil
end

local function deriv()
	return WFG.YanTian and WFG.YanTian.derive or nil
end

------------------------------------------------------------------------
-- 数据
------------------------------------------------------------------------
function C:MaxCount()
	local e = self.entry
	local d, m = deriv(), mod()
	if e == nil or e.defName == nil or d == nil or m == nil or d.QuoteCreate == nil then return 1 end
	local best = 0
	for n = 1, 100 do
		local ok, q = pcall(function()
			return d:QuoteCreate(m, self.npc, e.defName, n, self.stuff, self.quality, 0)
		end)
		if not ok or type(q) ~= "table" or q.ok ~= true or q.enough ~= true then break end
		best = n
	end
	return math.max(1, best)
end

function C:Quote()
	local e = self.entry
	local d, m = deriv(), mod()
	if e == nil or e.defName == nil or d == nil or m == nil or d.QuoteCreate == nil then return self.quote end
	local ok, q = pcall(function()
		return d:QuoteCreate(m, self.npc, e.defName, self.count or 1, self.stuff, self.quality, self.store or 0)
	end)
	if ok and type(q) == "table" then
		self.quote = q
		-- 首次进入时用条目里的默认值初始化选择状态
		if self.stuff == nil then self.stuff = q.stuff end
		if self.quality == nil then self.quality = q.q end
	end
	return self.quote
end

-- 材料循环：nil（未记录）→ 各已解锁材料 → 回到第一个
function C:CycleStuff(dir)
	local q = self:Quote()
	if q == nil or q.stuffs == nil or #q.stuffs == 0 then return end
	local list = q.stuffs
	local idx = 0
	for i = 1, #list do
		if list[i] == self.stuff then idx = i end
	end
	idx = idx + dir
	if idx < 1 then idx = #list end
	if idx > #list then idx = 1 end
	self.stuff = list[idx]
	self:Quote()
	self:RefreshAll()
end

function C:CycleQuality(dir)
	local q = self:Quote()
	if q == nil or q.quals == nil or #q.quals == 0 then return end
	local list = q.quals
	local idx = 1
	for i = 1, #list do
		if list[i] == self.quality then idx = i end
	end
	idx = idx + dir
	if idx < 1 then idx = #list end
	if idx > #list then idx = 1 end
	self.quality = list[idx]
	self:Quote()
	self:RefreshAll()
end

------------------------------------------------------------------------
-- 构建（只建一次）
------------------------------------------------------------------------
function C:Build()
	if self.built == true then return end
	local w = {}

	-- 三块底板：信息 / 参数 / 报价
	self.cards = {}
	self.cards.info = addRect(22, 44, WIN_W - 44, 122)
	self.cards.ctrl = addRect(22, 174, WIN_W - 44, 168)
	self.cards.cost = addRect(22, 350, WIN_W - 44, 60)

	w.LStuff = addLabel("WFG_CfLStuff", "材料", 0, 0, 48, 24)
	w.BStuffL = addBtn("WFG_CfStuffL", "◀", 0, 0, 30, 28)
	w.VStuff = addLabel("WFG_CfVStuff", "-", 0, 0, 160, 24)
	w.BStuffR = addBtn("WFG_CfStuffR", "▶", 0, 0, 30, 28)

	w.LQual = addLabel("WFG_CfLQual", "品级", 0, 0, 48, 24)
	w.BQualL = addBtn("WFG_CfQualL", "◀", 0, 0, 30, 28)
	w.VQual = addLabel("WFG_CfVQual", "-", 0, 0, 100, 24)
	w.BQualR = addBtn("WFG_CfQualR", "▶", 0, 0, 30, 28)

	w.LQty  = addLabel("WFG_CfLQty", "数量", 0, 0, 48, 24)
	w.Sld   = addRaw(URL_SLD, "WFG_CfSld", 0, 0, 236, 22)
	w.Inp   = addRaw(URL_INPUT, "WFG_CfInp", 0, 0, 96, 32)

	w.LLing = addLabel("WFG_CfLLing", "储灵", 0, 0, 48, 24)
	w.Sld2  = addRaw(URL_SLD, "WFG_CfSld2", 0, 0, 236, 22)
	w.Inp2  = addRaw(URL_INPUT, "WFG_CfInp2", 0, 0, 96, 32)

	w.LCost = addLabel("WFG_CfLCost", "", 0, 0, 420, 24)
	w.LCost2 = addLabel("WFG_CfLCost2", "", 0, 0, 420, 24)
	w.Ok     = addBtn("WFG_CfOk", "确认并选点", 0, 0, 150, 34)
	w.Cancel = addBtn("WFG_CfCancel", "取消", 0, 0, 110, 34)
	self.w = w

	-- 数量输入框
	self.tf = nil
	if w.Inp ~= nil then
		pcall(function() self.tf = w.Inp:GetChildAt(1) end)
		if self.tf ~= nil then
			pcall(function() self.tf.text = "1" end)
			pcall(function() self.tf.align = CS.FairyGUI.AlignType.Center end)
			local cb = cb0(function() C:OnInputChanged() end)
			if cb ~= nil then pcall(function() self.tf.onChanged:Add(cb) end) end
		end
	end

	-- 储灵输入框
	self.tf2 = nil
	if w.Inp2 ~= nil then
		pcall(function() self.tf2 = w.Inp2:GetChildAt(1) end)
		if self.tf2 ~= nil then
			pcall(function() self.tf2.text = "0" end)
			pcall(function() self.tf2.align = CS.FairyGUI.AlignType.Center end)
			local cb = cb0(function() C:OnStoreChanged() end)
			if cb ~= nil then pcall(function() self.tf2.onChanged:Add(cb) end) end
		end
	end

	if w.Sld ~= nil then
		pcall(function() w.Sld.min = 1 end)
		pcall(function() w.Sld.max = 100 end)
		pcall(function() w.Sld.value = 1 end)
		pcall(function() w.Sld.wholeNumbers = true end)
		local cb = cb0(function() C:OnSliderMoved() end)
		if cb ~= nil then pcall(function() w.Sld.onChanged:Add(cb) end) end
	end
	if w.Sld2 ~= nil then
		pcall(function() w.Sld2.min = 0 end)
		pcall(function() w.Sld2.max = 1 end)
		pcall(function() w.Sld2.value = 0 end)
		pcall(function() w.Sld2.wholeNumbers = true end)
		local cb = cb0(function() C:OnStoreSlider() end)
		if cb ~= nil then pcall(function() w.Sld2.onChanged:Add(cb) end) end
	end

	self.built = true
	WFG:Log("[confirm] 构建完成 数量滑条=%s 储灵滑条=%s",
		tostring(w.Sld ~= nil), tostring(w.Sld2 ~= nil))
end

function C:Layout()
	local w = self.w
	if w == nil then return end

	-- 控件坐标是 contentPane 坐标系，不是 WIN_W 虚拟画布：
	-- 卡片 24..pw-24，内容统一按 L / R 两边对齐，避免"再加一档居中偏移"把右侧箭头推出卡片
	local pw, ph = 600, 520
	pcall(function()
		local pane = tbWindow.window.contentPane
		if pane ~= nil then pw = pane.width; ph = pane.height end
	end)
	if pw == nil or pw < 600 then pw = 600 end
	if ph == nil or ph < 520 then ph = 520 end

	local L  = 64                -- 内容左边界
	local R  = pw - 64           -- 内容右边界
	local XC = 176               -- 控件列起点
	local BW = 32                -- 小按钮宽

	local function setSize(o, a, b)
		if o == nil then return end
		pcall(function() o:SetSize(a, b) end)
	end

	-- 材料行
	setSize(w.LStuff, 60, 24); setXY(w.LStuff, L, 196)
	setXY(w.BStuffL, XC, 192)
	setSize(w.VStuff, math.max(120, R - XC - BW - 60), 24); setXY(w.VStuff, XC + BW + 12, 196)
	setXY(w.BStuffR, R - BW, 192)

	-- 品级行
	setSize(w.LQual, 60, 24); setXY(w.LQual, L, 232)
	setXY(w.BQualL, XC, 228)
	setSize(w.VQual, math.max(120, R - XC - BW - 60), 24); setXY(w.VQual, XC + BW + 12, 232)
	setXY(w.BQualR, R - BW, 228)

	-- 数量行：标签 | 滑条 | 输入框（输入框贴右边界）
	local inpW = 96
	setSize(w.LQty, 60, 24); setXY(w.LQty, L, 274)
	setSize(w.Sld, math.max(160, R - XC - inpW - 16), 22); setXY(w.Sld, XC, 276)
	setSize(w.Inp, inpW, 32); setXY(w.Inp, R - inpW, 270)

	-- 储灵行
	setSize(w.LLing, 60, 24); setXY(w.LLing, L, 314)
	setSize(w.Sld2, math.max(160, R - XC - inpW - 16), 22); setXY(w.Sld2, XC, 316)
	setSize(w.Inp2, inpW, 32); setXY(w.Inp2, R - inpW, 310)

	-- 报价（与标签列左对齐）
	setSize(w.LCost, R - L, 24); setXY(w.LCost, L, 358)
	setSize(w.LCost2, R - L, 24); setXY(w.LCost2, L, 380)

	-- 按钮行：整行按窗口宽度居中
	local bw1, bw2, gap = 170, 120, 28
	local bx = math.floor((pw - (bw1 + gap + bw2)) / 2)
	setXY(w.Ok, bx, 452)
	setXY(w.Cancel, bx + bw1 + gap, 452)

	-- 三块底板
	pcall(function()
		if self.cards ~= nil then
			if self.cards.info ~= nil then self.cards.info:SetXY(24, 46); self.cards.info:SetSize(pw - 48, 116) end
			if self.cards.ctrl ~= nil then self.cards.ctrl:SetXY(24, 172); self.cards.ctrl:SetSize(pw - 48, 176) end
			if self.cards.cost ~= nil then self.cards.cost:SetXY(24, 348); self.cards.cost:SetSize(pw - 48, 64) end
		end
	end)

	-- 信息条带（m_html）
	local f = nil
	pcall(function() f = tbWindow.window.contentPane:GetChildAt(1) end)
	if f ~= nil then
		pcall(function() f:SetXY(40, 54) end)
		pcall(function() f:SetSize(pw - 80, 100, false) end)
	end
end

------------------------------------------------------------------------
-- 交互
------------------------------------------------------------------------
function C:ApplyCount(n, fromInput)
	local maxC = self:MaxCount()
	n = tonumber(n) or 1
	if n ~= n then n = 1 end
	n = math.floor(n)
	if n < 1 then n = 1 end
	if n > maxC then n = maxC end
	self.count = n
	self.maxC = maxC

	local w = self.w
	if w ~= nil and w.Sld ~= nil then
		local locked = (maxC <= 1)
		-- min 与 max 相等时 FairyGUI 滑条会算出 0/0，value 变成 -nan(ind)
		pcall(function() w.Sld.max = math.max(2, maxC) end)
		pcall(function() w.Sld.touchable = not locked end)
		pcall(function() w.Sld.grayed = locked end)
		if fromInput or locked then
			local was = self.syncing
			self.syncing = true
			pcall(function() w.Sld.value = n end)
			self.syncing = was
		end
	end
	if fromInput ~= true and self.tf ~= nil then
		pcall(function() self.tf.text = tostring(n) end)
	end
	self:Render()
end

function C:ApplyStore(v, fromInput)
	local q = self:Quote()
	local capAll = math.floor((q and q.lingMax) or 0)
	v = math.floor(tonumber(v) or 0)
	if v < 0 then v = 0 end
	if v > capAll then v = capAll end
	self.store = v

	local w = self.w
	if w ~= nil and w.Sld2 ~= nil then
		pcall(function() w.Sld2.max = math.max(1, capAll) end)
		if fromInput then pcall(function() w.Sld2.value = v end) end
	end
	if fromInput ~= true and self.tf2 ~= nil then
		pcall(function() self.tf2.text = tostring(v) end)
	end
	self:Render()
end

function C:OnSliderMoved()
	if self.syncing == true then return end
	local v = self.count or 1
	pcall(function() v = self.w.Sld.value end)
	v = tonumber(v) or 1
	if v ~= v then v = 1 end
	self.syncing = true
	self:ApplyCount(v, false)
	self.syncing = false
end

function C:OnInputChanged()
	if self.syncing == true then return end
	local t = tostring(self.count or 1)
	pcall(function() t = self.tf.text end)
	local n = tonumber(string.match(t, "%-?%d+") or "") or 1
	self.syncing = true
	self:ApplyCount(n, true)
	self.syncing = false
end

function C:OnStoreSlider()
	if self.syncing == true then return end
	local v = self.store or 0
	pcall(function() v = self.w.Sld2.value end)
	self.syncing = true
	self:ApplyStore(v, false)
	self.syncing = false
end

function C:OnStoreChanged()
	if self.syncing == true then return end
	local t = tostring(self.store or 0)
	pcall(function() t = self.tf2.text end)
	local n = tonumber(string.match(t, "%-?%d+") or "") or 0
	self.syncing = true
	self:ApplyStore(n, true)
	self.syncing = false
end

function C:OnClick(name)
	if name == "WFG_CfOk" then
		self:Confirm()
	elseif name == "WFG_CfCancel" then
		self:Close()
	elseif name == "WFG_CfStuffL" then
		self:CycleStuff(-1)
	elseif name == "WFG_CfStuffR" then
		self:CycleStuff(1)
	elseif name == "WFG_CfQualL" then
		self:CycleQuality(-1)
	elseif name == "WFG_CfQualR" then
		self:CycleQuality(1)
	end
end

------------------------------------------------------------------------
-- 渲染
------------------------------------------------------------------------
function C:RefreshAll()
	local q = self:Quote()
	local w = self.w
	if w == nil then return end
	setTitle(w.VStuff, (q and q.stuffName) or "未记录")
	setTitle(w.VQual, string.format("%d 品 · %s", (q and q.q) or 1,
		QUAL_NAME[(q and q.q) or 1] or ""))
	self:Render()
end

function C:Render()
	local e = self.entry
	if e == nil then
		tbWindow:SetHtml(WFG.ui:Center(col(C_WARN, "目标已丢失。")))
		setVisible(self.w and self.w.Ok, false)
		return
	end

	local q = self:Quote()
	if q == nil then
		tbWindow:SetHtml(WFG.ui:Center(col(C_WARN, "无法读取该素材信息。")))
		setVisible(self.w and self.w.Ok, false)
		return
	end
	q.name = e.name

	local out = {}
	out[#out + 1] = string.format("%s：%s　%s：%s<br/>",
		col(C_LABEL, "素材"), col(C_VALUE, q.name or "未知物品"),
		col(C_LABEL, "阶数"), col(C_VALUE, tostring(e.lv or 0) .. " 阶"))
	out[#out + 1] = string.format("%s：%s　%s：%s<br/>",
		col(C_LABEL, "已录材料"), col(C_VALUE, tostring(#(q.stuffs or {})) .. " 种"),
		col(C_LABEL, "已录品级"), col(C_VALUE, tostring(#(q.quals or {})) .. " 级"))
	out[#out + 1] = string.format("%s：%s　%s：%s",
		col(C_LABEL, "单次上限"), col(C_VALUE, tostring(q.maxBatch or 1) .. " 件"),
		col(C_LABEL, "可负担"), col(C_VALUE, tostring(self.maxC or 1) .. " 件"))
	local rawCap = 0
	pcall(function() rawCap = WFG.item:LingCap(e.defName) end)
	if rawCap <= 0 then
		out[#out + 1] = "<br/>" .. col(C_DIM,
			string.format("原版该物品不可储灵，已按功法上限 %d/件 处理",
				(WFG.YanTianDef and WFG.YanTianDef.lingFallback) or 100))
	end
	tbWindow:SetHtml(WFG.ui:Center(table.concat(out)))

	-- 报价两行
	local cost = math.floor(q.cost or 0)
	local store = math.floor(q.store or 0)
	local total = math.floor(q.total or (cost + store))
	local ling = math.floor(q.ling or 0)
	local maxLing = math.floor(q.maxLing or 0)
	if q.ok ~= true then
		setTitle(self.w.LCost, col(C_WARN, q.reason or "无法创造"))
		setTitle(self.w.LCost2, "")
	else
		setTitle(self.w.LCost, string.format("%s　%s　%s",
			col(C_ACCENT, string.format("造物 %d", cost)),
			col(C_ACCENT, string.format("储灵 %d", store)),
			col(C_TITLE, string.format("合计 %d", total))))
		if q.enough then
			setTitle(self.w.LCost2, col(C_VALUE, string.format("当前灵气 %d / %d", ling, maxLing)))
		else
			setTitle(self.w.LCost2, col(C_WARN, string.format("灵气不足，还差 %d", total - ling)))
		end
	end
	setVisible(self.w and self.w.Ok, q.ok == true and q.enough == true)

	-- 储灵上限变化时同步滑条
	if self.w and self.w.Sld2 ~= nil then
		local capAll = math.floor(q.lingMax or 0)
		pcall(function() self.w.Sld2.max = math.max(1, capAll) end)
		if (self.store or 0) > capAll then
			self.store = capAll
			if self.tf2 ~= nil then pcall(function() self.tf2.text = tostring(capAll) end) end
		end
	end
end

------------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------------
function C:Open(npc, entry, quote, tile)
	self.npc = npc
	self.tile = tile
	self.entry = entry
	self.quote = quote
	self.count = 1
	self.store = 0
	self.stuff = nil
	self.quality = nil
	self.maxC = 1
	self.syncing = false

	tbWindow:SetSize(WIN_W, WIN_H)
	tbWindow:Show()
	pcall(function() tbWindow:SetTitle("衍天 · 创造") end)
	pcall(function() tbWindow.window:Center() end)
	WFG.ui:Pause()

	self:Build()
	self:Layout()
	-- 已在地图上选好落点时，按钮语义改为「确认创造」
	if self.tile ~= nil and self.w ~= nil and self.w.Ok ~= nil then
		pcall(function() self.w.Ok.title = "确认创造" end)
	elseif self.w ~= nil and self.w.Ok ~= nil then
		pcall(function() self.w.Ok.title = "确认并选点" end)
	end
	self:Quote()          -- 初始化 stuff/quality
	self.maxC = self:MaxCount()
	self:ApplyCount(1, false)
	self:ApplyStore(0, false)
	self:RefreshAll()
end

function C:Close()
	pcall(function() tbWindow:Hide() end)
	WFG.ui:Resume()
end

function C:Confirm()
	local q = self:Quote()
	if q == nil or q.ok ~= true then say(q and q.reason or "无法创造") return end
	if q.enough ~= true then say("灵气不足") return end

	local e = self.entry
	local n = self.count or 1
	local st = self.stuff
	local qq = self.quality or q.q or 1
	local store = self.store or 0
	local d, m = deriv(), mod()
	local tile = self.tile
	self:Close()
	if WFG.ui.create ~= nil then WFG.ui.create:Close() end

	if tile ~= nil and d ~= nil and m ~= nil and d.Create ~= nil then
		local ok, ret, why = pcall(function() return d:Create(m, self.npc, e.defName, n, tile, st, qq, store) end)
		if not ok then
			WFG:Error("confirm.create", ret)
			say("创造失败（详见日志）")
			return
		end
		if ret == false then
			say(tostring(why or "创造失败"))
			return
		end
		say(string.format("已创造 %s ×%d", tostring(e.name or e.defName), n))
		return
	end

	-- 兜底：没有点选地块时退回手动选点
	WFG.ui.pos:Start(self.npc, e, n, st, qq, store)
end

function tbWindow:OnInit()
	-- 控件在首次 Show 之后建（Wnd_Simple.UIInfo 于 OnInit 才 CreateInstance）
end

function tbWindow:OnShown()
	pcall(function() C:Build() end)
	pcall(function() C:Layout() end)
end

function tbWindow:OnObjectEvent(t, obj, context)
	if t ~= "onClick" or obj == nil then return end
	local name = nil
	pcall(function() name = obj.name end)
	if name == nil then return end
	WFG:Log("[confirm] 点击控件：%s", name)
	local ok, err = pcall(function() C:OnClick(name) end)
	if not ok then WFG:Error("confirm.click", err) end
end

return C

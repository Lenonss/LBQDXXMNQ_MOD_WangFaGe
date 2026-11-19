--[[
    万法阁 · 官方小乾坤界风格物品浏览器
    - 外壳：FairyGUI.Window + InGame/RemoteStorage
    - 顶部：m_Head 页签；m_n5：UI_Bnt_EquipItem 网格
    - 不依赖 Wnd_Simple/UI_WindowEmpty（后者是整屏模板，压不小）
    - 浮窗自绘：ACS 的 obj.tooltips 不可用；Wnd_TipPopPanel 需要真实 Thing.ID
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local B = {}
B.__index = B

local TAB_URL  = "ui://0xrxw6g7qah58x" -- UI_bnt_buildType
local CARD_URL = "ui://0xrxw6g7k0zi4c" -- UI_Bnt_EquipItem
local WINDOW_URL = "ui://0xrxw6g7h0gv2ovtu" -- InGame/RemoteStorage

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_DIM   = "#7A6A55"
local C_WARN  = "#8F2B1B"
local C_OK    = "#1D6B3A"

local function col(c, t)
	-- GRichTextField 走 HTML 解析，不能用旧窗口的 UBB 标记
	return string.format("<font color=\"%s\">%s</font>", c, tostring(t))
end

-- GTextField.wordWrap 未暴露给 XLua，长句只能按 UTF-8 字符手工断行，避免文字冲出浮窗
local function wrapPlain(t, maxChars)
	local s = tostring(t or "")
	if s == "" then return s end
	local out, line, count = {}, {}, 0
	local function flush()
		if #line > 0 then
			out[#out + 1] = table.concat(line)
			line = {}
			count = 0
		end
	end
	local i, n = 1, #s
	while i <= n do
		local b = s:byte(i) or 0
		local len = 1
		if b >= 240 then len = 4
		elseif b >= 224 then len = 3
		elseif b >= 192 then len = 2 end
		local ch = s:sub(i, i + len - 1)
		if ch == "\r" then
			-- 忽略 CR，交给 LF 断行
		elseif ch == "\n" then
			flush()
		else
			line[#line + 1] = ch
			count = count + 1
			if count >= maxChars then flush() end
		end
		i = i + len
	end
	flush()
	return table.concat(out, "<br/>")
end

local function cb0(fn)
	local out = nil
	pcall(function() out = CS.FairyGUI.EventCallback0(fn) end)
	return out
end

local function setVisible(o, v)
	if o == nil then return end
	pcall(function() o.visible = v and true or false end)
end

local function setText(o, t)
	if o == nil then return end
	pcall(function() o.text = (t or "") end)
end

local function setTitle(o, t)
	if o == nil then return end
	pcall(function() o.title = (t or "") end)
end

local function addClick(o, fn)
	if o == nil then return end
	local ok = pcall(function()
		local f = cb0(fn)
		if f ~= nil then
			o.onClick:Add(f)
		else
			o.onClick:Add(fn)
		end
	end)
	if not ok then WFG:Log("[ui] 监听挂载失败（onClick）") end
end

local function addRoll(o, name, fn)
	if o == nil then return end
	pcall(function()
		local f = cb0(fn)
		if f ~= nil then
			o[name]:Add(f)
		else
			o[name]:Add(fn)
		end
	end)
end

local function makeButton(url, title, w, h)
	local o = nil
	pcall(function() o = UIPackage.CreateObjectFromURL(url) end)
	if o == nil then return nil end
	local b = nil
	pcall(function() b = o.asButton end)
	if b == nil then
		WFG:Log("[ui] 控件不是按钮：%s", tostring(url))
		return nil
	end
	pcall(function() b:SetSize(w, h, false) end)
	pcall(function() b.title = title or "" end)
	return b
end

-- 官方按钮图形有固定宽度，缩到筛选/能源按钮尺寸时会互相压边；
-- 这里用精确尺寸的扁平按钮，避免 UI_bnt_buildType 的背景越界。
local function makeFlatButton(text, w, h)
	local btn = nil
	pcall(function() btn = CS.FairyGUI.GButton() end)
	if btn == nil then return nil end
	pcall(function() btn:SetSize(w, h) end)
	pcall(function() btn.opaque = true end)
	pcall(function() btn.touchable = true end)
	-- GGraph.DrawRect(width, height, lineSize, lineColor, fillColor)：
	-- 第 4 个参数是线色，第 5 个才是填充色。写反会让按钮变成深棕底。
	local bgOK = pcall(function()
		local bg = CS.FairyGUI.GGraph()
		bg:DrawRect(w, h, 1, CS.UnityEngine.Color(0.55, 0.42, 0.25, 1), CS.UnityEngine.Color(0.99, 0.95, 0.85, 1))
		bg.touchable = false
		btn:AddChild(bg)
	end)
	if not bgOK then
		WFG:Log("[ui] 扁平按钮背景创建失败")
		-- 保证文字始终是第 2 个子件（索引 1），SetDropdownText 依赖这个索引
		pcall(function()
			local placeholder = CS.FairyGUI.GComponent()
			placeholder:SetSize(w, h)
			btn:AddChild(placeholder)
		end)
	end
	-- 注意：XLua 没有暴露 GTextField.fontSize，直接赋值会在 pcall 内中断，
	-- 导致后面的 text/AddChild 都不执行（这正是筛选条只剩底、没有文字的原因）。
	-- 因而字号用默认值，文字与挂载放在最前面，其它装饰逐项 pcall。
	local label = nil
	pcall(function() label = CS.FairyGUI.GRichTextField() end)
	if label ~= nil then
		pcall(function() btn:AddChild(label) end)
		-- 默认 autoSize=Both，写 text 会把控件缩成文字大小，align 就失去意义；
		-- 先固定尺寸再写文字。
		pcall(function() label.autoSize = CS.FairyGUI.AutoSizeType.None end)
		pcall(function() label:SetSize(w, h) end)
		pcall(function() label:SetXY(0, 0) end)
		pcall(function() label.align = CS.FairyGUI.AlignType.Center end)
		pcall(function() label.verticalAlign = CS.FairyGUI.VertAlignType.Middle end)
		pcall(function() label.color = CS.UnityEngine.Color(0.23, 0.16, 0.08, 1) end)
		pcall(function() label.touchable = false end)
		pcall(function() label.text = tostring(text or "") end)
	end
	return btn
end

local function menuText(t)
	local s = tostring(t or "")
	local p = string.find(s, "：", 1, true)
	if p ~= nil and p + 2 < #s then
		local mark = string.sub(s, p, p + 2)
		return string.sub(s, p + ((mark == "：") and 3 or 1))
	end
	return s
end

local function addChevron(btn, w, h)
	local chev = nil
	pcall(function() chev = CS.FairyGUI.GRichTextField() end)
	if chev == nil then return nil end
	pcall(function() btn:AddChild(chev) end)
	pcall(function() chev.autoSize = CS.FairyGUI.AutoSizeType.None end)
	pcall(function() chev:SetSize(18, h) end)
	pcall(function() chev:SetXY(w - 22, 0) end)
	pcall(function() chev.align = CS.FairyGUI.AlignType.Center end)
	pcall(function() chev.verticalAlign = CS.FairyGUI.VertAlignType.Middle end)
	pcall(function() chev.color = CS.UnityEngine.Color(0.45, 0.32, 0.16, 1) end)
	pcall(function() chev.touchable = false end)
	pcall(function() chev.text = "▾" end)
	return chev
end

-- 下拉选项行：无原生皮肤，避免 UI_bnt_buildType 图形在窄按钮里越界；
-- 选中行用暖金底 + 左侧竖线 + 右侧勾，悬停行叠一层浅色。
local function makeMenuOption(text, w, h, selected)
	local row = nil
	pcall(function() row = CS.FairyGUI.GButton() end)
	if row == nil then return nil end
	pcall(function()
		row:SetSize(w, h)
		row.opaque = true
		row.touchable = true
		row.selected = false
		row.changeStateOnClick = false
	end)
	local fill = selected and CS.UnityEngine.Color(0.955, 0.885, 0.715, 1)
		or CS.UnityEngine.Color(0.985, 0.955, 0.885, 1)
	local line = selected and CS.UnityEngine.Color(0.66, 0.49, 0.24, 0.85)
		or CS.UnityEngine.Color(0.55, 0.42, 0.25, 0.18)
	pcall(function()
		local bg = CS.FairyGUI.GGraph()
		bg:DrawRect(w, h, 1, line, fill)
		bg.touchable = false
		row:AddChild(bg)
	end)
	local hover = nil
	pcall(function()
		hover = CS.FairyGUI.GGraph()
		hover:DrawRect(w - 2, h - 2, 1,
			CS.UnityEngine.Color(0, 0, 0, 0),
			CS.UnityEngine.Color(0.93, 0.83, 0.60, 0.30))
		hover:SetXY(1, 1)
		hover.touchable = false
		hover.visible = false
		row:AddChild(hover)
	end)
	if selected then
		pcall(function()
			local acc = CS.FairyGUI.GGraph()
			acc:DrawRect(3, h - 14, 1,
				CS.UnityEngine.Color(0.66, 0.49, 0.24, 1),
				CS.UnityEngine.Color(0.66, 0.49, 0.24, 1))
			acc:SetXY(5, 7)
			acc.touchable = false
			row:AddChild(acc)
		end)
	end
	local label = nil
	pcall(function() label = CS.FairyGUI.GRichTextField() end)
	if label ~= nil then
		pcall(function() row:AddChild(label) end)
		pcall(function() label.autoSize = CS.FairyGUI.AutoSizeType.None end)
		pcall(function() label:SetSize(w - 46, h) end)
		pcall(function() label:SetXY(14, 0) end)
		pcall(function() label.align = CS.FairyGUI.AlignType.Left end)
		pcall(function() label.verticalAlign = CS.FairyGUI.VertAlignType.Middle end)
		pcall(function()
			label.color = selected and CS.UnityEngine.Color(0.36, 0.23, 0.08, 1)
				or CS.UnityEngine.Color(0.16, 0.12, 0.07, 1)
		end)
		pcall(function() label.touchable = false end)
		-- 文字最后写，且单独 pcall：任何装饰属性失败都不能让选项变成空白
		pcall(function() label.text = menuText(text) end)
	end
	if selected then
		local tick = nil
		pcall(function() tick = CS.FairyGUI.GRichTextField() end)
		if tick ~= nil then
			pcall(function() row:AddChild(tick) end)
			pcall(function() tick.autoSize = CS.FairyGUI.AutoSizeType.None end)
			pcall(function() tick:SetSize(24, h) end)
			pcall(function() tick:SetXY(w - 30, 0) end)
			pcall(function() tick.align = CS.FairyGUI.AlignType.Center end)
			pcall(function() tick.verticalAlign = CS.FairyGUI.VertAlignType.Middle end)
			pcall(function() tick.color = CS.UnityEngine.Color(0.45, 0.30, 0.10, 1) end)
			pcall(function() tick.touchable = false end)
			pcall(function() tick.text = "✓" end)
		end
	end
	addRoll(row, "onRollOver", function() if hover ~= nil then hover.visible = true end end)
	addRoll(row, "onRollOut", function() if hover ~= nil then hover.visible = false end end)
	return row
end

function B:MakeFlatButton(text, w, h)
	return makeFlatButton(text, w, h)
end

function B.new(opts)
	opts = opts or {}
	local self = setmetatable({}, B)
	self.key = opts.key or "browser"
	self.title = opts.title or ""
	self.mode = opts.mode or "grid"
	self.showCount = opts.showCount ~= false
	self.rows = {}
	self.cards = {}
	self.tabs = {}
	self.chips = {}
	self.chipSpecs = {}
	self.failed = false
	self.paused = false
	return self
end

function B:Log(fmt, ...)
	WFG:Log("[ui:" .. tostring(self.key) .. "] " .. tostring(fmt), ...)
end

function B:Ensure()
	if self.win ~= nil then return true end
	if self.failed then return false end
	local ok, err = pcall(function()
		self.win = CS.FairyGUI.Window()
		local obj = UIPackage.CreateObject("InGame", "RemoteStorage")
		if obj == nil then error("RemoteStorage CreateObject 返回空") end
		self.pane = obj.asCom
		if self.pane == nil then error("RemoteStorage 不是 GComponent") end
		self.win.contentPane = self.pane
		self.win.modal = true
		local frameObj = self.pane:GetChildAt(0)
		local gridObj = self.pane:GetChildAt(2)
		local inputObj = self.pane:GetChildAt(4)
		local searchObj = self.pane:GetChildAt(6)
		local headObj = self.pane:GetChildAt(7)
		self.frame = frameObj and frameObj.asCom or nil
		self.grid = gridObj and gridObj.asList or nil
		self.searchInput = inputObj and inputObj.asTextField or nil
		self.searchBtn = searchObj and searchObj.asButton or nil
		self.head = headObj and headObj.asList or nil
		if self.frame == nil or self.grid == nil or self.head == nil then
			error("RemoteStorage 结构不符（frame/grid/head 类型转换失败）")
		end
		self.gridX = self.grid.x
		self.gridY = self.grid.y
		self.gridW = self.grid.width
		self.gridH = self.grid.height
		if self.gridW == nil or self.gridW < 120 then
			self.gridW = math.max(300, (tonumber(self.pane.width) or 780) - (self.gridX or 0) * 2)
		end
		if self.gridH == nil or self.gridH < 120 then
			self.gridH = math.max(200, (tonumber(self.pane.height) or 560) - (self.gridY or 0) - 80)
		end
		-- 标题、关闭钮
		self.titleField = self.frame:GetChildAt(12)
		self.closeBtn = self.frame:GetChildAt(14)
		if self.closeBtn ~= nil then self.closeBtn = self.closeBtn.asButton end
		if self.titleField == nil or self.closeBtn == nil then
			error("RemoteStorage 标题/关闭钮缺失")
		end
		self:SetTitle(self.title)
		self.win.closeButton = self.closeBtn
		-- 关闭动画结束时恢复暂停
		local okHook, hookErr = pcall(function()
			local fn = function() self:OnClosed() end
			local f = cb0(fn)
			if f ~= nil then
				self.win.displayObject.onRemovedFromStage:Add(f)
			else
				self.win.displayObject.onRemovedFromStage:Add(fn)
			end
		end)
		if not okHook then self:Log("关闭监听失败：%s", tostring(hookErr)) end
		-- 搜索按钮
		addClick(self.searchBtn, function()
			self:FireSearch()
		end)
		-- 自绘浮窗：宽度固定、高度按文本自适应；外面留 4px 阴影位
		self.tipW = 310
		self.tip = CS.FairyGUI.GComponent()
		self.tip:SetSize(self.tipW + 4, 124)
		self.tipShadow = CS.FairyGUI.GGraph()
		self.tipShadow:SetXY(4, 4)
		self.tipShadow.touchable = false
		self.tip:AddChild(self.tipShadow)
		self.tipBg = CS.FairyGUI.GGraph()
		self.tipBg.touchable = false
		self.tip:AddChild(self.tipBg)
		self.tipText = CS.FairyGUI.GRichTextField()
		pcall(function() self.tipText.autoSize = CS.FairyGUI.AutoSizeType.None end)
		self.tipText:SetSize(self.tipW - 28, 20)
		self.tipText:SetXY(14, 10)
		pcall(function() self.tipText.color = CS.UnityEngine.Color(0.16, 0.12, 0.07, 1) end)
		pcall(function() self.tipText.align = CS.FairyGUI.AlignType.Left end)
		pcall(function() self.tipText.verticalAlign = CS.FairyGUI.VertAlignType.Top end)
		pcall(function() self.tipText.touchable = false end)
		self.tip:AddChild(self.tipText)
		self.tip.touchable = false
		self.tip.visible = false
		self.pane:AddChild(self.tip)
		self:LayoutTip(120)
		self.tip:SetXY(8, 8)
		-- 底栏
		self.footer = CS.FairyGUI.GRichTextField()
		self.footer:SetSize(self.gridW, 26)
		pcall(function() self.footer.fontSize = 14 end)
		pcall(function() self.footer.color = CS.UnityEngine.Color(0.35, 0.27, 0.16, 1) end)
		pcall(function() self.footer.align = CS.FairyGUI.AlignType.Center end)
		self.pane:AddChild(self.footer)
		self.footer:SetXY(self.gridX, self.gridY + self.gridH - 28)
		self:SetMode(self.mode)
		self:Log("shell pane=%sx%s grid=%s,%s %sx%s", tostring(self.pane.width), tostring(self.pane.height), tostring(self.gridX), tostring(self.gridY), tostring(self.gridW), tostring(self.gridH))
	end)
	if not ok then
		self.failed = true
		WFG:Error("ui.browser." .. tostring(self.key), err)
		self:Log("初始化失败：%s", tostring(err))
		return false
	end
	return true
end

function B:SetTitle(t)
	self.title = t or self.title
	if self.titleField ~= nil then
		pcall(function() self.titleField.text = self.title end)
	end
end

function B:SetMode(mode)
	self.mode = mode or "grid"
	local gridMode = self.mode == "grid"
	setVisible(self.head, gridMode)
	setVisible(self.grid, gridMode)
	setVisible(self.searchInput, gridMode)
	setVisible(self.searchBtn, gridMode)
	setVisible(self.footer, gridMode)
	setVisible(self.empty, gridMode)
	-- m_n6/m_n7/m_n9 是搜索区装饰，能源窗隐藏
	pcall(function() if self.pane then self.pane:GetChildAt(1).visible = gridMode end end)
	pcall(function() if self.pane then self.pane:GetChildAt(3).visible = gridMode end end)
	pcall(function() if self.pane then self.pane:GetChildAt(5).visible = gridMode end end)
	if not gridMode then
		setVisible(self.chipBar, false)
		self:HideTip()
		self:CloseDropdown()
	end
end

function B:SetTabs(cats, current, onTab)
	if not self:Ensure() then return end
	self.tabs = cats or {}
	self.onTab = onTab
	self.currentTab = current or "all"
	if self.head == nil then return end
	pcall(function() self.head:RemoveChildrenToPool() end)
	for i, c in ipairs(self.tabs) do
		local o = nil
		pcall(function() o = self.head:AddItemFromPool(TAB_URL) end)
		local b = o and o.asButton or nil
		if b == nil then
			if o ~= nil then pcall(function() self.head:RemoveChild(o) end) end
			b = makeButton(TAB_URL, c.text, 96, 28)
			if b ~= nil then pcall(function() self.head:AddChild(b) end) end
		end
		if b ~= nil then
			setVisible(b, true)
			-- 池化控件会复用，先清掉上一轮的点击闭包，避免旧页签串台
			pcall(function() if b.onClick ~= nil then b.onClick:Clear() end end)
			pcall(function() b.selected = false end)
			setTitle(b, c.text)
			pcall(function() b.data = c.id end)
			pcall(function() b.selected = (c.id == self.currentTab) end)
			local cid = c.id
			addClick(b, function() self:OnTabClick(cid) end)
		end
	end
	local idx = 1
	for i, c in ipairs(self.tabs) do if c.id == self.currentTab then idx = i break end end
	pcall(function() self.head.selectedIndex = idx - 1 end)
end

function B:SelectTab(id)
	self.currentTab = id
	for i, c in ipairs(self.tabs or {}) do
		if c.id == id then
			pcall(function() self.head.selectedIndex = i - 1 end)
			break
		end
	end
end

function B:OnTabClick(id)
	self:SelectTab(id)
	if self.onTab ~= nil then
		local ok, err = pcall(function() self.onTab(id) end)
		if not ok then WFG:Error("ui.browser.tab", err) end
	end
end

function B:SetChips(specs, onChip)
	if not self:Ensure() then return end
	self.chipSpecs = specs or {}
	self.onChip = onChip
	if self.chipBar == nil then
		self.chipBar = CS.FairyGUI.GComponent()
		self.pane:AddChild(self.chipBar)
	end
	pcall(function() self.chipBar:RemoveChildren(true) end)
	self.chips = {}
	local n = #self.chipSpecs
	if n == 0 then
		setVisible(self.chipBar, false)
		return
	end
	setVisible(self.chipBar, true)
	-- 页签在 m_Head 里，筛选行必须放到页签下方；不能写死 gridY-36，否则两行叠在一起
	local top = self.gridY or 94
	if self.head ~= nil then
		local hy, hh = 0, 0
		pcall(function() hy = self.head.y; hh = self.head.height end)
		-- 只有拿到可信的页签底边才采用；height 为 0 时退回 gridY，避免筛选行压到页签
		if hh ~= nil and hh > 12 and hy ~= nil and hy >= 0 and hy + hh <= self.gridY then
			top = hy + hh
		end
	end
	local chipY = math.max(0, top + 4)
	local gridTop = chipY + 34
	local footerY = self.gridY + self.gridH - 24
	local gridH = math.max(120, footerY - gridTop - 4)
	pcall(function() self.chipBar:SetXY(self.gridX, chipY) end)
	pcall(function() self.chipBar:SetSize(self.gridW, 30) end)
	pcall(function() self.grid:SetXY(self.gridX, gridTop) end)
	pcall(function() self.grid:SetSize(self.gridW, gridH) end)
	if self.empty ~= nil then
		pcall(function() self.empty:SetXY(self.gridX, gridTop + 24) end)
	end
	local gap = 8
	local w = math.floor((self.gridW - gap * (n - 1)) / n)
	if w < 96 then
		gap = 4
		w = math.floor((self.gridW - gap * (n - 1)) / n)
	end
	local total = n * w + (n - 1) * gap
	local x0 = math.max(0, math.floor((self.gridW - total) / 2))
	for i, s in ipairs(self.chipSpecs) do
		local b = makeButton(TAB_URL, s.text or s.id, w, 28)
		if b ~= nil then
			self.chipBar:AddChild(b)
			b:SetXY(x0 + (i - 1) * (w + gap), 0)
			pcall(function() b.selected = false end)
			pcall(function()
				local tf = b:GetChildAt(1)
				if tf ~= nil then tf.fontSize = 12 end
			end)
			self.chips[s.id] = b
			local cid = s.id
			addClick(b, function() self:OnChipClick(cid) end)
		end
	end
	self:RepositionFooter()
end

function B:OnChipClick(id)
	if self.onChip ~= nil then
		local ok, err = pcall(function() self.onChip(id) end)
		if not ok then WFG:Error("ui.browser.chip", err) end
	end
end

function B:SetChipText(id, text)
	self:SetDropdownText(id, text)
end

function B:SetDropdowns(specs, onPick)
	if not self:Ensure() then return end
	self:CloseDropdown()
	self.chipSpecs = specs or {}
	self.dropdownSpecs = self.chipSpecs
	self.dropdownByID = {}
	self.dropdowns = {}
	self.dropdownLabels = {}
	self.dropdownArrows = {}
	self.onDropdownPick = onPick
	if self.chipBar == nil then
		self.chipBar = CS.FairyGUI.GComponent()
		self.pane:AddChild(self.chipBar)
	end
	pcall(function() self.chipBar:RemoveChildren(true) end)
	local n = #self.chipSpecs
	if n == 0 then
		setVisible(self.chipBar, false)
		return
	end
	setVisible(self.chipBar, true)
	local top = self.gridY or 94
	if self.head ~= nil then
		local hy, hh = 0, 0
		pcall(function() hy = self.head.y; hh = self.head.height end)
		if hh ~= nil and hh > 12 and hy ~= nil and hy >= 0 and hy + hh <= self.gridY then
			top = hy + hh
		end
	end
	local barY = math.max(0, top + 4)
	-- 三个以上筛选分两行（3 个为 2+1，4 个为 2+2），避免挤在一条线上越出窗口
	local rowCount = 1
	if n > 2 then rowCount = math.ceil(n / 2) end
	local rowH, rowGap = 32, 6
	local barH = rowCount * rowH + (rowCount - 1) * rowGap
	local gridTop = barY + barH + 8
	local footerY = self.gridY + self.gridH - 24
	local gridH = math.max(120, footerY - gridTop - 4)
	-- 触发器与窗口内框留 8px 呼吸位，避免贴着背景线框
	local inset = 8
	local barW = math.max(160, self.gridW - inset * 2)
	pcall(function() self.chipBar:SetXY(self.gridX + inset, barY) end)
	pcall(function() self.chipBar:SetSize(barW, barH) end)
	pcall(function() self.grid:SetXY(self.gridX, gridTop) end)
	pcall(function() self.grid:SetSize(self.gridW, gridH) end)
	if self.empty ~= nil then
		pcall(function() self.empty:SetXY(self.gridX, gridTop + 24) end)
	end
	local gap = 8
	local i = 1
	local rowIdx = 0
	while i <= n do
		rowIdx = rowIdx + 1
		local count = math.min(2, n - i + 1)
		local w = math.floor((barW - gap * (count - 1)) / count)
		if w < 96 then
			gap = 4
			w = math.floor((barW - gap * (count - 1)) / count)
		end
		local total = count * w + (count - 1) * gap
		local x0 = math.max(0, math.floor((barW - total) / 2))
		for j = 1, count do
			local spec = self.chipSpecs[i + j - 1]
			local btn = makeFlatButton(spec.text or spec.id, w, 30)
			if btn ~= nil then
				self.chipBar:AddChild(btn)
				btn:SetXY(x0 + (j - 1) * (w + gap), (rowIdx - 1) * (rowH + rowGap))
				self.dropdowns[spec.id] = btn
				self.dropdownByID[spec.id] = spec
				local label = nil
				pcall(function() label = btn:GetChildAt(1) end)
				if label ~= nil then
					pcall(function() label:SetSize(w - 24, 30) end)
				end
				self.dropdownLabels[spec.id] = label
				-- 顶部一线浅高光，让米色底不再是一片纯色
				pcall(function()
					local shine = CS.FairyGUI.GGraph()
					shine:DrawRect(w - 10, 1, 1,
						CS.UnityEngine.Color(1, 0.985, 0.94, 0.55),
						CS.UnityEngine.Color(1, 0.985, 0.94, 0.55))
					shine:SetXY(5, 1)
					shine.touchable = false
					btn:AddChild(shine)
				end)
				self.dropdownArrows[spec.id] = addChevron(btn, w, 30)
				addClick(btn, function() self:ToggleDropdown(spec.id) end)
			end
		end
		i = i + count
	end
	self:RepositionFooter()
end

function B:SetDropdownText(id, text)
	local label = self.dropdownLabels and self.dropdownLabels[id]
	if label ~= nil then label.text = tostring(text or "") end
end

function B:CloseDropdown()
	if self.dropdownBlocker ~= nil then
		pcall(function() self.dropdownBlocker:Dispose() end)
		self.dropdownBlocker = nil
	end
	if self.dropdownPopup ~= nil then
		pcall(function() self.dropdownPopup:Dispose() end)
	end
	self.dropdownPopup = nil
	self.dropdownId = nil
	for _, chev in pairs(self.dropdownArrows or {}) do
		pcall(function()
			chev.text = "▾"
			chev.color = CS.UnityEngine.Color(0.45, 0.32, 0.16, 1)
		end)
	end
end

function B:ShowOptionPopupAt(x, y, w, options, onPick, selected, anchorTop)
	if not self:Ensure() then return end
	self:CloseDropdown()
	self:HideTip()
	local opts = options or {}
	if #opts == 0 then return end
	local paneW, paneH = 470, 524
	pcall(function() paneW = self.pane.width; paneH = self.pane.height end)
	local margin = 10
	local pw = math.max(180, math.min(260, tonumber(w) or 180))
	if pw > paneW - margin * 2 then pw = paneW - margin * 2 end
	local rowH = 32
	local ph = #opts * rowH + 14
	local px = tonumber(x) or margin
	local py = tonumber(y) or margin
	if px + pw + 4 > paneW - margin then px = paneW - margin - pw - 4 end
	if px < margin then px = margin end
	-- 下方空间不够时翻到触发器上方，避免压住底部按钮
	if py + ph + 4 > paneH - margin then
		if anchorTop ~= nil then
			py = (tonumber(anchorTop) or py) - ph - 10
		else
			py = paneH - margin - ph - 4
		end
	end
	if py < margin then py = margin end
	if py + ph + 4 > paneH - margin then py = math.max(margin, paneH - margin - ph - 4) end
	-- 全屏透明挡板：点击菜单以外任何位置都关闭；挡板在菜单下面，不挡选项点击
	local blocker = CS.FairyGUI.GComponent()
	blocker:SetSize(paneW, paneH)
	blocker:SetXY(0, 0)
	blocker.opaque = true
	blocker.touchable = true
	addClick(blocker, function() self:CloseDropdown() end)
	self.pane:AddChild(blocker)
	self.dropdownBlocker = blocker
	local popup = CS.FairyGUI.GComponent()
	popup:SetSize(pw + 4, ph + 4)
	local shadow = CS.FairyGUI.GGraph()
	shadow:DrawRect(pw, ph, 1,
		CS.UnityEngine.Color(0.12, 0.08, 0.03, 0.22),
		CS.UnityEngine.Color(0.12, 0.08, 0.03, 0.22))
	shadow:SetXY(4, 4)
	shadow.touchable = false
	popup:AddChild(shadow)
	local bg = CS.FairyGUI.GGraph()
	bg:DrawRect(pw, ph, 1,
		CS.UnityEngine.Color(0.50, 0.37, 0.21, 1),
		CS.UnityEngine.Color(0.985, 0.955, 0.885, 1))
	bg.touchable = false
	popup:AddChild(bg)
	pcall(function()
		local topLine = CS.FairyGUI.GGraph()
		topLine:DrawRect(pw - 12, 1, 1,
			CS.UnityEngine.Color(0.92, 0.78, 0.52, 0.75),
			CS.UnityEngine.Color(0.92, 0.78, 0.52, 0.75))
		topLine:SetXY(6, 2)
		topLine.touchable = false
		popup:AddChild(topLine)
	end)
	for i, opt in ipairs(opts) do
		local value = opt[1]
		local text = opt[2] or tostring(value)
		local isSel = (selected ~= nil and value == selected)
		local row = makeMenuOption(text, pw - 16, 30, isSel)
		if row ~= nil then
			row:SetXY(8, 8 + (i - 1) * rowH)
			addClick(row, function()
				self:CloseDropdown()
				if onPick ~= nil then
					local ok, err = pcall(function() onPick(value) end)
					if not ok then WFG:Error("ui.browser.option", err) end
				end
			end)
			popup:AddChild(row)
		end
		if i < #opts then
			pcall(function()
				local sep = CS.FairyGUI.GGraph()
				sep:DrawRect(pw - 24, 1, 1,
					CS.UnityEngine.Color(0.55, 0.42, 0.25, 0.16),
					CS.UnityEngine.Color(0.55, 0.42, 0.25, 0.16))
				sep:SetXY(12, 8 + i * rowH - 1)
				sep.touchable = false
				popup:AddChild(sep)
			end)
		end
	end
	popup:SetXY(px, py)
	self.pane:AddChild(popup)
	self.dropdownPopup = popup
end

function B:OpenDropdown(id)
	local spec = self.dropdownByID and self.dropdownByID[id]
	local trigger = self.dropdowns and self.dropdowns[id]
	if spec == nil or trigger == nil then return end
	local top = self.chipBar.y + trigger.y
	local x = self.chipBar.x + trigger.x
	local y = top + trigger.height + 6
	self:ShowOptionPopupAt(x, y, trigger.width, spec.options, function(value)
		if self.onDropdownPick ~= nil then
			local ok, err = pcall(function() self.onDropdownPick(id, value) end)
			if not ok then WFG:Error("ui.browser.dropdown", err) end
		end
	end, spec.value, top)
	if self.dropdownPopup ~= nil then
		self.dropdownId = id
		local chev = self.dropdownArrows and self.dropdownArrows[id]
		if chev ~= nil then
			pcall(function()
				chev.text = "▴"
				chev.color = CS.UnityEngine.Color(0.62, 0.44, 0.18, 1)
			end)
		end
	end
end

function B:ToggleDropdown(id)
	if self.dropdownPopup ~= nil and self.dropdownId == id then
		self:CloseDropdown()
		return
	end
	self:OpenDropdown(id)
end

function B:SetSearchHandler(fn)
	self.onSearch = fn
end

function B:FireSearch()
	local text = ""
	pcall(function() text = self.searchInput.text or "" end)
	if self.onSearch ~= nil then
		local ok, err = pcall(function() self.onSearch(text) end)
		if not ok then WFG:Error("ui.browser.search", err) end
	end
end

function B:ClearCards()
	pcall(function() self.grid:RemoveChildrenToPool() end)
	self.cards = {}
end

function B:CardCount()
	return #self.cards
end

function B:MakeButton(title, w, h)
	return makeButton(TAB_URL, title, w, h)
end

function B:AddPanel(panel)
	if self.pane ~= nil and panel ~= nil then self.pane:AddChild(panel) end
end

function B:SetItems(items, opts)
	if not self:Ensure() then return end
	opts = opts or {}
	self.showCount = opts.showCount ~= false
	self.onPick = opts.onPick
	self.tipKind = opts.tipKind or "material"
	self.selectedDef = opts.selectedDef
	self.emptyText = opts.emptyText or "暂无素材"
	self:ClearCards()
	self.rows = items or {}
	local failed = 0
	for i, e in ipairs(self.rows) do
		local o = nil
		pcall(function() o = self.grid:AddItemFromPool(CARD_URL) end)
		local card = o and o.asButton or nil
		if card == nil then
			if o ~= nil then pcall(function() self.grid:RemoveChild(o) end) end
			local cobj = nil
			pcall(function() cobj = UIPackage.CreateObjectFromURL(CARD_URL) end)
			if cobj == nil then pcall(function() cobj = UIPackage.CreateObject("InGame", "Bnt_EquipItem") end) end
			card = cobj and cobj.asButton or nil
			if card ~= nil then pcall(function() self.grid:AddChild(card) end) end
		end
		if card ~= nil then
			pcall(function() card.visible = true end)
			pcall(function() card.selected = false end)
			-- 池化卡片复用时清掉旧闭包，否则新卡片会带着旧 item 回调
			pcall(function() if card.onClick ~= nil then card.onClick:Clear() end end)
			pcall(function() if card.onRollOver ~= nil then card.onRollOver:Clear() end end)
			pcall(function() if card.onRollOut ~= nil then card.onRollOut:Clear() end end)
			self.cards[#self.cards + 1] = card
			pcall(function() card.data = e.defName or e.name or "" end)
			pcall(function() card.icon = "thing://2," .. tostring(e.defName or "") end)
			pcall(function() card.title = tostring(e.name or e.defName or "?") end)
			local count = nil
			pcall(function() count = card:GetChildAt(6) end)
			if count ~= nil then
				if self.showCount then
					count.visible = true
					count.text = tostring(e.n or 0)
				else
					count.visible = false
				end
			end
			local use = nil
			pcall(function() use = card:GetChildAt(5) end)
			if use ~= nil then
				if e.q ~= nil then
					use.visible = true
					use.text = "品质 " .. tostring(e.q)
				else
					use.visible = false
				end
			end
			if self.selectedDef ~= nil and e.defName == self.selectedDef then
				pcall(function() card.selected = true end)
			end
			local item = e
			addClick(card, function()
				if self.onPick ~= nil then
					local ok, err = pcall(function() self.onPick(item, card) end)
					if not ok then WFG:Error("ui.browser.pick", err) end
				end
			end)
			addRoll(card, "onRollOver", function() self:ShowTip(card, item) end)
			addRoll(card, "onRollOut", function() self:HideTip() end)
		else
			failed = failed + 1
		end
	end
	if failed > 0 then
		self:Log("card 创建失败 %d/%d", failed, #self.rows)
	end
	-- 空态
	if self.empty == nil then
		self.empty = CS.FairyGUI.GRichTextField()
		self.empty:SetSize(self.gridW, 120)
		pcall(function() self.empty.fontSize = 16 end)
		pcall(function() self.empty.color = CS.UnityEngine.Color(0.48, 0.40, 0.30, 1) end)
		pcall(function() self.empty.align = CS.FairyGUI.AlignType.Center end)
		self.pane:AddChild(self.empty)
	end
	if self.empty ~= nil then
		local gy = self.gridY
		pcall(function() gy = self.grid.y end)
		self.empty:SetXY(self.gridX, gy + 24)
		self.empty:SetSize(self.gridW, 120)
		self.empty.text = self.emptyText or "暂无"
		self.empty.visible = (#self.rows == 0)
	end
	-- 浮窗、底栏必须在卡片之后，保证在最上层
	if self.empty ~= nil then pcall(function() self.pane:AddChild(self.empty) end) end
	if self.tip ~= nil then pcall(function() self.pane:AddChild(self.tip) end) end
	if self.footer ~= nil then pcall(function() self.pane:AddChild(self.footer) end) end
	self:RepositionFooter()
	self:Log("items=%d cards=%d", #self.rows, #self.cards)
end

function B:RepositionFooter()
	if self.footer == nil then return end
	local y = self.gridY + self.gridH - 28
	if self.chipBar ~= nil and #self.chipSpecs > 0 then y = self.gridY + self.gridH - 24 end
	pcall(function() self.footer:SetXY(self.gridX, y) end)
	pcall(function() self.footer:SetSize(self.gridW, 24) end)
end

function B:SetFooter(text)
	self.footerText = text or ""
	setText(self.footer, self.footerText)
end

function B:LayoutTip(h)
	if self.tip == nil or self.tipBg == nil then return end
	local w = self.tipW or 340
	h = math.max(80, tonumber(h) or 120)
	local paneH = 524
	pcall(function() paneH = self.pane.height end)
	h = math.min(h, math.max(80, paneH - 20))
	self.tip:SetSize(w + 4, h + 4)
	if self.tipShadow ~= nil then
		pcall(function()
			self.tipShadow:SetXY(4, 4)
			self.tipShadow:DrawRect(w, h, 1,
				CS.UnityEngine.Color(0.12, 0.08, 0.03, 0.22),
				CS.UnityEngine.Color(0.12, 0.08, 0.03, 0.22))
		end)
	end
	pcall(function()
		self.tipBg:SetXY(0, 0)
		self.tipBg:DrawRect(w, h, 1,
			CS.UnityEngine.Color(0.50, 0.37, 0.21, 1),
			CS.UnityEngine.Color(0.985, 0.955, 0.885, 1))
	end)
	pcall(function() self.tipText:SetSize(w - 28, h - 20) end)
end

function B:ShowTip(card, e)
	if self.tip == nil or self.tipText == nil then return end
	local line = {}
	line[#line + 1] = col(C_TITLE, wrapPlain(e.name or e.defName or "?", 22))
	local meta = {}
	if e.kind ~= nil then meta[#meta + 1] = "类别 " .. tostring(e.kind) end
	if e.lv ~= nil then meta[#meta + 1] = "阶 " .. tostring(e.lv) end
	if e.q ~= nil then meta[#meta + 1] = "品 " .. tostring(e.q) end
	if #meta > 0 then line[#line + 1] = col(C_DIM, wrapPlain(table.concat(meta, " · "), 22)) end
	-- 数据窗显示收录状态；创造窗不显示库存数字
	if self.tipKind == "material" then
		line[#line + 1] = col(C_LABEL, "共享总库已收录")
	end
	if e.stuffs ~= nil or e.quals ~= nil then
		line[#line + 1] = string.format("%s %d 种　%s %d 级",
			col(C_LABEL, "材料"), #(e.stuffs or {}), col(C_LABEL, "品级"), #(e.quals or {}))
	end
	local desc = nil
	pcall(function()
		local def = WFG.item and WFG.item:Def(e.defName)
		if def ~= nil then desc = def.Desc end
	end)
	if desc ~= nil and tostring(desc) ~= "" then
		line[#line + 1] = col(C_VALUE, wrapPlain(desc, 22))
	end
	local hint = (self.tipKind == "material") and "悬停查看；素材汇入与取用全自动"
		or "单击选中，再点一次进入确认"
	line[#line + 1] = col(C_OK, wrapPlain(hint, 22))
	pcall(function() self.tipText.autoSize = CS.FairyGUI.AutoSizeType.None end)
	pcall(function() self.tipText:SetSize((self.tipW or 340) - 28, 20) end)
	self.tipText.text = table.concat(line, "<br/>")
	-- 文本高度取不到时用字符数估算，避免文字超出边框
	local th = 0
	pcall(function() th = self.tipText.textHeight end)
	if th == nil or th < 40 then
		th = 0
		for _, s in ipairs(line) do
			local plain = tostring(s):gsub("<[^>]->", "")
			local chars = math.floor(#plain / 3)
			th = th + math.max(1, math.ceil(chars / 24)) * 20
		end
	end
	self:LayoutTip(math.max(80, th + 20))
	self.tip.visible = true
	pcall(function() self.pane:AddChild(self.tip) end)
	local p = nil
	pcall(function()
		local g = card:LocalToGlobal(CS.UnityEngine.Vector2(0, 0))
		p = self.pane:GlobalToLocal(g)
	end)
	if p ~= nil then
		local pw, ph = self.pane.width, self.pane.height
		local x = p.x + card.width + 10
		local y = p.y
		local rightFits = (x + self.tip.width <= pw - 8)
		local belowY = p.y + card.height + 8
		local aboveY = p.y - self.tip.height - 8
		if rightFits then
			-- 右侧优先；纵向放不下时翻到卡片上方，避免与卡片重叠导致 rollOut 闪烁
			if y + self.tip.height > ph - 8 then
				if aboveY >= 8 then y = aboveY else y = ph - self.tip.height - 8 end
			end
		else
			-- 右侧空间不足时放到卡片下方；下方也不够再放到上方
			x = p.x + (card.width - self.tip.width) * 0.5
			if belowY + self.tip.height <= ph - 8 then
				y = belowY
			elseif aboveY >= 8 then
				y = aboveY
			else
				y = ph - self.tip.height - 8
			end
		end
		if x < 8 then x = 8 end
		if x + self.tip.width > pw - 8 then x = math.max(8, pw - self.tip.width - 8) end
		if y < 8 then y = 8 end
		if y + self.tip.height > ph - 8 then y = math.max(8, ph - self.tip.height - 8) end
		self.tip:SetXY(x, y)
	end
end

function B:HideTip()
	if self.tip ~= nil then self.tip.visible = false end
end

function B:Show()
	if not self:Ensure() then return false end
	if self.win == nil then return false end
	local ok, err = pcall(function()
		self.win:Show()
	end)
	if ok then
		pcall(function() self.win:CenterOn(CS.FairyGUI.GRoot.inst, true) end)
	end
	if not ok then
		self:Log("Show 失败：%s", tostring(err))
		WFG:Error("ui.browser.show." .. tostring(self.key), err)
		return false
	end
	self.visible = true
	self:HideTip()
	if not self.paused then
		pcall(function() WFG.ui:Pause() end)
		self.paused = true
	end
	return true
end

function B:OnClosed()
	self.visible = false
	self:CloseDropdown()
	self:HideTip()
	if self.paused then
		self.paused = false
		pcall(function() WFG.ui:Resume() end)
	end
end

function B:Close()
	self:CloseDropdown()
	if self.win ~= nil then pcall(function() self.win:Hide() end) end
	self:OnClosed()
end

function B:Dispose()
	if self.win ~= nil then pcall(function() self.win:Dispose() end) end
	self.win = nil
	self.pane = nil
end

WFG.ui.browser = B
return B

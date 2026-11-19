--[[
    万法阁 · 衍天珠凝练窗
    布局（560×380）：
        y= 46  当前灵气
        y= 72  可凝练颗数
        y=118  [数量] [滑条] [×N]
        y=158  本次消耗
        y=192  服用说明
        y=216  佩带说明
        y=246  已服用层数
        y=300  [凝练] [取消]
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("WFG_NingZhu")

local URL_BTN   = "ui://0xrxw6g7hdhl18"
local URL_LABEL = "ui://0xrxw6g7nd594l"
local URL_SLD   = "ui://0xrxw6g7hdhl1e"

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_ACCENT= "#8A5A0F"
local C_WARN  = "#8F2B1B"
local C_DIM   = "#8A7A5E"

local WIN_W, WIN_H = 560, 380
local COST = 500
local MAX_BATCH = 999
local ZHU_MAX = 4

local C = WFG.ui.ningzhu or {}
WFG.ui.ningzhu = C

------------------------------------------------------------------
-- 小工具
------------------------------------------------------------------
local function col(color, text)
	return string.format("[color=%s]%s[/color]", color, text)
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(text, title or "衍天·凝练") end)
	WFG:Log("[凝练] %s", tostring(text))
end

local function cb0(fn)
	local out = nil
	pcall(function() out = CS.FairyGUI.EventCallback0(fn) end)
	return out
end

local function addRaw(url, name, x, y, w, h)
	local obj = nil
	local ok = pcall(function() obj = tbWindow:AddObjectFromUrl(url, x, y) end)
	if not ok or obj == nil then
		WFG:Log("[凝练] 取控件失败：%s（%s）", tostring(name), tostring(url))
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

local function zhuCount(npc)
	local c = nil
	local m = mod()
	if m ~= nil and m.Char ~= nil then
		local ok, d = pcall(function() return m:Char(npc, false) end)
		if ok then c = d end
	end
	if c == nil then return 0 end
	local n = tonumber(c.zhu) or 0
	if n ~= n then n = 0 end
	return math.max(0, math.min(ZHU_MAX, math.floor(n)))
end

------------------------------------------------------------------
-- 数据
------------------------------------------------------------------
function C:MaxCount()
	if self.npc == nil then return 0 end
	local ling = 0
	pcall(function() ling = WFG:Ling(self.npc) or 0 end)
	ling = tonumber(ling) or 0
	if ling ~= ling then ling = 0 end
	local n = math.floor(ling / COST)
	if n ~= n then n = 0 end
	if n > MAX_BATCH then n = MAX_BATCH end
	return math.max(0, n)
end

function C:ApplyCount(v, syncSlider)
	local maxN = self:MaxCount()
	v = tonumber(v) or 1
	if v ~= v then v = 1 end
	v = math.floor(v)
	if maxN < 1 then
		v = 1
	else
		if v < 1 then v = 1 end
		if v > maxN then v = maxN end
	end
	self.count = v
	self.maxN = maxN

	local w = self.w
	if w ~= nil and w.Sld ~= nil then
		local locked = (maxN <= 1)
		-- min 与 max 相等时 FairyGUI 滑条会算出 0/0，value 变成 -nan(ind)
		pcall(function() w.Sld.max = math.max(2, maxN) end)
		pcall(function() w.Sld.touchable = not locked end)
		pcall(function() w.Sld.grayed = locked end)
		if syncSlider == true or locked then
			local was = self.syncing
			self.syncing = true
			pcall(function() w.Sld.value = v end)
			self.syncing = was
		end
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

------------------------------------------------------------------
-- 构建（只建一次）
------------------------------------------------------------------
function C:Build()
	if self.built == true then return end
	local w = {}

	w.LInfo  = addLabel("WFG_NzLInfo", "当前灵气：-", 0, 0, 480, 24)
	w.LInfo2 = addLabel("WFG_NzLInfo2", "可凝练 0 颗", 0, 0, 480, 24)

	w.LQty = addLabel("WFG_NzLQty", "数量", 0, 0, 64, 24)
	w.Sld  = addRaw(URL_SLD, "WFG_NzSld", 0, 0, 300, 22)
	w.VQty = addLabel("WFG_NzVQty", "×1", 0, 0, 72, 24)

	w.LCost = addLabel("WFG_NzLCost", "", 0, 0, 480, 24)
	w.LHint1 = addLabel("WFG_NzLHint1", "", 0, 0, 480, 22)
	w.LHint2 = addLabel("WFG_NzLHint2", "", 0, 0, 480, 22)
	w.LZhu  = addLabel("WFG_NzLZhu", "", 0, 0, 480, 24)

	w.Ok     = addBtn("WFG_NzOk", "凝练 ×1", 0, 0, 170, 36)
	w.Cancel = addBtn("WFG_NzCancel", "取消", 0, 0, 110, 36)
	self.w = w

	if w.Sld ~= nil then
		pcall(function() w.Sld.min = 1 end)
		-- 先给 max=2：Refresh 之前 max==min 会让滑条 value 变成 NaN
		pcall(function() w.Sld.max = 2 end)
		pcall(function() w.Sld.value = 1 end)
		pcall(function() w.Sld.touchable = false end)
		pcall(function() w.Sld.wholeNumbers = true end)
		local cb = cb0(function() C:OnSliderMoved() end)
		if cb ~= nil then pcall(function() w.Sld.onChanged:Add(cb) end) end
	end

	self.built = true
	WFG:Log("[凝练] 构建完成 滑条=%s", tostring(w.Sld ~= nil))
end

function C:Layout()
	local w = self.w
	if w == nil then return end

	local pw, ph = WIN_W, WIN_H
	pcall(function()
		local pane = tbWindow.window.contentPane
		if pane ~= nil then pw = pane.width; ph = pane.height end
	end)
	if pw == nil or pw < WIN_W then pw = WIN_W end
	if ph == nil or ph < WIN_H then ph = WIN_H end

	local L = 40
	local R = pw - 40
	local qw = 72
	local vw = 72

	local function setSize(o, a, b)
		if o == nil then return end
		pcall(function() o:SetSize(a, b) end)
	end

	setSize(w.LInfo, R - L, 24);  setXY(w.LInfo, L, 46)
	setSize(w.LInfo2, R - L, 24); setXY(w.LInfo2, L, 74)

	setSize(w.LQty, 64, 24); setXY(w.LQty, L, 120)
	setSize(w.Sld, math.max(160, R - L - qw - 12 - vw - 12), 22); setXY(w.Sld, L + qw + 12, 122)
	setSize(w.VQty, vw, 24); setXY(w.VQty, R - vw, 120)

	setSize(w.LCost, R - L, 24);   setXY(w.LCost, L, 158)
	setSize(w.LHint1, R - L, 22);  setXY(w.LHint1, L, 192)
	setSize(w.LHint2, R - L, 22);  setXY(w.LHint2, L, 216)
	setSize(w.LZhu, R - L, 24);    setXY(w.LZhu, L, 246)

	local bw1, bw2, gap = 170, 110, 28
	local bx = math.floor((pw - (bw1 + gap + bw2)) / 2)
	setXY(w.Ok, bx, 300)
	setXY(w.Cancel, bx + bw1 + gap, 300)
end

------------------------------------------------------------------
-- 渲染
------------------------------------------------------------------
function C:Render()
	local w = self.w
	if w == nil then return end

	if self.npc == nil then
		setTitle(w.LInfo, col(C_WARN, "未找到施术者。"))
		setTitle(w.LInfo2, "")
		setTitle(w.LCost, "")
		setTitle(w.LZhu, "")
		setVisible(w.Ok, false)
		return
	end

	local ling, maxLing = 0, 0
	pcall(function() ling = WFG:Ling(self.npc) or 0 end)
	pcall(function() maxLing = WFG:MaxLing(self.npc) or 0 end)
	ling = tonumber(ling) or 0
	maxLing = tonumber(maxLing) or 0
	if ling ~= ling then ling = 0 end
	if maxLing ~= maxLing then maxLing = 0 end
	local maxN = self:MaxCount()
	local n = tonumber(self.count) or 1
	if n ~= n then n = 1 end
	n = math.floor(n)
	if maxN >= 1 then
		if n < 1 then n = 1 end
		if n > maxN then n = maxN end
	end
	self.count = n

	setTitle(w.LInfo, string.format("%s：%s　%s：%s",
		col(C_LABEL, "当前灵气"), col(C_VALUE, tostring(math.floor(ling))),
		col(C_LABEL, "灵气上限"), col(C_VALUE, tostring(math.floor(maxLing)))))
	if maxN < 1 then
		setTitle(w.LInfo2, col(C_WARN, string.format("灵气不足 %d，无法凝练。", COST)))
	elseif maxN >= MAX_BATCH then
		setTitle(w.LInfo2, col(C_VALUE, string.format("单次最多 %d 颗（灵气上限内可凝练 %d 颗）", MAX_BATCH, maxN)))
	elseif maxN == 1 then
		setTitle(w.LInfo2, col(C_VALUE, "本次最多可凝练 1 颗（数量已锁定）"))
	else
		setTitle(w.LInfo2, col(C_VALUE, string.format("本次最多可凝练 %d 颗", maxN)))
	end

	setTitle(w.VQty, col(C_VALUE, "×" .. tostring(n)))
	setTitle(w.Ok, string.format("凝练 ×%d", n))

	local total = n * COST
	if maxN < 1 or ling < total then
		setTitle(w.LCost, col(C_WARN, string.format("灵气不足：需要 %d，还差 %d。", total, total - math.floor(ling))))
	else
		setTitle(w.LCost, string.format("%s　%s",
			col(C_ACCENT, string.format("本次消耗 %d 灵气", total)),
			col(C_DIM, string.format("（%d × %d）", n, COST))))
	end

	setTitle(w.LHint1, col(C_LABEL, "服用：立刻恢复 10% 最大灵气；永久 +25% 根本灵气（最多 4 次）"))
	setTitle(w.LHint2, col(C_LABEL, "佩带：心境 +100　｜　炼制灵析剑 / 灵源剑的核心材料"))

	local zhu = zhuCount(self.npc)
	setTitle(w.LZhu, string.format("%s：%s",
		col(C_LABEL, "已服用的衍天珠"),
		col(C_VALUE, string.format("%d / %d（永久 +%d%% 根本灵气）", zhu, ZHU_MAX, zhu * 25))))

	setVisible(w.Ok, maxN >= 1 and ling >= total)
end

------------------------------------------------------------------
-- 交互
------------------------------------------------------------------
function C:OnClick(name)
	if name == "WFG_NzOk" then
		self:Confirm()
	elseif name == "WFG_NzCancel" then
		self:Close()
	end
end

function C:Confirm()
	if self.npc == nil then say("未找到施术者。") return end

	local maxN = self:MaxCount()
	local n = tonumber(self.count) or 1
	if n ~= n then n = 1 end
	n = math.floor(n)
	if maxN < 1 then say(string.format("灵气不足 %d，无法凝练。", COST)) return end
	if n < 1 then n = 1 end
	if n > maxN then n = maxN end

	local cost = n * COST
	local have = 0
	pcall(function() have = WFG:Ling(self.npc) or 0 end)
	have = tonumber(have) or 0
	if have ~= have then have = 0 end
	if have < cost then say(string.format("灵气不足：需要 %d，当前 %d。", cost, math.floor(have))) return end

	local ok, err = pcall(function() self.npc:AddLing(-cost) end)
	if not ok then
		WFG:Error("ningzhu.ling", err)
		say("扣除灵气失败（详见日志）")
		return
	end

	local created, cerr = false, nil
	local cok, ret = pcall(function() return WFG.item:Create("WFG_Item_YanTianZhu", 3, n, self.npc) end)
	if not cok then
		cerr = ret
	elseif ret ~= true then
		cerr = "Create 返回 false"
	end
	if cerr ~= nil then
		pcall(function() self.npc:AddLing(cost) end)
		WFG:Error("ningzhu.create", cerr)
		say("凝练失败，灵气已退回（详见日志）")
		return
	end

	WFG:Log("[凝练] %s 凝练衍天珠 ×%d，消耗灵气 %d", tostring(self.npc.Name or "?"), n, cost)
	self:Close()
	say(string.format("已凝练衍天珠 ×%d（消耗 %d 灵气）", n, cost))
end

------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------
function C:Open(npc)
	self.npc = npc
	self.count = 1
	self.maxN = 0
	self.syncing = false

	tbWindow:SetSize(WIN_W, WIN_H)
	tbWindow:Show()
	pcall(function() tbWindow:SetTitle("衍天 · 凝练衍天珠") end)
	pcall(function() tbWindow.window:Center() end)
	if not self.paused then
		pcall(function() WFG.ui:Pause() end)
		self.paused = true
	end

	self:Build()
	self:Layout()
	self:Refresh()
end

function C:Refresh()
	local maxN = self:MaxCount()
	self.maxN = maxN
	self:ApplyCount(self.count or 1, true)
end

function C:Close()
	local was = self.paused == true
	self.paused = false
	pcall(function() tbWindow:Hide() end)
	if was then pcall(function() WFG.ui:Resume() end) end
end

function tbWindow:OnInit()
end

function tbWindow:OnShown()
	pcall(function() C:Build() end)
	pcall(function() C:Layout() end)
	pcall(function() C:Refresh() end)
end

-- 标题栏关闭也要恢复游戏速度
function tbWindow:OnHide()
	if C.paused then
		C.paused = false
		pcall(function() WFG.ui:Resume() end)
	end
end

function tbWindow:OnObjectEvent(t, obj, context)
	if t ~= "onClick" or obj == nil then return end
	local name = nil
	pcall(function() name = obj.name end)
	if name == nil then return end
	WFG:Log("[凝练] 点击控件：%s", name)
	local ok, err = pcall(function() C:OnClick(name) end)
	if not ok then WFG:Error("ningzhu.click", err) end
end

return C

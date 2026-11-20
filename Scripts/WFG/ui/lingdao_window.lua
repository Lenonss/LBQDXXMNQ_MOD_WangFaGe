--[[
    万法阁 · 灵道剑窗口
    - 入口：角色指令栏「灵道剑」（module 每秒按「佩剑 / 有存道」维护按钮）
    - 存入：把自身道行扣进剑里；取回：把存道加回自身道行
    - 加成 = 存道 × rate（def.lua 的 D.lingDao.rate，默认每点 +1%，无上限）
    - 壳与控件全部沿用 hall_window 已实机验证的原语：WFG.ui.browser + GRichTextField + MakeFlatButton
      （不使用 WFG.ui.kit：kit 控件进入游戏后未验证，会在建面板阶段静默抛错导致窗口不弹）
]]
WFG = WFG or {}
WFG.ui = WFG.ui or {}

local C = WFG.ui.lingdao or {}
WFG.ui.lingdao = C

local COL_TEXT  = CS.UnityEngine.Color(0.23, 0.16, 0.08, 1)
local COL_LABEL = CS.UnityEngine.Color(0.42, 0.32, 0.20, 1)
local COL_DIM   = CS.UnityEngine.Color(0.48, 0.41, 0.32, 1)
local COL_OK    = CS.UnityEngine.Color(0.11, 0.42, 0.23, 1)
local COL_WARN  = CS.UnityEngine.Color(0.56, 0.17, 0.11, 1)

local function say(text, title)
	pcall(function() world:ShowMsgBox(tostring(text), title or "灵道剑") end)
	WFG:Log("[灵道剑] %s", tostring(text))
end

-- 必须本地定义：仓库里没有全局 cb0，之前直接调全局 cb0 会抛错，
-- 而 addClick 外层 pcall 把错误吞掉 → 所有按钮"看得见、点不动"。
local function cb0(fn)
	local out = nil
	pcall(function() out = CS.FairyGUI.EventCallback0(fn) end)
	return out
end

local function addClick(o, fn)
	if o == nil then return end
	local ok, err = pcall(function()
		local f = cb0(fn)
		if f ~= nil then o.onClick:Add(f) else o.onClick:Add(fn) end
	end)
	if not ok then
		WFG:Error("ui.lingdao.click", tostring(err))
		say("按钮事件挂载失败：" .. tostring(err), "灵道剑")
	end
end

local function modRef()
	return WFG.GetModule and WFG:GetModule("yantian") or nil
end

local function isYanNpc(npc)
	if npc == nil then return false end
	local ok, g = pcall(function() return WFG.npc:GetGongName(npc) end)
	return ok and g == (WFG.YanTianDef and WFG.YanTianDef.gong)
end

local function pctText(v)
	return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5))
end

------------------------------------------------------------
-- 壳（惰性创建，Close 只隐藏）
------------------------------------------------------------
local browser = nil
local function shell()
	if browser ~= nil then return browser end
	local B = WFG.ui.browser
	if B == nil then
		WFG:Error("ui.lingdao", "fgui_browser.lua 未加载")
		return nil
	end
	browser = B.new({ key = "lingdao", title = "灵道剑", mode = "blank" })
	return browser
end

------------------------------------------------------------
-- 面板
------------------------------------------------------------
function C:EnsurePanel()
	if self.panel ~= nil then return true end
	local b = shell()
	if b == nil then return false end
	if not b:Ensure() then return false end
	b:SetTitle("灵道剑")
	b:SetMode("blank")

	local paneW, paneH = 470, 524
	pcall(function() paneW = b.pane.width; paneH = b.pane.height end)
	local pad = b.gridX or 21
	local gw = math.max(360, (tonumber(paneW) or 470) - pad * 2)
	local gh = math.max(380, (tonumber(paneH) or 524) - 96)
	self.gw, self.gh = gw, gh

	self.panel = CS.FairyGUI.GComponent()
	self.panel:SetSize(gw, gh)
	b:AddPanel(self.panel)
	self.panel:SetXY(pad, 72)

	local panel = self.panel
	local function label(text, x, y, w, align, color, size)
		local t = CS.FairyGUI.GRichTextField()
		pcall(function() t.autoSize = CS.FairyGUI.AutoSizeType.None end)
		t:SetSize(w or gw, 22)
		t:SetXY(x or 0, y or 0)
		pcall(function() t.color = color or COL_LABEL end)
		pcall(function() t.fontSize = size or 14 end)
		if align ~= nil then pcall(function() t.align = align end) end
		t.text = text or ""
		panel:AddChild(t)
		return t
	end

	local function button(text, x, y, w, h, fn)
		local btn = b:MakeFlatButton(text, w, h)
		if btn ~= nil then
			panel:AddChild(btn)
			btn:SetXY(x, y)
			pcall(function()
				local tf = btn:GetChildAt(1)
				if tf ~= nil then tf.fontSize = 13 end
			end)
			if fn ~= nil then addClick(btn, fn) end
		end
		return btn
	end

	self.status = label("", 0, 0, gw, nil, COL_WARN, 13)
	self.status:SetSize(gw, 38)

	local function row(y, text)
		label(text, 0, y, 150, nil, COL_LABEL, 14)
		return label("", 150, y, gw - 150, CS.FairyGUI.AlignType.Right, COL_TEXT, 14)
	end
	self.vBase = row(42, "角色当前道行")
	self.vStored = row(66, "剑内存道")
	self.vAddp = row(90, "法宝威力加成")

	label("每 1 点存道 +1% 法宝威力，无上限；加成作用于佩者全部法宝。", 0, 116, gw, nil, COL_DIM, 12)

	self.btnDep = button("存入道行", 0, 144, 100, 28, function() self:SetMode("dep") end)
	self.btnWith = button("取回道行", 108, 144, 100, 28, function() self:SetMode("with") end)

	self.vAmount = label("", 0, 180, gw, CS.FairyGUI.AlignType.Center, COL_TEXT, 14)

	local function addRow(y, specs)
		local x = 0
		for i = 1, #specs do
			local s = specs[i]
			button(s[1], x, y, 96, 26, function() self:AddAmount(s[2]) end)
			x = x + 104
		end
	end
	addRow(204, { { "−1000", -1000 }, { "−100", -100 }, { "−10", -10 } })
	addRow(230, { { "+10", 10 }, { "+100", 100 }, { "+1000", 1000 } })

	button("−1", 0, 256, 76, 26, function() self:AddAmount(-1) end)
	button("+1", 82, 256, 76, 26, function() self:AddAmount(1) end)
	button("一半", 164, 256, 76, 26, function() self:SetHalf() end)
	button("全部", 246, 256, 76, 26, function() self:SetAll() end)
	button("清零", 328, 256, 76, 26, function() self:ClearAmount() end)

	self.pLine1 = label("", 0, 290, gw, nil, COL_LABEL, 13)
	self.pLine2 = label("", 0, 312, gw, nil, COL_LABEL, 13)
	label("存入超过当前道行一半时会要求二次确认；存道随时可取回。", 0, 336, gw, nil, COL_DIM, 12)

	local by = math.max(0, gh - 34)
	button("确定", math.floor(gw / 2) - 104, by, 96, 28, function() self:Confirm() end)
	button("关闭", math.floor(gw / 2) + 8, by, 96, 28, function() self:Close() end)
	return true
end

------------------------------------------------------------
-- 数值
------------------------------------------------------------
function C:SetMode(m)
	if m ~= "dep" and m ~= "with" then return end
	if m == "dep" then
		local mod = modRef()
		if mod == nil or self.npc == nil or not mod:LingDaoActive(self.npc) then
			say("需佩带并认主灵道剑，才能存入道行。", "灵道剑")
			return
		end
	end
	self.mode = m
	self.amount = 0
	self.needConfirm = false
	self:Render(true)
end

function C:AddAmount(delta)
	local maxN = self.maxN or 0
	local n = math.floor((tonumber(self.amount) or 0) + (tonumber(delta) or 0))
	if n < 0 then n = 0 end
	if n > maxN then n = maxN end
	self.amount = n
	self.needConfirm = false
	self:Render(true)
end

function C:SetHalf()
	self.amount = math.floor((self.maxN or 0) / 2)
	self.needConfirm = false
	self:Render(true)
end

function C:SetAll()
	self.amount = self.maxN or 0
	self.needConfirm = false
	self:Render(true)
end

function C:ClearAmount()
	self.amount = 0
	self.needConfirm = false
	self:Render(true)
end

function C:Render(force)
	if self.panel == nil then return end
	local mod = modRef()
	local npc = self.npc
	local base, stored, addp = 0, 0, 0
	local yan, equipped, active = false, false, false
	if mod ~= nil and npc ~= nil then
		stored = mod:LingDaoStored(npc)
		yan = isYanNpc(npc)
		local okP, p = pcall(function() return WFG.npc:Practice(npc) end)
		if okP and p ~= nil then
			local ok, v = pcall(function() return tonumber(p.DaoHang) end)
			if ok and v ~= nil then base = math.max(0, math.floor(v)) end
		end
		local okE, eq = pcall(function() return mod:HasLingDaoEquipped(npc) end)
		equipped = okE and eq or false
		active = yan and equipped
		addp = mod:LingDaoAddp(stored)
	end
	self.base, self.stored = base, stored

	local stat, color = "未选择角色。", COL_WARN
	if npc ~= nil then
		if not yan then
			if stored > 0 then
				stat, color = "已转修他法：法宝加成失效，但仍可取回存道。", COL_WARN
			else
				stat, color = "该角色未修炼衍天诀，不能使用灵道剑。", COL_WARN
			end
		elseif not equipped then
			if stored > 0 then
				stat, color = "灵道剑不在法宝格：加成失效，仍可取回存道。", COL_WARN
			else
				stat, color = "未佩带灵道剑：请先装入法宝格并完成认主。", COL_WARN
			end
		else
			stat, color = "灵道剑已认主：存道加成生效中。", COL_OK
		end
	end
	pcall(function()
		self.status.text = stat
		self.status.color = color
	end)

	self.vBase.text = tostring(base)
	self.vStored.text = tostring(stored)
	if active then
		self.vAddp.text = pctText(addp) .. "（生效中）"
		pcall(function() self.vAddp.color = COL_OK end)
	elseif stored > 0 then
		self.vAddp.text = pctText(addp) .. "（未生效）"
		pcall(function() self.vAddp.color = COL_WARN end)
	else
		self.vAddp.text = "0%"
		pcall(function() self.vAddp.color = COL_TEXT end)
	end

	local canDep = active and base > 0
	local canWith = stored > 0
	if self.mode == nil then self.mode = "dep" end
	if self.mode == "dep" and not canDep and canWith then self.mode = "with" end
	if self.mode == "with" and not canWith and canDep then self.mode = "dep" end
	local maxN = (self.mode == "dep") and (canDep and base or 0) or (canWith and stored or 0)
	self.maxN = maxN
	self.amount = math.max(0, math.min(math.floor(tonumber(self.amount) or 0), maxN))

	pcall(function()
		self.btnDep.grayed = not canDep
		self.btnWith.grayed = not canWith
	end)
	self:RefreshAmount()
end

function C:RefreshAmount()
	if self.panel == nil then return end
	local mod = modRef()
	local n = math.floor(tonumber(self.amount) or 0)
	local base, stored = self.base or 0, self.stored or 0
	local label = (self.mode == "dep") and "本次存入" or "本次取回"
	self.vAmount.text = string.format("%s：%d 点", label, n)

	local a0, a1 = 0, 0
	if mod ~= nil then
		if self.mode == "dep" then
			a0 = mod:LingDaoAddp(stored)
			a1 = mod:LingDaoAddp(stored + n)
		else
			a0 = mod:LingDaoAddp(stored)
			a1 = mod:LingDaoAddp(math.max(0, stored - n))
		end
	end
	if self.mode == "dep" then
		self.pLine1.text = string.format("存入后：角色道行 %d → %d    剑内存道 %d → %d", base, base - n, stored, stored + n)
	else
		self.pLine1.text = string.format("取回后：角色道行 %d → %d    剑内存道 %d → %d", base, base + n, stored, stored - n)
	end
	self.pLine2.text = string.format("法宝威力加成：%s → %s", pctText(a0), pctText(a1))
	pcall(function() self.pLine2.color = (n > 0) and COL_TEXT or COL_DIM end)
end

function C:Confirm()
	local mod = modRef()
	local npc = self.npc
	if mod == nil or npc == nil then return end
	local n = math.floor(tonumber(self.amount) or 0)
	if n <= 0 then
		say("请先选择数量。", "灵道剑")
		return
	end
	if self.mode == "dep" and (self.base or 0) > 0 and n * 2 > self.base and not self.needConfirm then
		self.needConfirm = true
		say(string.format("将存入 %d 点道行（当前 %d 点）：存入后这些道行被剑占住，不能再用于修行。再点一次「确定」继续。", n, self.base), "灵道剑")
		return
	end
	self.needConfirm = false
	local method = (self.mode == "dep") and "DepositLingDao" or "WithdrawLingDao"
	local ok, moved, err = pcall(function() return mod[method](mod, npc, n) end)
	if not ok then
		WFG:Error("ui.lingdao", tostring(moved))
		say("操作失败，详见日志。", "灵道剑")
		return
	end
	if (tonumber(moved) or 0) <= 0 then
		say(err or "操作失败。", "灵道剑")
		self.amount = 0
		self:Render(true)
		return
	end
	local verb = (self.mode == "dep") and "存入" or "取回"
	say(string.format("已%s %d 点道行。", verb, moved), "灵道剑")
	self.amount = 0
	self:Render(true)
end

------------------------------------------------------------
-- 打开 / 关闭
------------------------------------------------------------
function C:Show()
	local mod = modRef()
	local npc = self.npc
	if mod == nil then
		say("衍天诀模块未加载。", "灵道剑")
		return
	end
	if npc == nil then
		say("请从角色指令栏的「灵道剑」打开。", "灵道剑")
		return
	end
	WFG:Log("[ui:lingdao] Show 开始：角色=%s，面板=%s", tostring(npc), tostring(self.panel ~= nil))
	local okStored, stored = pcall(function() return mod:LingDaoStored(npc) end)
	stored = okStored and (tonumber(stored) or 0) or 0
	if (not isYanNpc(npc)) and stored <= 0 then
		if browser ~= nil then browser:Close() end
		say("该角色未修炼衍天诀，不能打开灵道剑。", "灵道剑")
		return
	end
	local ok, err = pcall(function()
		if not self:EnsurePanel() then error("建面板失败") end
		local b = shell()
		if b == nil then error("窗口壳未就绪") end
		b:SetTitle("灵道剑")
		self.amount = 0
		self.needConfirm = false
		self:Render(true)
		b:Show()
		WFG:Log("[ui:lingdao] Show 完成")
	end)
	if not ok then
		WFG:Error("ui.lingdao.show", tostring(err))
		say("界面打开失败：" .. tostring(err), "灵道剑")
	end
end

function C:OpenNpc(npc)
	self.npc = npc
	self:Show()
end

function C:Open(bind)
	self.npc = bind
	self:Show()
end

function C:Refresh()
	self:Render(true)
end

function C:Close()
	if browser ~= nil then browser:Close() end
end

return C

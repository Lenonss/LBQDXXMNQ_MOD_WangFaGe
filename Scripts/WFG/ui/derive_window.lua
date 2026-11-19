--[[
    万法阁 · 衍天解析确认窗
    施放「衍天·解析」后立刻弹出本窗，展示物品信息与灵气消耗：
      - 灵气不足 / 等阶不足：只显示「关闭」
      - 条件满足：显示「开始解析」
    确认后才真正扣灵气并入素材库。

    排版：整段正文居中（<p align='center'>），底部按钮左右对称居中。
    配色：窗底是米色卷轴，正文一律用深色墨字，避免浅金在米色上糊成一片。
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("WFG_Derive")

-- 米色底上可读的配色（深墨 → 琥珀 → 墨绿 / 绛红）
local C_TITLE = "#6B4A16"   -- 标题：深琥珀
local C_LABEL = "#6A5233"   -- 字段名：中褐
local C_VALUE = "#221A10"   -- 正文值：近黑
local C_ACCENT= "#8A5A0F"   -- 强调（消耗）
local C_OK    = "#1D6B3A"   -- 通过
local C_WARN  = "#8F2B1B"   -- 不足/失败
local C_DIM   = "#7A6A55"   -- 次要说明

local WIN_W = 560
local WIN_H = 400

local W = WFG.ui.derive or {}
WFG.ui.derive = W

local function col(color, text)
	return string.format("[color=%s]%s[/color]", color, text)
end

-- 居中一行：名称用浅褐、数值用近黑
local function row(label, value)
	return string.format("%s：%s<br/>", col(C_LABEL, label), col(C_VALUE, tostring(value)))
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(text, title or "衍天") end)
	WFG:Log("[解析窗] %s", tostring(text))
end

------------------------------------------------------------------------
-- 渲染
------------------------------------------------------------------------
function W:Render()
	local npc = self.npc
	local thing = self.thing
	if npc == nil or thing == nil then
		tbWindow:SetHtml(self:Center(col(C_WARN, "目标已丢失。")))
		self:SetParseVisible(false)
		return
	end

	local mod = WFG:GetModule("yantian")
	local q = nil
	if mod ~= nil then
		local ok, res = pcall(function() return WFG.YanTian.derive:Quote(mod, npc, thing) end)
		if ok and type(res) == "table" then q = res end
	end
	if q == nil then
		tbWindow:SetHtml(self:Center(col(C_WARN, "无法读取该物品信息。")))
		self:SetParseVisible(false)
		return
	end

	self.quote = q
	local out = {}
	out[#out + 1] = col(C_TITLE, "【衍天 · 解析】") .. "<br/>"
	out[#out + 1] = col(C_DIM, "— — — — — — — — — —") .. "<br/>"
	out[#out + 1] = row("物品", q.name or WFG.item:Show(q.defName or ""))
	out[#out + 1] = row("等阶", tostring(q.lv) .. " 阶")
	out[#out + 1] = row("品级", tostring(q.q) .. " 品")
	out[#out + 1] = row("可解析上限", tostring(q.maxLv) .. " 阶（随境界提升）")
	out[#out + 1] = row("已收录", q.already and col(C_OK, "是") or col(C_DIM, "否"))
	out[#out + 1] = "<br/>"
	out[#out + 1] = row("解析消耗", col(C_ACCENT, tostring(q.cost) .. " 灵气"))
	out[#out + 1] = row("当前灵气", tostring(math.floor(q.ling)) .. " / " .. tostring(math.floor(q.maxLing)))
	out[#out + 1] = "<br/>"

	if not q.ok then
		out[#out + 1] = col(C_WARN, q.reason or "无法解析")
	elseif q.already and q.cost <= 0 then
		out[#out + 1] = col(C_OK, "已收录且品级不低于当前，无需消耗。")
	elseif q.enough then
		out[#out + 1] = col(C_OK, "灵气充足，可以开始解析。")
	else
		out[#out + 1] = col(C_WARN, string.format("灵气不足，还差 %d。", math.floor(q.cost - q.ling)))
	end

	tbWindow:SetHtml(self:Center(table.concat(out)))
	self:SetParseVisible(q.ok == true and q.enough == true)
end

function W:Center(body)
	return string.format("<p align='center'>%s</p>", body)
end

function W:SetParseVisible(show)
	local pane = nil
	pcall(function() pane = tbWindow.window.contentPane end)
	if pane == nil then return end
	local ok, child = pcall(function() return pane:GetChild("WFG_DParse") end)
	if ok and child ~= nil then
		local ok2 = pcall(function() child.visible = show end)
		if not ok2 and show == false then
			pcall(function() child:SetVisible(false) end)
		elseif not ok2 and show == true then
			pcall(function() child:SetVisible(true) end)
		end
	end
end

------------------------------------------------------------------------
-- 居中与暂停：确认窗弹出时冻结世界，避免角色在玩家决策期间乱跑
------------------------------------------------------------------------
local function mainMgr()
	local mm = nil
	pcall(function() mm = CS.XiaWorld.MainManager.Instance end)
	return mm
end

function W:Freeze()
	local mm = mainMgr()
	if mm == nil then return end
	local running = nil
	pcall(function() running = mm.Runing end)
	if running == true then
		pcall(function() self.speed = mm.gamespeed end)
		pcall(function() mm:Pause() end)
		self.paused = true
	end
end

function W:Unfreeze()
	if not self.paused then return end
	self.paused = false
	local mm = mainMgr()
	if mm == nil then return end
	local sp = self.speed
	if type(sp) == "number" and sp > 0 then
		pcall(function() mm:Play(sp) end)
	else
		pcall(function() mm:Play() end)
	end
end

function W:CenterWindow()
	pcall(function() tbWindow.window:Center() end)
end

------------------------------------------------------------------------
-- 打开 / 执行
------------------------------------------------------------------------
function W:Open(npc, thing)
	self.npc = npc
	self.thing = thing
	self.quote = nil
	tbWindow:SetSize(WIN_W, WIN_H)
	tbWindow:Show()
	self:CenterWindow()
	self:Render()
	self:Freeze()
end

function W:DoParse()
	local q = self.quote
	if q == nil then return end
	if not q.ok then say(q.reason or "无法解析") return end
	if not q.enough then say("灵气不足") return end

	local mod = WFG:GetModule("yantian")
	local ok, res, text = pcall(function()
		return WFG.YanTian.derive:Parse(mod, self.npc, self.thing)
	end)
	if not ok then
		WFG:Error("ui.derive", res)
		say("解析失败（详见日志）")
		return
	end
	say(text or (res and "解析完成" or "解析失败"))
	if res then
		pcall(function() tbWindow:Hide() end)
		if WFG.ui.Refresh ~= nil then pcall(function() WFG.ui:Refresh() end) end
	end
end

function W:Close()
	pcall(function() tbWindow:Hide() end)
end

------------------------------------------------------------------------
-- 窗口事件
------------------------------------------------------------------------
function tbWindow:OnInit()
	self:SetTitle("衍天 · 解析")
	self:SetSize(WIN_W, WIN_H)
	-- 两个按钮各约 96 宽，整体居中：160 + 96 + 48 间距 = 304
	self:AddButton("WFG_DParse", "开始解析", 168, WIN_H - 74)
	self:AddButton("WFG_DClose", "关闭", 312, WIN_H - 74)
	WFG.ui.deriveWindow = self
end

function tbWindow:OnShown()
	local w = WFG.ui.derive
	if w ~= nil then
		w:CenterWindow()
		w:Render()
		w:Freeze()
	end
end

function tbWindow:OnHide()
	local w = WFG.ui.derive
	if w ~= nil then w:Unfreeze() end
end

function tbWindow:OnObjectEvent(eventType, obj, context)
	if eventType ~= "onClick" or obj == nil then return end
	local n = obj.name
	local w = WFG.ui.derive
	if w == nil then return end
	if n == "WFG_DParse" then
		w:DoParse()
	elseif n == "WFG_DClose" then
		w:Close()
	end
end

return W

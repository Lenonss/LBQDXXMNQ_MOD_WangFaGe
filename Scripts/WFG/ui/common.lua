--[[
    万法阁 · UI 公共件
    - 统一暂停/恢复（引用计数，多个窗口叠加时不会提前解冻）
    - UBB 着色与消息提示的小工具
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local U = WFG.ui

U.pauseDepth = U.pauseDepth or 0
U.pausedSpeed = U.pausedSpeed
U.pausedByUs = U.pausedByUs or false

local function mainMgr()
	local mm = nil
	pcall(function() mm = CS.XiaWorld.MainManager.Instance end)
	return mm
end

-- 打开窗口时冻结世界：引擎只在模态窗口上拦输入，时间照走，所以手动暂停
function U:Pause()
	local mm = mainMgr()
	if mm == nil then return end
	self.pauseDepth = (self.pauseDepth or 0) + 1
	if self.pauseDepth > 1 then return end

	local running = nil
	pcall(function() running = mm.Runing end)
	if running == true then
		local sp = nil
		pcall(function() sp = mm.gamespeed end)
		self.pausedSpeed = sp
		self.pausedByUs = true
		pcall(function() mm:Pause() end)
	end
end

function U:Resume()
	self.pauseDepth = math.max(0, (self.pauseDepth or 0) - 1)
	if self.pauseDepth > 0 then return end

	local mm = mainMgr()
	if mm == nil then return end
	-- 只在「是我们暂停的」情况下恢复；玩家自己暂停的保持暂停
	local sp = self.pausedSpeed
	self.pausedSpeed = nil
	if not self.pausedByUs then return end
	self.pausedByUs = false
	if type(sp) == "number" and sp > 0 then
		pcall(function() mm:Play(sp) end)
	else
		pcall(function() mm:Play() end)
	end
end

-- 强制恢复（取消选点等异常路径用）
function U:ResumeAll()
	self.pauseDepth = 0
	self:Resume()
	self.pauseDepth = 0
end

function U:Col(color, text)
	return string.format("[color=%s]%s[/color]", color, tostring(text))
end

function U:Say(text, title)
	pcall(function() world:ShowMsgBox(tostring(text), title or "万法阁") end)
	WFG:Log("[ui] %s", tostring(text))
end

function U:Center(body)
	return string.format("<p align='center'>%s</p>", body)
end

------------------------------------------------------------------------
-- 窗口正文框定位
-- Wnd_Simple 的内容 = UI_WindowEmpty（GLabel）：子对象 0 = 边框 m_frame，
-- 子对象 1 = m_html（GRichTextField，占满内容区）。拿到它并改 y/height，
-- 就能把「正文」与「按钮」分到不同条带，避免叠字。
------------------------------------------------------------------------
function U:HtmlField(win)
	local f = nil
	pcall(function()
		local pane = win.window.contentPane
		f = pane:GetChildAt(1)
	end)
	return f
end

function U:FitHtml(win, y, h)
	local f = self:HtmlField(win)
	if f == nil then
		if not self.htmlDiag then
			self.htmlDiag = true
			WFG:Log("[ui] 未取到正文框（GetChildAt(1) 为空），按默认排布继续")
		end
		return false
	end
	local ok = pcall(function()
		f.y = y
		f.height = h
	end)
	if ok and not self.htmlOk then
		self.htmlOk = true
		WFG:Log("[ui] 正文框定位成功：y=%s h=%s", tostring(y), tostring(h))
	end
	return ok
end

return U

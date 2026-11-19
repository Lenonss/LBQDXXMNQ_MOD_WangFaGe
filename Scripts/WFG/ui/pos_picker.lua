--[[
    万法阁 · 衍天创造选点
    确认创造后进入本模块：
      1. 每帧读取鼠标所在格（UI_WorldLayer.Instance.MouseGridKey，ui_worldlayer.cs:64）
      2. 左键点地 → 弹出「是否在此生成」
      3. 生成 / 取消（取消后继续选点）
      4. 右键或 ESC 退出选点
    必须逐帧采样：GetMouseButtonDown 只在按下那一帧为真，定时器会漏。
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("WFG_PosConfirm")

local C_TITLE = "#6B4A16"
local C_LABEL = "#6A5233"
local C_VALUE = "#221A10"
local C_ACCENT= "#8A5A0F"
local C_OK    = "#1D6B3A"
local C_WARN  = "#8F2B1B"
local C_DIM   = "#7A6A55"

local WIN_W, WIN_H = 480, 320

local P = WFG.ui.pos or {}
WFG.ui.pos = P

local function col(color, text)
	return string.format("[color=%s]%s[/color]", color, tostring(text))
end

local function say(text, title)
	pcall(function() world:ShowMsgBox(tostring(text), title or "衍天·创造") end)
	WFG:Log("[选点] %s", tostring(text))
end

-- 引擎取值（全部 pcall，取不到就当不存在）
local function worldLayer()
	local inst = nil
	pcall(function() inst = CS.UI_WorldLayer.Instance end)
	return inst
end

local function mouseGrid()
	local inst = worldLayer()
	if inst == nil then return nil end
	local k = nil
	pcall(function() k = inst.MouseGridKey end)
	if type(k) == "number" and k > 0 then return k end
	return nil
end

local function overUI()
	local v = false
	pcall(function() v = CS.FairyGUI.Stage.isTouchOnUI end)
	return v == true
end

local function leftDown()
	local v = false
	pcall(function() v = CS.UnityEngine.Input.GetMouseButtonDown(0) end)
	return v == true
end

local function rightDown()
	local v = false
	pcall(function() v = CS.UnityEngine.Input.GetMouseButtonDown(1) end)
	return v == true
end

local function escDown()
	local v = false
	pcall(function() v = CS.UnityEngine.Input.GetKeyDown(CS.UnityEngine.KeyCode.Escape) end)
	return v == true
end

local function keyXY(key)
	local x, y = 0, 0
	pcall(function()
		local xy = GridMgr:Key2P(key)
		if type(xy) == "table" then x, y = xy[0] or xy[1], xy[1] or xy[2] end
	end)
	if x == 0 and y == 0 then
		pcall(function()
			local arr = CS.XiaWorld.GridMgr.Inst:Key2P(key)
			if arr ~= nil and arr.Length >= 2 then x, y = arr[0], arr[1] end
		end)
	end
	return math.floor(x or 0), math.floor(y or 0)
end

-- 目标地块是否已被占用（物品 / 建筑 / 植物都算）
function P:Occupied(key)
	if type(key) ~= "number" or key <= 0 then return false end
	local n = 0
	pcall(function()
		local list = World.map.Things:GetThingsAtGrid(key)
		if list ~= nil then n = list.Count end
	end)
	return n > 0
end

------------------------------------------------------------------------
-- 状态
------------------------------------------------------------------------
-- 游戏内 Lua 沙箱没有 os 库，计时一律用 realtimeSinceStartup
local function nowSec()
	local t = nil
	pcall(function() t = CS.UnityEngine.Time.realtimeSinceStartup end)
	if type(t) ~= "number" then return 0 end
	return t
end

-- 地图选点光标：GRoot 上挂一个自绘方框，每帧跟随鼠标所在世界坐标
function P:CursorInit()
	self.cursor = nil
	local ok, gg = pcall(function()
		local gr = CS.FairyGUI.GRoot.inst
		if gr == nil then return nil end
		local g = CS.FairyGUI.GGraph()
		g:DrawRect(48, 48, 2,
			CS.UnityEngine.Color(0.55, 0.85, 0.35, 1),
			CS.UnityEngine.Color(0.35, 0.75, 0.25, 0.35))
		pcall(function() g.touchable = false end)
		gr:AddChild(g)
		pcall(function() g.sortingOrder = 30000 end)
		pcall(function() g.visible = false end)
		return g
	end)
	if ok and gg ~= nil then
		self.cursor = gg
		WFG:Log("[pos] 光标已创建")
	else
		WFG:Log("[pos] 光标创建失败（GRoot 不可用）")
	end
end

function P:CursorStep()
	local gg = self.cursor
	if gg == nil then return end
	pcall(function()
		local layer = UI_WorldLayer.Instance
		if layer == nil then return end
		local key = layer.MouseGridKey
		local pos = layer.MousePostion
		local cam = CS.UnityEngine.Camera.main
		if pos == nil or cam == nil or key == nil or key <= 0 then
			pcall(function() gg.visible = false end)
			return
		end
		local sp = cam:WorldToScreenPoint(pos)
		local v2 = CS.UnityEngine.Vector2(sp.x, CS.UnityEngine.Screen.height - sp.y)
		local local2 = nil
		local okLocal = pcall(function() local2 = CS.FairyGUI.GRoot.inst:GlobalToLocal(v2) end)
		pcall(function() gg.visible = true end)
		if okLocal and local2 ~= nil then
			pcall(function() gg:SetXY(math.floor(local2.x - 24), math.floor(local2.y - 24)) end)
		else
			pcall(function() gg:SetXY(math.floor(sp.x - 24), math.floor(CS.UnityEngine.Screen.height - sp.y - 24)) end)
		end
		if not self.cursorLogged then
			self.cursorLogged = true
			WFG:Log("[pos] 光标定位 sp=(%.0f,%.0f) local=(%s,%s) key=%s",
				sp.x, sp.y,
				tostring(local2 and local2.x or -1), tostring(local2 and local2.y or -1),
				tostring(key))
		end
		local busy = self:Occupied(key)
		if busy ~= self.cursorBusy then
			self.cursorBusy = busy
			pcall(function()
				if busy then
					gg:DrawRect(48, 48, 3,
						CS.UnityEngine.Color(0.88, 0.25, 0.18, 1),
						CS.UnityEngine.Color(0.88, 0.25, 0.18, 0.35))
				else
					gg:DrawRect(48, 48, 3,
						CS.UnityEngine.Color(0.48, 0.82, 0.32, 1),
						CS.UnityEngine.Color(0.36, 0.75, 0.26, 0.30))
				end
			end)
		end
	end)
end

function P:CursorFree()
	local gg = self.cursor
	self.cursor = nil
	if gg == nil then return end
	pcall(function() gg:Dispose() end)
end

function P:Start(npc, entry, count, stuff, quality, store)
	self.npc = npc
	self.entry = entry
	self.count = math.max(1, math.floor(count or 1))
	self.stuff = stuff
	self.quality = quality
	self.store = math.max(0, math.floor(store or 0))
	self.gridKey = nil
	self.confirming = false
	self.active = true
	self.bornAt = nowSec()
	self:CursorInit()
	say(string.format("请在地图上左键选择落点：%s ×%d（右键或 ESC 取消）",
		entry and (entry.name or entry.defName) or "", self.count))
end

function P:Stop(reason)
	self.active = false
	self.confirming = false
	self.entry = nil
	self.pendingKey = nil
	self:CursorFree()
	if self.closeConfirm ~= nil then pcall(self.closeConfirm) end
	WFG.ui:ResumeAll()
	if reason ~= nil then say(reason) end
end

function P:Cancel()
	self:Stop("已取消创造")
end

------------------------------------------------------------------------
-- 每帧
------------------------------------------------------------------------
function P:Step(dt)
	if not self.active then return end
	if self.confirming then return end

	self:CursorStep()

	-- UI_WorldLayer 尚未就绪时最多等 3 秒
	if worldLayer() == nil then
		if nowSec() - (self.bornAt or 0) > 3 then
			self:Stop("世界层未就绪，已退出选点")
		end
		return
	end

	if escDown() or rightDown() then
		self:Cancel()
		return
	end

	local k = mouseGrid()
	if k == nil then return end
	self.hoverKey = k

	if leftDown() and not overUI() then
		if self:Occupied(k) then
			say("该地块已有物品/建筑，无法在此创造，请换个位置。")
		else
			self:AskConfirm(k)
		end
	end
end

function P:AskConfirm(key)
	if self:Occupied(key) then
		say("该地块已有物品/建筑，无法在此创造，请换个位置。")
		return
	end
	self.pendingKey = key
	self.confirming = true
	local x, y = keyXY(key)
	self.pendingXY = { x = x, y = y }
	tbWindow:SetSize(WIN_W, WIN_H)
	tbWindow:Show()
	pcall(function() tbWindow.window:Center() end)
	WFG.ui:Pause()
	self:Render()
end

function P:Render()
	local e = self.entry
	local key = self.pendingKey
	if e == nil or key == nil then
		tbWindow:SetHtml(WFG.ui:Center(col(C_WARN, "目标已丢失。")))
		return
	end

	local mod = WFG:GetModule("yantian")
	local ok, q = pcall(function()
		return WFG.YanTian.derive:QuoteCreate(mod, self.npc, e.defName, self.count,
			self.stuff, self.quality, self.store)
	end)

	local xy = self.pendingXY or { x = 0, y = 0 }
	local out = {}
	out[#out + 1] = col(C_TITLE, "【衍天 · 造物落点】") .. "<br/>"
	out[#out + 1] = col(C_DIM, "— — — — — — — — — —") .. "<br/>"
	out[#out + 1] = string.format("%s：%s<br/>", col(C_LABEL, "素材"), col(C_VALUE, e.name or e.defName))
	out[#out + 1] = string.format("%s：%s<br/>", col(C_LABEL, "数量"), col(C_ACCENT, tostring(self.count) .. " 件"))
	if ok and type(q) == "table" and q.ok == true then
		out[#out + 1] = string.format("%s：%s　%s：%s<br/>",
			col(C_LABEL, "材料"), col(C_VALUE, tostring(q.stuffName or "随机")),
			col(C_LABEL, "品级"), col(C_VALUE, tostring(q.q or 1) .. " 品"))
		out[#out + 1] = string.format("%s：%s<br/>",
			col(C_LABEL, "储灵"), col(C_VALUE, tostring(q.store or 0)))
	end
	out[#out + 1] = string.format("%s：%s<br/>", col(C_LABEL, "坐标"),
		col(C_VALUE, string.format("(%d, %d)", xy.x or 0, xy.y or 0)))

	if ok and type(q) == "table" then
		out[#out + 1] = string.format("%s：%s<br/>", col(C_LABEL, "灵气消耗"), col(C_ACCENT, tostring(q.cost or 0)))
		out[#out + 1] = "<br/>"
		if q.ok ~= true then
			out[#out + 1] = col(C_WARN, q.reason or "无法创造")
		elseif q.enough then
			out[#out + 1] = col(C_OK, "是否在此生成？")
		else
			out[#out + 1] = col(C_WARN, string.format("灵气不足，还差 %d", math.floor((q.cost or 0) - (q.ling or 0))))
		end
	else
		out[#out + 1] = "<br/>" .. col(C_WARN, "无法读取消耗信息")
	end

	tbWindow:SetHtml(WFG.ui:Center(table.concat(out)))
end

function P:DoCreate()
	local e = self.entry
	local key = self.pendingKey
	if e == nil or key == nil then self:Stop() return end

	local mod = WFG:GetModule("yantian")
	local ok, res, text = pcall(function()
		return WFG.YanTian.derive:Create(mod, self.npc, e.defName, self.count, key,
			self.stuff, self.quality, self.store)
	end)
	if not ok then
		WFG:Error("ui.pos", res)
		say("创造失败（详见日志）")
		return
	end
	if res then
		say(text or "创造完成")
		self:Stop()
	else
		say(text or "创造失败")
		-- 失败留在选点，允许换个位置再试
		self.confirming = false
		pcall(function() tbWindow:Hide() end)
		WFG.ui:Resume()
	end
end

function P:CloseConfirm()
	self.confirming = false
	pcall(function() tbWindow:Hide() end)
	WFG.ui:Resume()
end

------------------------------------------------------------------------
-- 窗口
------------------------------------------------------------------------
function tbWindow:OnInit()
	self:SetTitle("衍天 · 造物落点")
	self:SetSize(WIN_W, WIN_H)
	self:AddButton("WFG_PDo", "生成", 150, WIN_H - 74)
	self:AddButton("WFG_PCancel", "取消", 300, WIN_H - 74)
	WFG.ui.posWindow = self
end

function tbWindow:OnShown()
	local p = WFG.ui.pos
	if p ~= nil then
		pcall(function() tbWindow.window:Center() end)
		p:Render()
		WFG.ui:Pause()
	end
end

function tbWindow:OnHide()
	WFG.ui:Resume()
end

function tbWindow:OnObjectEvent(eventType, obj, context)
	if eventType ~= "onClick" or obj == nil then return end
	local p = WFG.ui.pos
	if p == nil then return end
	if obj.name == "WFG_PDo" then
		p:DoCreate()
	elseif obj.name == "WFG_PCancel" then
		p:CloseConfirm()
	end
end

------------------------------------------------------------------------
-- 注册逐帧回调
------------------------------------------------------------------------
if WFG.OnStep ~= nil then
	WFG:OnStep(function(dt)
		local ok, err = pcall(P.Step, P, dt)
		if not ok then WFG:Error("pos.step", err) end
	end)
else
	WFG.pendingStep = WFG.pendingStep or {}
	table.insert(WFG.pendingStep, P)
end

return P

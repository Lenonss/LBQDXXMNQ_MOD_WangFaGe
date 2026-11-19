--[[
    万法阁 · UI 工具（kit）
    直接用 FairyGUI 原语在 Lua 里手搭界面，不依赖 .fui 资源包。

    为什么可行（反编译 Assembly-CSharp-firstpass.dll 的 FairyGUI 部分确认）：
        GComponent / GTextField / GGraph / GLoader / GList / GButton / GSlider
        都有 public 无参构造函数；GObject 暴露 onClick / onRollOver / onRollOut /
        onTouchBegin / onRightClick / tooltips / touchable / opaque；
        GComponent 有 AddChild / GetChildAt / GetChild / RemoveChildren。

    用法：
        local kit = WFG.ui.kit
        local root = kit.Panel(600, 400)          -- 带底板的 GComponent
        root:AddChild(kit.Label("标题", 18, "#6B4A16", 20, 16))
        local b = kit.Button("确定", 200, 90, 120, 32)
        b.onClick:Add(function(ctx) ... end)
        window:AddObj(root, 0, 0)
]]

WFG = WFG or {}
WFG.ui = WFG.ui or {}

local K = {}
WFG.ui.kit = K

local FG = CS.FairyGUI

------------------------------------------------------------------------
-- 事件挂载（两种写法都试，失败要留痕，不能静默吞掉）
------------------------------------------------------------------------
function K.Attach(obj, evt, fn)
	if obj == nil or fn == nil then return false end
	local raw = fn
	fn = function(ctx)
		if WFG and WFG.Log then
			WFG:Log("[kit] click " .. tostring(obj.name))
		end
		return raw(ctx)
	end
	local ok, err = pcall(function()
		local l = obj[evt]
		if l ~= nil and l.Add ~= nil then
			l:Add(fn)
			return
		end
		error("no listener " .. tostring(evt))
	end)
	if ok then return true end
	local ok2 = pcall(function() obj:AddEventListener(evt, fn) end)
	if not ok2 and WFG and WFG.Log then
		WFG:Log(string.format("[kit] 事件挂载失败 %s.%s：%s",
			tostring(obj.name), tostring(evt), tostring(err)))
	end
	return ok2
end

------------------------------------------------------------------------
-- 颜色
------------------------------------------------------------------------
function K.Color(hex, alpha)
	hex = tostring(hex or "#000000")
	hex = hex:gsub("^#", "")
	local r = tonumber(hex:sub(1, 2), 16) or 0
	local g = tonumber(hex:sub(3, 4), 16) or 0
	local b = tonumber(hex:sub(5, 6), 16) or 0
	local a = alpha or 1
	return CS.UnityEngine.Color(r / 255, g / 255, b / 255, a)
end

------------------------------------------------------------------------
-- 底板 / 方块
------------------------------------------------------------------------
function K.Rect(w, h, fillHex, lineHex, lineSize, alpha)
	local g = FG.GGraph()
	local ok = pcall(function()
		g:DrawRect(w, h, lineSize or 1, K.Color(lineHex or "#8A6A3A"), K.Color(fillHex or "#F3E6C8", alpha))
	end)
	if not ok then
		pcall(function() g:DrawRect(w, h) end)
	end
	pcall(function() g.touchable = false end)
	return g
end

function K.Panel(w, h, fillHex, lineHex)
	local root = FG.GComponent()
	root:SetSize(w, h, true)
	local bg = K.Rect(w, h, fillHex or "#F3E6C8", lineHex or "#8A6A3A", 2)
	bg.name = "bg"
	root:AddChild(bg)
	pcall(function() root.opaque = true end)
	return root
end

------------------------------------------------------------------------
-- 文本
------------------------------------------------------------------------
function K.Label(text, size, hex, x, y, w)
	local t = FG.GTextField()
	pcall(function() t.text = tostring(text or "") end)
	pcall(function() t.fontSize = size or 14 end)
	pcall(function() t.color = K.Color(hex or "#221A10") end)
	pcall(function() t.autoSize = 2 end)          -- 2 = Both，按内容撑开
	pcall(function() t.singleLine = true end)
	pcall(function() t.touchable = false end)
	pcall(function() t.SetXY(x or 0, y or 0) end)
	if w ~= nil then
		pcall(function()
			t.autoSize = 0
			t.width = w
		end)
	end
	return t
end

-- 居中文案（整块铺满，用于标题）
function K.LabelCenter(text, size, hex, x, y, w, h)
	local t = K.Label(text, size, hex, x, y, w)
	pcall(function()
		t.height = h or 24
		t.autoSize = 0
		t.align = 2                             -- 2 = Center
		t.verticalAlign = 1                     -- 1 = Middle
	end)
	return t
end

------------------------------------------------------------------------
-- 按钮（自绘：底板 + 文字 + 悬停高亮）
------------------------------------------------------------------------
function K.Button(text, x, y, w, h, onClick, opts)
	opts = opts or {}
	local b = FG.GComponent()
	b:SetSize(w, h, true)
	pcall(function() b.opaque = true end)
	pcall(function() b.touchable = true end)

	local normal = opts.fill or "#E8DCC0"
	local bg = K.Rect(w, h, normal, opts.line or "#8A6A3A", 2)
	bg.name = "bg"
	b:AddChild(bg)

	local lbl = K.LabelCenter(text, opts.size or 14, opts.color or "#221A10", 0, 0, w, h)
	lbl.name = "label"
	b:AddChild(lbl)

	local function paint(hex)
		pcall(function()
			bg:DrawRect(w, h, 2, K.Color(opts.line or "#8A6A3A"), K.Color(hex))
		end)
	end
	pcall(function()
		b.onRollOver:Add(function() paint(opts.hover or "#F7EDD8") end)
		b.onRollOut:Add(function() paint(normal) end)
	end)
	if onClick ~= nil then
		K.Attach(b, "onClick", onClick)
	end
	pcall(function() b.SetXY(x, y) end)
	b.title = text
	b.name = opts.name or ("btn_" .. tostring(text))
	return b
end

------------------------------------------------------------------------
-- 勾选项（■ / □ + 文字，点击切换）
------------------------------------------------------------------------
function K.Check(text, x, y, checked, onChange)
	local c = FG.GComponent()
	local w, h = 96, 26
	c:SetSize(w, h, true)
	pcall(function() c.opaque = true end)
	pcall(function() c.touchable = true end)

	local lbl = K.Label((checked and "■ " or "□ ") .. text, 14, checked and "#1D6B3A" or "#221A10", 4, 4)
	lbl.name = "label"
	c:AddChild(lbl)

	local state = checked and true or false
	K.Attach(c, "onClick", function()
			state = not state
			pcall(function()
				lbl.text = (state and "■ " or "□ ") .. text
				lbl.color = K.Color(state and "#1D6B3A" or "#221A10")
			end)
			if onChange ~= nil then onChange(state) end
	end)
	pcall(function() c.SetXY(x, y) end)
	c.name = "check_" .. tostring(text)
	return c, function() return state end
end

------------------------------------------------------------------------
-- 图标 / 贴图
------------------------------------------------------------------------
function K.Icon(url, x, y, w, h)
	local l = FG.GLoader()
	pcall(function() l.url = url end)
	pcall(function() l:SetSize(w or 48, h or 48, true) end)
	pcall(function() l.SetXY(x or 0, y or 0) end)
	pcall(function() l.touchable = false end)
	return l
end

------------------------------------------------------------------------
-- 悬停提示
------------------------------------------------------------------------
function K.Tip(obj, text)
	if obj == nil then return end
	pcall(function() obj.tooltips = tostring(text or "") end)
end

------------------------------------------------------------------------
-- 滑块（自绘：轨道 + 手柄，可点击定位/拖动）
------------------------------------------------------------------------
function K.Slider(x, y, w, minV, maxV, value, onChange)
	local s = FG.GComponent()
	local h = 24
	s:SetSize(w, h, true)
	pcall(function() s.opaque = true end)

	local track = K.Rect(w, 6, "#C9B48A", "#8A6A3A", 1)
	pcall(function() track.SetXY(0, 9) end)
	track.name = "track"
	s:AddChild(track)

	local knob = K.Rect(10, 18, "#8A5A0F", "#5A3A06", 1)
	knob.name = "knob"
	s:AddChild(knob)

	local v = value or minV
	local function paint()
		local p = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
		pcall(function() knob.SetXY(math.floor(p * (w - 10)), 3) end)
	end
	paint()

	local function handle(cx)
		local p = (cx - 5) / math.max(1, w - 10)
		if p < 0 then p = 0 end
		if p > 1 then p = 1 end
		v = math.floor(minV + p * (maxV - minV) + 0.5)
		paint()
		if onChange ~= nil then onChange(v) end
	end

	pcall(function()
		s.onTouchBegin:Add(function(ctx)
			if ctx ~= nil and ctx.inputEvent ~= nil then
				local pt = ctx.inputEvent.x
				if pt ~= nil then handle(pt) end
			end
		end)
	end)
	pcall(function()
		knob.onTouchBegin:Add(function() end)
	end)
	pcall(function() s.SetXY(x, y) end)
	s.name = "slider"
	return s, function() return v end
end

return K

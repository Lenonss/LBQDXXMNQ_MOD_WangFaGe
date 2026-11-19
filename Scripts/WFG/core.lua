--[[
    万法阁 · 框架核心
    职责：模块注册、安全调用与熔断、定时器、通用工具、日志。
    注意：本文件不写任何具体功法的数值与规则；所有功法逻辑放在 Scripts/Gong/<功法>/ 下。
]]

WFG = WFG or {}

local unpack = unpack or table.unpack

WFG.modules    = WFG.modules    or {}   -- id -> module table
WFG.moduleList = WFG.moduleList or {}   -- 有序列表（注册顺序）
WFG.defs       = WFG.defs       or {}   -- 功法定义：gongName -> {moduleId, label}
WFG.store      = WFG.store      or {}   -- 运行时数据（存档时序列化）
WFG.timers     = WFG.timers     or {}   -- 定时器表
WFG.errCount   = WFG.errCount   or {}   -- 模块错误计数（熔断用）
WFG.disabled   = WFG.disabled   or {}   -- 已熔断模块
WFG.hotkeys    = WFG.hotkeys    or {}   -- id -> {module, fn}
WFG.flags      = WFG.flags      or {}
WFG.TAG        = "[WFG]"

------------------------------------------------------------------------
-- 日志
------------------------------------------------------------------------
function WFG:Log(fmt, ...)
	local msg
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, fmt, ...)
		msg = ok and s or tostring(fmt)
	else
		msg = tostring(fmt)
	end
	print(self.TAG .. " " .. msg)
end

function WFG:Error(tag, msg)
	local text = self.TAG .. " [" .. tostring(tag) .. "] " .. tostring(msg)
	LogError(text)
end

------------------------------------------------------------------------
-- 模块注册与调度
------------------------------------------------------------------------
-- spec: { id=, gong=, label=, dataVer=, OnInit=, OnEnter=, OnLeave=, OnStep=,
--         OnSecond=, OnStageChange=, OnSave=, OnLoad=, OnAfterLoad=,
--         OnHotKey=, OnUiCommand= }
function WFG:Register(spec)
	assert(type(spec) == "table" and type(spec.id) == "string", "[WFG] Register 需要 id")
	if self.modules[spec.id] ~= nil then
		self:Log("模块重复注册，已忽略: %s", spec.id)
		return self.modules[spec.id]
	end
	spec.dataVer = spec.dataVer or 1
	self.modules[spec.id] = spec
	table.insert(self.moduleList, spec)
	if type(spec.gong) == "string" and spec.gong ~= "" then
		self.defs[spec.gong] = { moduleId = spec.id, label = spec.label or spec.id }
	end
	return spec
end

function WFG:GetModule(id)
	return self.modules[id]
end

function WFG:ForEachModule(fn)
	for i = 1, #self.moduleList do
		local m = self.moduleList[i]
		if m ~= nil and self.disabled[m.id] ~= true then
			fn(m)
		end
	end
end

-- 调用某个模块的某个钩子；带 pcall 与熔断
function WFG:Call(m, fnName, ...)
	if m == nil or self.disabled[m.id] then return end
	local fn = m[fnName]
	if type(fn) ~= "function" then return end
	local args = { ... }
	local n = select("#", ...)
	local ok, err = pcall(function()
		if n == 0 then return fn(m) end
		return fn(m, unpack(args, 1, n))
	end)
	if not ok then
		local c = (self.errCount[m.id] or 0) + 1
		self.errCount[m.id] = c
		self:Error(m.id .. "." .. fnName, err)
		if c >= 5 then
			self.disabled[m.id] = true
			LogError(self.TAG .. " 模块连续报错，已停用: " .. m.id)
		end
	end
end

------------------------------------------------------------------------
-- 定时器：OnStep 内统一推进，避免各模块自己算时间
------------------------------------------------------------------------
function WFG:Every(interval, key, fn)
	self.timers[key] = { interval = interval, key = key, fn = fn, acc = 0 }
end

function WFG:Cancel(key)
	self.timers[key] = nil
end

function WFG:StepTimers(dt)
	-- 取快照，避免回调里注册/注销导致遍历错乱
	local list = {}
	for _, t in pairs(self.timers) do
		list[#list + 1] = t
	end
	for i = 1, #list do
		local t = list[i]
		if self.timers[t.key] == t then
			t.acc = t.acc + dt
			if t.acc >= t.interval then
				t.acc = 0
				local ok, err = pcall(t.fn, t.acc)
				if not ok then
					self:Error("timer:" .. t.key, err)
					self.timers[t.key] = nil
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- 生命周期（由 boot.lua 调用）
------------------------------------------------------------------------
function WFG:InitAll()
	self:Log("初始化，模块数 %d", #self.moduleList)
	self:ForEachModule(function(m) self:Call(m, "OnInit") end)
end

function WFG:EnterAll()
	self:ForEachModule(function(m) self:Call(m, "OnEnter") end)
end

function WFG:LeaveAll()
	self:ForEachModule(function(m) self:Call(m, "OnLeave") end)
	self.timers = {}
end

function WFG:SecondTick()
	self:ForEachModule(function(m) self:Call(m, "OnSecond") end)
end

function WFG:AfterLoadAll()
	self:ForEachModule(function(m) self:Call(m, "OnAfterLoad") end)
end

function WFG:SaveAll()
	local data = { ver = 1, mods = {} }
	self:ForEachModule(function(m)
		local fn = m.OnSave
		if type(fn) == "function" then
			local ok, res = pcall(fn, m)
			if ok and type(res) == "table" then
				data.mods[m.id] = res
			elseif not ok then
				self:Error(m.id .. ".OnSave", res)
			end
		end
	end)
	return data
end

function WFG:LoadAll(data)
	self.store = {}
	if type(data) ~= "table" then return end
	local mods = data.mods or {}
	self:ForEachModule(function(m)
		local fn = m.OnLoad
		if type(fn) == "function" then
			local ok, err = pcall(fn, m, mods[m.id])
			if not ok then self:Error(m.id .. ".OnLoad", err) end
		end
	end)
	self:Log("读档完成，模块数据 %d 份", (function()
		local n = 0
		for _ in pairs(mods) do n = n + 1 end
		return n
	end)())
end

------------------------------------------------------------------------
-- 热键
------------------------------------------------------------------------
function WFG:AddHotKey(id, m, fn)
	self.hotkeys[id] = { module = m, fn = fn }
end

function WFG:CollectHotKeys()
	local list = {}
	for id, h in pairs(self.hotkeys) do
		list[#list + 1] = { ID = id, Name = "万法阁", Type = "Mod", InitialKey1 = "", InitialKey2 = "" }
	end
	return list
end

function WFG:HotKey(id, state)
	local h = self.hotkeys[id]
	if h and type(h.fn) == "function" then
		local ok, err = pcall(h.fn, h.module, state)
		if not ok then self:Error("hotkey:" .. id, err) end
	end
end

------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------
function WFG:Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- 中文数字缩写：12345 -> 1.2万
function WFG:Num(v)
	v = math.floor(tonumber(v) or 0)
	if v >= 100000000 then
		return string.format("%.2f亿", v / 100000000)
	elseif v >= 10000 then
		return string.format("%.2f万", v / 10000)
	end
	return tostring(v)
end

-- 安全读取对象数值属性（不存在或非数字时给默认值）
-- 灵气在本作里叫 LingV（Thing.LingV），历史写法 Ling 并不存在。
-- 这里统一做别名，避免所有调用方各自记忆属性名。
local PROP_ALIAS = { Ling = "LingV" }

function WFG:Prop(obj, key, def)
	def = def or 0
	if obj == nil then return def end
	local ok, v = pcall(function() return obj[key] end)
	if ok and type(v) == "number" then return v end
	local alias = PROP_ALIAS[key]
	if alias ~= nil then
		ok, v = pcall(function() return obj[alias] end)
		if ok and type(v) == "number" then return v end
	end
	return def
end

-- 当前灵气
function WFG:Ling(npc)
	return self:Prop(npc, "LingV", 0)
end

-- 灵气上限
function WFG:MaxLing(npc)
	return self:Prop(npc, "MaxLing", 0)
end

-- 安全读取对象字符串属性
function WFG:PropStr(obj, key, def)
	if obj == nil then return def or "" end
	local ok, v = pcall(function() return obj[key] end)
	if ok and type(v) == "string" then return v end
	return def or ""
end

function WFG:Copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do
		r[k] = self:Copy(v)
	end
	return r
end

function WFG:Count(t)
	local n = 0
	if type(t) ~= "table" then return 0 end
	for _ in pairs(t) do n = n + 1 end
	return n
end

function WFG:Split(s, sep)
	local out = {}
	if type(s) ~= "string" then return out end
	for part in string.gmatch(s, "([^" .. sep .. "]+)") do
		out[#out + 1] = part
	end
	return out
end

-- 安全取值：任何异常都返回默认值，不中断调用方
function WFG:Safe(fn, def, ...)
	local ok, res = pcall(fn, ...)
	if ok then return res end
	return def
end

------------------------------------------------------------------------
-- 每帧回调：选点等需要逐帧采样的场景（定时器会漏掉 GetMouseButtonDown）
------------------------------------------------------------------------
WFG.stepHooks = WFG.stepHooks or {}

function WFG:OnStep(fn)
	if type(fn) ~= "function" then return end
	table.insert(WFG.stepHooks, fn)
	return fn
end

function WFG:RemoveStep(fn)
	for i = #WFG.stepHooks, 1, -1 do
		if WFG.stepHooks[i] == fn then table.remove(WFG.stepHooks, i) end
	end
end

function WFG:StepAll(dt)
	local list = WFG.stepHooks
	for i = 1, #list do
		local ok, err = pcall(list[i], dt)
		if not ok then WFG:Error("step.hook", err) end
	end
end

------------------------------------------------------------------------
-- 加载顺序无关：core 若晚于模块加载，把提前登记 pending 的模块补注册
------------------------------------------------------------------------
if type(WFG.pending) == "table" then
	local pend = WFG.pending
	WFG.pending = nil
	for i = 1, #pend do
		WFG:Register(pend[i])
	end
end


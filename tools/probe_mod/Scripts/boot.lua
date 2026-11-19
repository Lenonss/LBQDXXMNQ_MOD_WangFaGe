--[[
	万法阁 · 手机端可行性探针（WFGProbe）

	目的：用最小成本回答三个问题
	  1) 移动版是否加载 Lua（有没有出现 [WFGProbe] 行）
	  2) 三个内置依赖 SimpleWindow / MagicHelper / ThingHelper 是否存在
	  3) 屏幕物理分辨率、FairyGUI 逻辑分辨率、缩放因子、触摸支持情况

	用法：把本目录整份放进 Mods，进游戏勾选激活，截图弹窗（或抓日志里的 [WFGProbe] 行）。
	安全：只读不写游戏数据；不改任何存档与配置；除生命周期钩子外不注册任何逻辑。
]]

local tbMod = GameMain:NewMod("WFGProbe")

local buff = {}

local function add(k, v)
	buff[#buff + 1] = tostring(k) .. "=" .. tostring(v)
end

local function try(k, fn)
	local ok, r = pcall(fn)
	if ok then
		add(k, r)
	else
		add(k, "ERR:" .. tostring(r))
	end
end

local function safeLog(text)
	pcall(function() LogError(text) end)
	pcall(function() print(text) end)
end

local function collect(tag)
	buff = {}

	-- 运行环境
	try("tag", tag)
	try("lua", _VERSION)
	try("platform", CS.UnityEngine.Application.platform)
	try("unity", CS.UnityEngine.Application.unityVersion)
	try("screen", CS.UnityEngine.Screen.width .. "x" .. CS.UnityEngine.Screen.height)
	try("dpi", CS.UnityEngine.Screen.dpi)
	try("touchSupported", CS.UnityEngine.Input.touchSupported)
	try("touchCount", CS.UnityEngine.Input.touchCount)
	try("mousePresent", CS.UnityEngine.Input.mousePresent)

	-- FairyGUI 逻辑分辨率与缩放
	try("groot", tostring(CS.FairyGUI.GRoot.inst))
	try("grootSize", tostring(CS.FairyGUI.GRoot.inst.width) .. "x" .. tostring(CS.FairyGUI.GRoot.inst.height))
	try("contentScaleFactor", CS.FairyGUI.GRoot.inst.contentScaleFactor)

	-- 三个内置依赖
	try("SimpleWindow", type(GameMain:GetMod("SimpleWindow")))
	try("MagicHelper", type(GameMain:GetMod("MagicHelper")))
	try("ThingHelper", type(GameMain:GetMod("ThingHelper")))

	-- 引擎能力
	try("world", type(world))
	try("fileIO", type(CS.System.IO.File))
	try("persistentDataPath", CS.UnityEngine.Application.persistentDataPath)

	local text = "[WFGProbe] " .. table.concat(buff, " | ")
	safeLog(text)

	-- 能写文件就顺手落一份，省得抓日志
	pcall(function()
		local p = CS.UnityEngine.Application.persistentDataPath .. "/WFGProbe.txt"
		CS.System.IO.File.WriteAllText(p, text)
		safeLog("[WFGProbe] wrote " .. p)
	end)

	-- 弹窗：一台手机一张截图即可回传
	pcall(function()
		if world ~= nil then
			world:ShowMsgBox(text, "WFG 探针 · " .. tostring(tag))
		end
	end)
end

function tbMod:OnInit()
	collect("init")
end

function tbMod:OnEnter()
	collect("enter")
end

function tbMod:OnSetHotKey()
	return {}
end

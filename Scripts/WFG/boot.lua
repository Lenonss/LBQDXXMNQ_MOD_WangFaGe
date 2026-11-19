--[[
    万法阁 · 唯一生命周期入口
    只有本文件调用 GameMain:NewMod，避免同名重复注册导致钩子执行多次。
    其余文件只做「向 WFG 注册模块」，不持有 mod 表。
]]

local tbWG = GameMain:NewMod("万法阁")

function tbWG:OnInit()
	WFG:InitAll()
	WFG:Log("boot ok, modules=%d", #WFG.moduleList)
	-- 每秒一次的统一心跳：境界观察 + 各模块 OnSecond
	WFG:Every(1, "wfg.second", function()
		if WFG.npc and WFG.npc.Refresh then
			WFG:Safe(function() WFG.npc:Refresh() end)
		end
		WFG:SecondTick()
	end)
end

function tbWG:OnEnter()
	WFG:EnterAll()
end

function tbWG:OnLeave()
	WFG:LeaveAll()
end

function tbWG:OnStep(dt)
	WFG:StepTimers(dt)
	if WFG.StepAll ~= nil then WFG:StepAll(dt) end
end

function tbWG:OnSave()
	return WFG:SaveAll()
end

function tbWG:OnLoad(data)
	WFG:LoadAll(data)
end

function tbWG:OnAfterLoad()
	WFG:AfterLoadAll()
end

function tbWG:NeedSyncData()
	return false
end

function tbWG:OnSetHotKey()
	local list = {}
	for i = 1, #WFG.moduleList do
		local m = WFG.moduleList[i]
		if type(m.OnSetHotKey) == "function" then
			local ok, res = pcall(m.OnSetHotKey, m)
			if ok and type(res) == "table" then
				for _, v in ipairs(res) do list[#list + 1] = v end
			end
		end
	end
	return list
end

function tbWG:OnHotKey(id, state)
	WFG:HotKey(id, state)
end

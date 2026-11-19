--[[
    万法阁 · 总库建筑登记
    两座总库（WFG_Build_HallMat / WFG_Build_HallEng）落地后登记到世界数据，
    用于面板显示「已建成 / 未建成」与唯一性提示。

    说明：v1 中建筑为仪典性存在（不阻塞总库功能），避免脚本钩子异常时把玩法锁死；
    若实机确认 OnPutDown / OnAfterLoad 稳定，再改为强制约束。
]]

WFG = WFG or {}

local okMod, tbHelper = pcall(function() return GameMain:GetMod("ThingHelper") end)
if not okMod or tbHelper == nil then
	WFG:Log("ThingHelper 不可用，总库建筑登记跳过")
	return
end

local KINDS = {
	WFG_Build_HallMat = "mat",
	WFG_Build_HallEng = "eng",
}

local function mark(defName, kind, delta)
	local mod = WFG.GetModule and WFG:GetModule("yantian") or nil
	if mod == nil then return end
	local hall = WFG.YanTian and WFG.YanTian.hall
	if hall == nil then return end
	pcall(function() hall:MarkBuilt(mod, kind, delta) end)
end

for defName, kind in pairs(KINDS) do
	local ok, tbThing = pcall(function() return tbHelper:GetThing(defName) end)
	if ok and tbThing ~= nil then
		function tbThing:OnPutDown()
			mark(defName, kind, 1)
		end
		function tbThing:OnAfterLoad(dt)
			mark(defName, kind, 1)
		end
		function tbThing:OnPickUp()
			mark(defName, kind, -1)
		end
		function tbThing:OnDeath()
			mark(defName, kind, -1)
		end
	end
end

return true

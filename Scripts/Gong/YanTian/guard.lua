--[[
    衍天诀 · 避天机程序
    学会后由秘籍自带的 Modifier 永久叠加「瓶颈倒计时推迟」，
    天劫倒计时不再推进；是否飞升成仙改由角色主动触发。
]]

WFG = WFG or {}
WFG.YanTian = WFG.YanTian or {}

local G = {}

-- 该角色是否已掌握避天机（秘籍在身即可，不额外依赖境界）
function G:Active(M, npc)
	local def = WFG.YanTianDef
	return WFG.npc:IsLearned(npc, def.eso.guard)
end

-- 主动渡劫：mode = "stay"（留世渡劫，默认）/ "ascend"（登仙而去）
function G:Ascend(M, npc, keepWorld)
	local def = WFG.YanTianDef
	local c = M:Char(npc, true)
	if c == nil then return false, "未找到角色数据" end
	if not self:Active(M, npc) then
		return false, "尚未习得避天机程序"
	end
	if (c.stage or 0) < def.gateFinal then
		return false, "需臻至天门境方可渡劫"
	end
	local staying = (keepWorld ~= false)
	if staying and c.stayPending ~= 1 and c.ascendPending ~= 1 then
		-- 第一次点「渡劫」只提示二选一，避免误触
		c.stayPending = 1
		return false, "天机已蔽：请再次确认——「留世渡劫」还是「登仙而去」"
	end

	local practice = WFG.npc:Practice(npc)
	if practice == nil then return false, "无法取得修行数据" end

	local ok, err = pcall(function() practice:BeginJieNan() end)
	if not ok then
		WFG:Error("guard.ascend", tostring(err))
		return false, "渡劫接口调用失败，详见日志"
	end
	c.stayPending = nil
	c.ascendPending = nil
	c.guard = 1
	c.path = staying and "stay" or "ascend"
	WFG:Log("[避天机] %s 主动引动天劫（%s）", WFG.npc:GetName(npc), staying and "留世" or "登仙")
	if staying then
		return true, "天劫将至。渡劫功成，你仍立于人间，只是再无人能算你的命数。"
	end
	return true, "天门已开。渡劫功成之日，此身将离世登仙。"
end

-- 二次确认入口：面板先点「留世渡劫」/「登仙而去」
function G:Choose(M, npc, path)
	local c = M:Char(npc, true)
	if c == nil then return false, "未找到角色数据" end
	if path == "ascend" then
		c.stayPending = nil
		c.ascendPending = 1
		c.path = "ascend"
		return true, "已选定：登仙而去。再点一次「渡劫」，天门便开。"
	end
	c.ascendPending = nil
	c.stayPending = 1
	c.path = "stay"
	return true, "已选定：留世渡劫。再点一次「渡劫」，雷劫便至。"
end

function G:Pending(M, npc)
	local c = M:Char(npc, false)
	if c == nil then return nil end
	return c.stayPending or c.ascendPending
end

function G:Second(M)
	-- 兜底：秘籍 Modifier 若因读档丢失，尝试补一次
	for i = 1, #(WFG.npc.list or {}) do
		local npc = WFG.npc.list[i]
		if WFG.npc:GetGongName(npc) == WFG.YanTianDef.gong and self:Active(M, npc) then
			local c = M:Char(npc, true)
			if c and c.guardRefresh ~= 1 then
				c.guardRefresh = 1
			end
		end
	end
end

WFG.YanTian.guard = G
return G

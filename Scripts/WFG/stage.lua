--[[
    万法阁 · 境界观察器（NPC 服务）
    - 每秒扫描玩家门下 NPC，读取其功法名与境界层
    - 境界变化时派发模块的 OnStageChange(npc, gongName, fromLevel, toLevel)
    - 缓存 per-npc 数据，读档/切图后由 AfterLoad 重建（缓存本身可随时重建，不入档）
]]

WFG.npc = WFG.npc or {}
local S = WFG.npc

S.list  = S.list  or {}   -- 本次扫描到的 npc 列表
S.cache = S.cache or {}   -- npcId -> { gong=, level= }
S.lastScanLog = 0
S.scanWarned = false

-- 取得 NPC 的 Lua 助手；失败返回 nil
function S:Helper(npc)
	if npc == nil then return nil end
	local ok, helper = pcall(function() return CS.XiaWorld.NpcLuaHelper(npc) end)
	if not ok or helper == nil then return nil end
	return helper
end

function S:Id(npc)
	if npc == nil then return nil end
	local ok, id = pcall(function() return npc.ID end)
	if ok and id ~= nil then return tostring(id) end
	return nil
end

function S:GetGongName(npc)
	local h = self:Helper(npc)
	if h == nil then return nil end
	local ok, name = pcall(function() return h:GetGongName() end)
	if ok then return name end
	return nil
end

function S:GetLevel(npc)
	local h = self:Helper(npc)
	if h == nil then return 0 end
	local ok, lv = pcall(function() return h:GetGLevel() end)
	if ok and type(lv) == "number" then return lv end
	return 0
end

function S:IsLearned(npc, esotericName)
	local h = self:Helper(npc)
	if h == nil then return false end
	local ok, res = pcall(function() return h:IsLearnedEsoteric(esotericName) end)
	return ok and res == true
end

-- 取 NPC 的修行数据（NpcPractice）。引擎只在 NpcPropertyMgr 上注册了 Practice，
-- Npc 本身没有 Practice —— 写 npc.Practice 会静默拿到 nil（不报错），
-- 于是 CheckMagic/AddMagic/RemoveMagic 全部空转。
function S:Practice(npc)
	if npc == nil then return nil end
	local ok, p = pcall(function() return npc.PropertyMgr.Practice end)
	if ok and p ~= nil then return p end
	ok, p = pcall(function() return npc.Practice end)
	if ok then return p end
	return nil
end

-- 取玩家当前激活弟子（失败时返回空表并只报一次日志）
function S:GetName(npc)
	if npc == nil then return "未知" end
	local ok, v = pcall(function() return npc.Name end)
	if ok and type(v) == "string" and v ~= "" then return v end
	ok, v = pcall(function() return npc.FullName end)
	if ok and type(v) == "string" and v ~= "" then return v end
	return "无名"
end

function S:List()
	local ok, res = pcall(function()
		return World.map.Things:GetPlayerActiveNpcs()
	end)
	if not ok or res == nil then
		if not self.scanWarned then
			self.scanWarned = true
			WFG:Error("npc.List", tostring(res))
		end
		return {}
	end
	-- GetPlayerActiveNpcs 返回 C# List，必须按 Count + 0 基下标转成 Lua 表
	local out = {}
	local okc, cnt = pcall(function() return res.Count end)
	if okc and type(cnt) == "number" then
		for i = 0, cnt - 1 do out[#out + 1] = res[i] end
	else
		for _, v in ipairs(res) do out[#out + 1] = v end
	end
	return out
end

-- 每秒调用：拉取 NPC、更新缓存、派发境界变化
function S:Refresh()
	local npcs = self:List()
	self.list = npcs
	local seen = {}

	for i = 1, #npcs do
		local npc = npcs[i]
		local id = self:Id(npc)
		if id ~= nil then
			seen[id] = true
			local gong = self:GetGongName(npc) or ""
			local lv = self:GetLevel(npc)
			local old = self.cache[id]
			if old == nil then
				self.cache[id] = { gong = gong, level = lv }
				if gong ~= "" and lv > 0 then
					self:Dispatch(npc, gong, 0, lv)
				end
			elseif old.gong ~= gong or old.level ~= lv then
				local fromLv = old.level
				old.gong = gong
				old.level = lv
				if gong ~= "" then
					self:Dispatch(npc, gong, fromLv, lv)
				end
			end
		end
	end

	-- 清理已不在场景中的 NPC 缓存，避免无限增长
	for id in pairs(self.cache) do
		if not seen[id] then self.cache[id] = nil end
	end
end

function S:Dispatch(npc, gong, fromLv, toLv)
	WFG:ForEachModule(function(m)
		if type(m.OnStageChange) == "function" then
			-- 只派发给关心该功法的模块（gong 为空的模块视为全局）
			if m.gong == nil or m.gong == "" or m.gong == gong then
				WFG:Call(m, "OnStageChange", npc, gong, fromLv, toLv)
			end
		end
	end)
end

function S:GetLevelOf(npc)
	local id = self:Id(npc)
	local c = id and self.cache[id]
	if c then return c.level or 0 end
	return self:GetLevel(npc)
end

function S:ClearCache()
	self.cache = {}
	self.list = {}
end

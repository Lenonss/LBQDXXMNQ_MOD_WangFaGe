--[[
    衍天诀 · 本命法宝（灵析剑 / 灵源剑）
    - 两件法宝都是真实物品，走官方法宝炼制；本模块只负责佩戴后的功能
    - 佩带灵析剑：角色素材库与共享素材总库每秒双向自动同步（无存取 UI）
    - 佩带灵源剑：共享能源核心自动供灵（实时/充满两种模式）
    - 属性大幅加成只在「功法 = 衍天诀」且佩带对应剑时挂载
]]

WFG = WFG or {}
WFG.YanTian = WFG.YanTian or {}

local H = {}

local BUFF_MAT = "WFG_Mod_YanTian_FabaoMat"
local BUFF_ENG = "WFG_Mod_YanTian_FabaoEng"

local function num(npc, key)
	local ok, v = pcall(function() return npc[key] end)
	if ok and type(v) == "number" then return v end
	if key == "Ling" then
		ok, v = pcall(function() return npc.LingV end)
		if ok and type(v) == "number" then return v end
	end
	return 0
end

local function addLing(npc, v)
	if v == 0 then return end
	WFG:Safe(function() npc:AddLing(v) end)
end

local function isYanTian(npc)
	local ok, r = pcall(function() return WFG.npc:GetGongName(npc) == WFG.YanTianDef.gong end)
	return ok and r == true
end

------------------------------------------------------------------------
-- 池
------------------------------------------------------------------------
function H:MatPool(M)
	local w = M.store.world
	w.hallMat = w.hallMat or { items = {} }
	w.hallMat.items = w.hallMat.items or {}
	w.hallMat.ver = w.hallMat.ver or 0
	return w.hallMat
end

function H:EngPool(M)
	local w = M.store.world
	local def = WFG.YanTianDef
	w.hallEng = w.hallEng or { ling = 0, cap = def.fabao.energyCap }
	if not w.hallEng.cap then w.hallEng.cap = def.fabao.energyCap end
	return w.hallEng
end

function H:EngLing(M)
	return self:EngPool(M).ling or 0
end

------------------------------------------------------------------
-- 总库建筑登记（由 Scripts/Thing/WFG_Hall.lua 调用）
------------------------------------------------------------------
function H:BuiltCount(M, kind)
	local w = M.store.world
	w.hallBuilt = w.hallBuilt or {}
	return w.hallBuilt[kind] or 0
end

function H:MarkBuilt(M, kind, delta)
	local w = M.store.world
	w.hallBuilt = w.hallBuilt or {}
	local n = (w.hallBuilt[kind] or 0) + (delta or 1)
	if n < 0 then n = 0 end
	w.hallBuilt[kind] = n
	if n > 1 then
		WFG:Log("[总库] %s 总库建筑出现 %d 座（设计上只应有一座）", tostring(kind), n)
	end
end

------------------------------------------------------------------------
-- 佩戴判定
------------------------------------------------------------------------
function H:EquipState(npc, kind)
	local def = WFG.YanTianDef
	local name = (kind == "mat") and def.item.hallMat or def.item.hallEng
	if WFG.item == nil or type(WFG.item.EquipState) ~= "function" then
		return "unavailable"
	end
	local ok, st = pcall(function() return WFG.item:EquipState(npc, name) end)
	if not ok then return "unavailable" end
	return st or "none"
end

function H:MatOn(npc)
	return self:EquipState(npc, "mat") == "equipped"
end

function H:EngOn(npc)
	return self:EquipState(npc, "eng") == "equipped"
end

------------------------------------------------------------------------
-- 素材库：佩戴灵析剑后与共享总库双向自动同步
------------------------------------------------------------------------
local function mergeToPool(old, e)
	local changed = false
	local q = tonumber(e.q) or 1
	local lv = tonumber(e.lv) or 0
	if q > (old.q or 1) then old.q = q changed = true end
	if lv > (old.lv or 0) then old.lv = lv changed = true end
	if old.name == nil and e.name ~= nil then old.name = e.name changed = true end
	old.stuffs = old.stuffs or {}
	for st in pairs(e.stuffs or {}) do
		if not old.stuffs[st] then old.stuffs[st] = true changed = true end
	end
	old.quals = old.quals or {}
	for qq in pairs(e.quals or {}) do
		if not old.quals[qq] then old.quals[qq] = true changed = true end
	end
	return changed
end

local function mergeFromPool(e, p)
	local changed = false
	local q = tonumber(p.q) or 1
	local lv = tonumber(p.lv) or 0
	if q > (e.q or 1) then e.q = q changed = true end
	if q > (e.maxq or 1) then e.maxq = q changed = true end
	if lv > (e.lv or 0) then e.lv = lv changed = true end
	if e.name == nil and p.name ~= nil then e.name = p.name changed = true end
	e.stuffs = e.stuffs or {}
	for st in pairs(p.stuffs or {}) do
		if not e.stuffs[st] then e.stuffs[st] = true changed = true end
	end
	e.quals = e.quals or {}
	for qq in pairs(p.quals or {}) do
		if not e.quals[qq] then e.quals[qq] = true changed = true end
	end
	return changed
end

function H:LibStats(c)
	local own, shared = 0, 0
	for _, e in pairs((c and c.lib) or {}) do
		if e.own == false then shared = shared + 1 else own = own + 1 end
	end
	return own, shared
end

function H:SyncMat(M, npc, c)
	if c == nil then return end
	local pool = self:MatPool(M)

	-- 个人 -> 总库：只推真正拥有的条目，共享借用条目不回流
	if (c.libVer or 0) ~= (c._pushVer or -1) then
		local changed = false
		for defName, e in pairs(c.lib or {}) do
			if e.own ~= false then
				local old = pool.items[defName]
				if old == nil then
					old = { q = e.q or 1, lv = e.lv or 0, name = e.name, stuffs = {}, quals = {} }
					for st in pairs(e.stuffs or {}) do old.stuffs[st] = true end
					for qq in pairs(e.quals or {}) do old.quals[qq] = true end
					pool.items[defName] = old
					changed = true
				elseif mergeToPool(old, e) then
					changed = true
				end
			end
		end
		c._pushVer = c.libVer or 0
		if changed then pool.ver = (pool.ver or 0) + 1 end
	end

	-- 总库 -> 个人：新条目记为借用；已有条目并集合并，自有标记不变
	if (pool.ver or 0) ~= (c.sharedVer or -1) then
		local libChanged = false
		c.lib = c.lib or {}
		for defName, p in pairs(pool.items) do
			local e = c.lib[defName]
			if e == nil then
				e = {
					q = p.q or 1, maxq = p.q or 1, lv = p.lv or 0, name = p.name,
					n = 0, stuffs = {}, quals = {}, own = false,
				}
				for st in pairs(p.stuffs or {}) do e.stuffs[st] = true end
				for qq in pairs(p.quals or {}) do e.quals[qq] = true end
				c.lib[defName] = e
				libChanged = true
			elseif mergeFromPool(e, p) then
				libChanged = true
			end
		end
		c.sharedVer = pool.ver or 0
		if libChanged then c.libVer = (c.libVer or 0) + 1 end
	end
end

-- 卸下/转功法：清掉从总库借来的条目，自己解析过的保留
function H:ClearShared(M, npc, c)
	if c == nil or type(c.lib) ~= "table" then return 0 end
	local n = 0
	for defName, e in pairs(c.lib) do
		if e.own == false then
			c.lib[defName] = nil
			n = n + 1
		end
	end
	if n > 0 then c.libVer = (c.libVer or 0) + 1 end
	c.sharedVer = nil
	c._pushVer = nil
	return n
end

------------------------------------------------------------------------
-- 属性加成：仅衍天诀 + 佩带对应剑
------------------------------------------------------------------------
local function addMod(npc, name)
	local ok, err = pcall(function() npc:AddModifier(name) end)
	if not ok then
		WFG:Error("fabao.add", tostring(name) .. " " .. tostring(err))
		return false
	end
	return true
end

local function delMod(npc, name)
	pcall(function() npc:RemoveModifier(name) end)
end

function H:SyncBuff(M, npc, c)
	if c == nil then return end
	local yan = isYanTian(npc)
	local wantMat = yan and self:MatOn(npc)
	local wantEng = yan and self:EngOn(npc)

	if wantMat and not c._buffMat then
		if addMod(npc, BUFF_MAT) then
			c._buffMat = true
			WFG:Log("[法宝] %s 灵析剑加成生效", WFG.npc:GetName(npc))
		end
	elseif not wantMat and c._buffMat then
		delMod(npc, BUFF_MAT)
		c._buffMat = false
		WFG:Log("[法宝] %s 灵析剑加成移除", WFG.npc:GetName(npc))
	end

	if wantEng and not c._buffEng then
		if addMod(npc, BUFF_ENG) then
			c._buffEng = true
			WFG:Log("[法宝] %s 灵源剑加成生效", WFG.npc:GetName(npc))
		end
	elseif not wantEng and c._buffEng then
		delMod(npc, BUFF_ENG)
		c._buffEng = false
		WFG:Log("[法宝] %s 灵源剑加成移除", WFG.npc:GetName(npc))
	end
end

function H:ClearAllBuffs(M)
	local list = WFG.npc.list or {}
	for i = 1, #list do
		delMod(list[i], BUFF_MAT)
		delMod(list[i], BUFF_ENG)
	end
	for _, c in pairs((M and M.store and M.store.char) or {}) do
		c._buffMat = false
		c._buffEng = false
	end
end

------------------------------------------------------------------------
-- 能源核心：存取与自动供灵
------------------------------------------------------------------------
function H:CanUseEng(npc)
	return isYanTian(npc) and self:EngOn(npc)
end

function H:DepositLing(M, npc, amount)
	if not self:CanUseEng(npc) then
		return false, "需衍天诀且佩带灵源剑"
	end
	local pool = self:EngPool(M)
	local ling = num(npc, "Ling")
	amount = math.floor(amount or 0)
	if amount <= 0 or amount > ling then
		return false, "可存入的灵气不足"
	end
	local space = pool.cap - pool.ling
	if space <= 0 then return false, "总核心已满" end
	local real = math.min(amount, space)
	addLing(npc, -real)
	pool.ling = pool.ling + real
	return true, string.format("已存入 %s 灵气，总核心现有 %s", WFG:Num(real), WFG:Num(pool.ling))
end

function H:WithdrawLing(M, npc, amount)
	if not self:CanUseEng(npc) then
		return false, "需衍天诀且佩带灵源剑"
	end
	local pool = self:EngPool(M)
	amount = math.floor(amount or 0)
	if amount <= 0 then return false, "数量无效" end
	if pool.ling < amount then return false, "总核心中灵气不足" end
	local maxLing = num(npc, "MaxLing")
	local ling = num(npc, "Ling")
	local space = maxLing - ling
	if space <= 0 then return false, "自身灵气已满" end
	local real = math.min(amount, space)
	addLing(npc, real)
	pool.ling = pool.ling - real
	return true, string.format("已取用 %s 灵气", WFG:Num(real))
end

function H:TickEnergy(M, npc, c)
	local def = WFG.YanTianDef
	if not self:CanUseEng(npc) then return end
	local cfg = c.fabao or {}
	local mode = cfg.mode or def.fabao.defaultMode
	local pool = self:EngPool(M)
	if pool.ling <= 0 then return end

	local maxLing = num(npc, "MaxLing")
	local ling = num(npc, "Ling")
	if maxLing <= 0 then return end

	if mode == 1 then
		-- 实时获取：低于阈值就补到阈值，累计取用不超过限额
		local pct = cfg.x
		if type(pct) ~= "number" or pct <= 0 then pct = def.fabao.defaultThresholdPct end
		local aim = maxLing * pct
		if ling >= aim then return end
		local limit = cfg.limit
		if type(limit) ~= "number" or limit <= 0 then limit = def.fabao.defaultLimit end
		local used = cfg.used or 0
		local remain = limit - used
		if remain <= 0 then return end
		local take = math.min(aim - ling, remain, pool.ling)
		if take <= 0 then return end
		addLing(npc, take)
		pool.ling = pool.ling - take
		cfg.used = used + take
	elseif mode == 2 then
		-- 充满获取：灵气见底时一次取定量
		if ling > 0 then return end
		local burst = cfg.burst
		if type(burst) ~= "number" or burst <= 0 then burst = def.fabao.defaultBurst end
		local take = math.min(burst, pool.ling, maxLing)
		if take <= 0 then return end
		addLing(npc, take)
		pool.ling = pool.ling - take
	end
end

-- 参数管理只要求衍天诀：未佩带灵源剑时也可以先设好取用参数。
local function energyCfg(M, npc)
	if not isYanTian(npc) then return nil, "需修衍天诀" end
	local c = M:Char(npc, true)
	if c == nil then return nil, "未找到角色数据" end
	c.fabao = c.fabao or {}
	return c.fabao, nil
end

function H:ResetLimit(M, npc)
	local cfg, err = energyCfg(M, npc)
	if cfg == nil then return false, err end
	cfg.limit = tonumber(cfg.limit) or 0
	cfg.used = 0
	return true, "实时获取的已用限额已重置"
end

function H:SetMode(M, npc, mode)
	local cfg, err = energyCfg(M, npc)
	if cfg == nil then return false, err end
	cfg.mode = (mode == 2) and 2 or 1
	cfg.used = 0
	return true, (cfg.mode == 1) and "已切换为：实时获取" or "已切换为：充满获取"
end

function H:SetThreshold(M, npc, pct)
	local cfg, err = energyCfg(M, npc)
	if cfg == nil then return false, err end
	pct = tonumber(pct) or 0
	if pct < 0.1 then pct = 0.1 end
	if pct > 0.9 then pct = 0.9 end
	cfg.x = pct
	return true, string.format("补灵阈值已设为 %d%%", math.floor(pct * 100 + 0.5))
end

function H:SetLimit(M, npc, limit)
	local cfg, err = energyCfg(M, npc)
	if cfg == nil then return false, err end
	limit = math.floor(tonumber(limit) or 0)
	if limit < 100000 then limit = 100000 end
	if limit > 10000000 then limit = 10000000 end
	cfg.limit = limit
	if (cfg.used or 0) > limit then cfg.used = limit end
	return true, "实时获取限额已设为 " .. WFG:Num(limit)
end

function H:SetBurst(M, npc, burst)
	local cfg, err = energyCfg(M, npc)
	if cfg == nil then return false, err end
	burst = math.floor(tonumber(burst) or 0)
	if burst < 1000 then burst = 1000 end
	if burst > 1000000 then burst = 1000000 end
	cfg.burst = burst
	return true, "单次取用已设为 " .. WFG:Num(burst)
end

------------------------------------------------------------------------
-- 每秒维护
------------------------------------------------------------------------
function H:Second(M)
	local list = WFG.npc.list or {}
	for i = 1, #list do
		local npc = list[i]
		local c = M:Char(npc, false)
		if c ~= nil then
			if isYanTian(npc) then
				if self:MatOn(npc) then
					self:SyncMat(M, npc, c)
				else
					self:ClearShared(M, npc, c)
				end
				self:SyncBuff(M, npc, c)
				if self:EngOn(npc) then self:TickEnergy(M, npc, c) end
			else
				-- 非衍天诀：借来的素材不保留，加成也一并移除
				self:ClearShared(M, npc, c)
				self:SyncBuff(M, npc, c)
			end
		end
	end
end

WFG.YanTian.hall = H
return H
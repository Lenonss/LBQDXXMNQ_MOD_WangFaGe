--[[
    衍天诀 · 衍天（解析 / 创造）
    解析：消耗灵气把物品构造记入该角色的素材库。
          素材条目按「物品定义」收录，并记录两个维度的解锁集合：
            stuffs = { [材料定义名] = true }   -- 材料录入即解锁
            quals  = { [品级 1..5] = true }    -- 品级录入即解锁
    创造：消耗灵气从素材库中再造物品，可指定材料 / 品级 / 批量 / 存入灵气量。
]]

WFG = WFG or {}
WFG.YanTian = WFG.YanTian or {}

local D = {}

local function log(fmt, ...)
	WFG:Log("[衍天] " .. string.format(fmt, ...))
end

local function num(v, def)
	v = tonumber(v)
	if v == nil then return def end
	return v
end

-- 取素材条目（并补齐旧档缺失的字段）
function D:Entry(c, defName)
	if c == nil or c.lib == nil then return nil end
	local e = c.lib[defName]
	if e == nil then return nil end
	e.stuffs = e.stuffs or {}
	e.quals = e.quals or {}
	e.maxq = num(e.maxq, num(e.q, 1))
	e.q = num(e.q, e.maxq)
	e.lv = num(e.lv, 0)
	e.n = num(e.n, 0)
	return e
end

-- 条目里已解锁的最高品级
function D:TopQual(e)
	local top = 1
	for q in pairs(e.quals or {}) do
		if q > top then top = q end
	end
	if e.maxq ~= nil and e.maxq > top then top = e.maxq end
	return top
end

-- 条目里已解锁的材料（按名字排序，便于下拉框稳定顺序）
function D:StuffList(e)
	local out = {}
	for s in pairs(e.stuffs or {}) do out[#out + 1] = s end
	table.sort(out)
	return out
end

function D:QualList(e)
	local out = {}
	for q in pairs(e.quals or {}) do out[#out + 1] = q end
	table.sort(out)
	return out
end

-- 当前境界可解析的最高等阶
function D:MaxLevel(M, npc)
	local c = M:Char(npc, true)
	return WFG.YanTianDef:MaxDeriveLevel(c and c.stage or 1)
end

-- 解析前的信息汇总（只读，不扣灵气），供确认窗使用
function D:Quote(M, npc, thing)
	local def = WFG.YanTianDef
	local out = {
		ok = false, reason = "", defName = "", name = "",
		lv = 0, q = 1, maxLv = 0, cost = 0,
		stuff = nil, stuffName = "", stuffCount = 0, qualCount = 0,
		ling = WFG:Ling(npc), maxLing = WFG:MaxLing(npc),
		enough = false, already = false,
	}
	local c = M ~= nil and M:Char(npc, true) or nil
	if c == nil then out.reason = "未找到角色数据" return out end

	local defName = WFG.item:DefName(thing)
	if defName == nil then out.reason = "无法识别该物品" return out end
	out.defName = defName
	out.name = WFG.item:NameOf(thing)
	out.lv = WFG.item:Level(thing)
	out.q = WFG.item:Quality(thing)
	out.maxLv = def:MaxDeriveLevel(c.stage or 1)
	out.stuff = WFG.item:Stuff(thing)
	out.stuffName = out.stuff ~= nil and WFG.item:StuffName(out.stuff) or "未记录"

	if (c.stage or 0) < def.gateDerive then
		out.reason = "尚未踏入衍天境"
		out.cost = def:DeriveCost(out.lv, out.q, npc)
		return out
	end
	if out.lv > out.maxLv then
		out.reason = string.format("等阶过高：该物品 %d 阶，当前最多解析 %d 阶", out.lv, out.maxLv)
		out.cost = def:DeriveCost(out.lv, out.q, npc)
		return out
	end

	local e = self:Entry(c, defName)
	local top = e ~= nil and self:TopQual(e) or 0
	out.already = e ~= nil and top >= out.q
	if e ~= nil then
		out.stuffCount = #self:StuffList(e)
		out.qualCount = #self:QualList(e)
	end
	local cost = def:DeriveCost(out.lv, out.q, npc)
	if e ~= nil and top < out.q then cost = math.floor(cost * 0.5) end
	out.cost = cost
	out.enough = out.ling >= cost
	out.ok = true
	return out
end

-- 解析一个物品对象：写入材料 / 品级解锁集合
function D:Parse(M, npc, thing, silent)
	local def = WFG.YanTianDef
	local c = M:Char(npc, true)
	if c == nil then return false, "未找到角色数据" end
	if (c.stage or 0) < def.gateDerive then
		return false, "尚未踏入衍天境（须修至第 7 境·衍天境）"
	end
	local defName = WFG.item:DefName(thing)
	if defName == nil then return false, "无法识别该物品" end

	local lv = WFG.item:Level(thing)
	local q = WFG.item:Quality(thing)
	local stuff = WFG.item:Stuff(thing)
	local maxLv = def:MaxDeriveLevel(c.stage)
	if lv > maxLv then
		return false, string.format("等阶不足：该物品 %d 阶，当前最多可解析 %d 阶", lv, maxLv)
	end

	c.lib = c.lib or {}
	local e = self:Entry(c, defName)
	local top = e ~= nil and self:TopQual(e) or 0
	local newStuff = (e == nil) or (stuff ~= nil and e.stuffs[stuff] == nil)
	local newQual = (e == nil) or (q > top)

	if e ~= nil and not newStuff and not newQual then
		-- 已收录且没有新信息：免费刷新显示信息
		local oldLv = e.lv or 0
		e.name = WFG.item:NameOf(thing)
		e.lv = math.max(e.lv or 0, lv)
		e.n = (e.n or 0) + 1
		-- 借用的条目被本人重新解析，转为自有；等阶刷新也要同步给总库
		if e.own == false or e.lv ~= oldLv then
			e.own = nil
			c.libVer = (c.libVer or 0) + 1
		end
		if not silent then log("%s 已在素材库中（最高品级 %d），无需重复解析", defName, top) end
		return true, "已收录"
	end

	local cost = def:DeriveCost(lv, q, npc)
	if e ~= nil and newQual then cost = math.floor(cost * 0.5) end
	if e ~= nil and not newQual then cost = math.floor(cost * 0.3) end

	local ling = WFG:Ling(npc)
	if ling < cost then
		return false, string.format("灵气不足：需要 %d，当前 %d", cost, ling)
	end

	WFG:Safe(function() npc:AddLing(-cost) end)

	if e == nil then
		e = { name = WFG.item:NameOf(thing), lv = lv, q = q, maxq = q, n = 0, stuffs = {}, quals = {} }
		c.lib[defName] = e
	end
	e.name = e.name or WFG.item:NameOf(thing)
	e.lv = math.max(e.lv or 0, lv)
	e.q = math.max(num(e.q, 1), q)
	e.maxq = math.max(num(e.maxq, 1), q)
	if stuff ~= nil then e.stuffs[stuff] = true end
	e.quals[q] = true
	e.n = (e.n or 0) + 1
	-- 实际写入：借用的转为自有，并通知自动同步把变化推给总库
	e.own = nil
	c.libVer = (c.libVer or 0) + 1

	log("解析 %s（%d 阶 / 品级 %d / 材料 %s），消耗灵气 %d", defName, lv, q, tostring(stuff), cost)
	return true, string.format("解析成功：%s（品级 %d）", WFG.item:Show(defName), q)
end

-- 校验「材料 / 品级」是否已在条目里解锁，返回归一化后的值
function D:Pick(e, stuff, quality)
	local top = self:TopQual(e)
	local q = math.max(1, math.min(5, math.floor(num(quality, top))))
	local stuffs = self:StuffList(e)
	local s = stuff
	if s == nil or not e.stuffs[s] then s = stuffs[1] end
	return s, q, e.stuffs[s] == true, e.quals[q] == true
end

-- 单件可储灵上限 × 件数
function D:LingLimit(defName, count)
	local cap = WFG.item:LingCap(defName)
	-- 原版多数工具/材料的 LingMax 为 0；为避免「储灵永远调不动」，
	-- 这类物品给一个功法侧兜底上限（造物时临时抬高 def 上限写入）。
	local fallback = (WFG.YanTianDef and WFG.YanTianDef.lingFallback) or 100
	if cap == nil or cap <= 0 then cap = fallback end
	count = math.max(1, math.floor(num(count, 1)))
	return cap, cap * count
end

-- 从素材库创造：stuff 材料、quality 品级、ling 存入该批物品的灵气总量
function D:Create(M, npc, defName, count, gridKey, stuff, quality, ling)
	local def = WFG.YanTianDef
	local c = M:Char(npc, true)
	if c == nil then return false, "未找到角色数据" end
	if (c.stage or 0) < def.gateDerive then
		return false, "尚未踏入衍天境"
	end
	local e = self:Entry(c, defName)
	if e == nil then return false, "素材库中没有此物" end

	count = math.max(1, math.floor(num(count, 1)))
	local maxBatch = def:BatchMax(c.stage)
	if count > maxBatch then
		return false, string.format("单次最多创造 %d 件", maxBatch)
	end

	local st, q, stuffOk, qualOk = self:Pick(e, stuff, quality)
	if not qualOk then return false, string.format("品级 %d 尚未解锁", q) end

	ling = math.max(0, num(ling, 0))
	local _, lingMax = self:LingLimit(defName, count)
	if lingMax > 0 and ling > lingMax then
		return false, string.format("存入灵气超过上限：最多 %d", math.floor(lingMax))
	end
	if lingMax <= 0 and ling > 0 then
		return false, "该物品不能储存灵气"
	end

	local cost = def:CreateCost(e.lv, q, count, npc)
	local total = cost + ling
	local have = WFG:Ling(npc)
	if have < total then
		return false, string.format("灵气不足：需要 %d（造物 %d + 储灵 %d），当前 %d", total, cost, ling, have)
	end

	if not WFG.item:Create(defName, q, count, npc, gridKey, st, ling) then
		return false, "创造失败（造物接口异常，详见日志）"
	end
	WFG:Safe(function() npc:AddLing(-total) end)
	log("创造 %s × %d（品级 %d / 材料 %s / 储灵 %d），消耗灵气 %d", defName, count, q, tostring(st), ling, total)
	return true, string.format("创造成功：%s × %d", WFG.item:Show(defName), count)
end

-- 只算不扣：给创造确认窗用的报价
function D:QuoteCreate(M, npc, defName, count, stuff, quality, ling)
	local def = WFG.YanTianDef
	local c = M ~= nil and M:Char(npc, true) or nil
	local out = {
		ok = false, reason = "", cost = 0, store = 0, total = 0,
		ling = 0, maxLing = 0, enough = false, maxBatch = 0,
		q = 1, stuff = nil, stuffName = "", stuffs = {}, quals = {},
		lingCap = 0, lingMax = 0,
	}
	if c == nil then out.reason = "未找到角色数据" return out end
	local e = self:Entry(c, defName)
	if e == nil then out.reason = "素材库中没有此物" return out end
	if (c.stage or 0) < def.gateDerive then out.reason = "尚未踏入衍天境" return out end

	count = math.max(1, math.floor(num(count, 1)))
	local maxBatch = def:BatchMax(c.stage)
	if count > maxBatch then out.reason = string.format("单次最多创造 %d 件", maxBatch) return out end

	local st, q, stuffOk, qualOk = self:Pick(e, stuff, quality)
	if not qualOk then out.reason = string.format("品级 %d 尚未解锁", q) return out end

	local cap, capAll = self:LingLimit(defName, count)
	ling = math.max(0, num(ling, 0))
	if capAll > 0 and ling > capAll then ling = capAll end
	if capAll <= 0 then ling = 0 end

	local cost = def:CreateCost(e.lv, q, count, npc)
	local have = WFG:Ling(npc)
	out.ok = true
	out.count = count
	out.cost = cost
	out.store = ling
	out.total = cost + ling
	out.q = q
	out.stuff = st
	out.stuffName = st ~= nil and WFG.item:StuffName(st) or "未记录（随机）"
	out.stuffs = self:StuffList(e)
	out.quals = self:QualList(e)
	out.lingCap = cap
	out.lingMax = capAll
	out.maxBatch = maxBatch
	out.ling = have
	out.maxLing = WFG:MaxLing(npc)
	out.enough = have >= out.total
	return out
end

-- 素材库列表（按等阶、定义名排序）
function D:List(M, npc)
	local c = M:Char(npc, true)
	local tb = {}
	if c == nil or c.lib == nil then return tb end
	for defName, raw in pairs(c.lib) do
		local e = self:Entry(c, defName)
		local meta = WFG.item:Meta(defName)
		local cap = WFG.item:LingCap(defName)
		tb[#tb + 1] = {
			name = (e.name ~= nil and e.name ~= "") and e.name or WFG.item:Show(defName),
			defName = defName,
			q = self:TopQual(e), lv = e.lv or 0, n = e.n or 0,
			stuffs = self:StuffList(e), quals = self:QualList(e),
			lingCap = cap,
			kind = meta.kind, tier = meta.lv, el = meta.el,
		}
	end
	table.sort(tb, function(a, b)
		if a.lv ~= b.lv then return a.lv < b.lv end
		return a.name < b.name
	end)
	return tb
end

function D:Has(M, npc, keyword)
	local tb = self:List(M, npc)
	for i = 1, #tb do
		if string.find(tb[i].name, keyword, 1, true) then return true end
	end
	return false
end

WFG.YanTian.derive = D
return D

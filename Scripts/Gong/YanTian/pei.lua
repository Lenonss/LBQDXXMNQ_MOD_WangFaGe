--[[
    衍天诀 · 衍天佩
    - 装备检测、按已学 14 项技能逐项解锁
    - 被动项：9 个 Modifier（与原技能 Modifier 同值，合计为原增幅 2 倍）
    - 自愈 / 精研 / 解析 / 创造：由 heal.lua、def.lua 实时查询
    - 炼石：只 AddMagic / RemoveMagic，提供主动神通按钮；绝不自动施法
]]
WFG = WFG or {}
WFG.YanTian = WFG.YanTian or {}

local P = {}

P.ITEM  = "WFG_Item_YanTianPei"
P.MAGIC = "WFG_Magic_LingStoneMake_Pei"

-- 14 项：mod=被动 Modifier；magic=主动神通按钮；lua=由 heal/def 计算
local SKILLS = {
	{ key = "gong",     label = "总纲",       mod = "WFG_Mod_YanTian_Pei_Gong" },
	{ key = "heal",     label = "自愈",       lua = true },
	{ key = "healPlus", label = "精研",       lua = true },
	{ key = "derive",   label = "解析",       lua = true },
	{ key = "create",   label = "创造",       lua = true },
	{ key = "fabao",    label = "本命法宝",   mod = "WFG_Mod_YanTian_Pei_Fabao" },
	{ key = "guard",    label = "避天机",     mod = "WFG_Mod_YanTian_Pei_Guard" },
	{ key = "lingStone",label = "炼石",       magic = true },
	{ key = "sword",    label = "御剑",       mod = "WFG_Mod_YanTian_Pei_Sword" },
	{ key = "shield",   label = "灵盾",       mod = "WFG_Mod_YanTian_Pei_Shield" },
	{ key = "codex",    label = "器谱",       mod = "WFG_Mod_YanTian_Pei_Codex" },
	{ key = "cycle",    label = "周天",       mod = "WFG_Mod_YanTian_Pei_Cycle" },
	{ key = "edge",     label = "锋锐",       mod = "WFG_Mod_YanTian_Pei_Edge" },
	{ key = "undying",  label = "不灭",       mod = "WFG_Mod_YanTian_Pei_Undying" },
}

local SKILL_BY_KEY = {}
for i = 1, #SKILLS do SKILL_BY_KEY[SKILLS[i].key] = SKILLS[i] end

local function freshState()
	return { npcs = {}, mods = {}, magic = {}, cleaned = {}, active = {} }
end

P.state = freshState()

local function delMod(npc, name)
	pcall(function() npc:RemoveModifier(name) end)
end

function P:Id(npc)
	return WFG.npc:Id(npc)
end

function P:Practice(npc)
	return WFG.npc:Practice(npc)
end

-- 衍天佩是普通 Tool 物品；优先用 WFG.item，再兜底扫道具槽 1001..1011。
function P:IsEquipped(npc)
	if npc == nil then return false end
	local ok, r = pcall(function() return WFG.item:IsEquipped(npc, P.ITEM) end)
	if ok and r == true then return true end
	for slot = 1001, 1011 do
		local okg, it = pcall(function() return npc.Equip:GetEquip(slot) end)
		if okg and it ~= nil then
			local okd, dn = pcall(function() return WFG.item:DefName(it) end)
			if okd and dn == P.ITEM then return true end
		end
	end
	return false
end

function P:IsLearned(npc, key)
	if npc == nil then return false end
	local d = WFG.YanTianDef
	if key == "gong" then
		return WFG.npc:GetGongName(npc) == (d and d.gong or "WFG_Gong_YanTian")
	end
	local s = SKILL_BY_KEY[key]
	if s == nil or d == nil or d.eso == nil or d.eso[key] == nil then return false end
	return WFG.npc:IsLearned(npc, d.eso[key]) == true
end

-- 佩戴 + 已学；治疗效果与费用的实时查询都走这里，不依赖 Modifier 是否加成功
function P:Active(npc, key)
	if npc == nil then return false end
	if not self:IsEquipped(npc) then return false end
	return self:IsLearned(npc, key)
end

function P:LearnedCount(npc)
	local n = 0
	for i = 1, #SKILLS do
		if self:IsLearned(npc, SKILLS[i].key) then n = n + 1 end
	end
	return n, #SKILLS
end

function P:UnlockSummary(npc)
	local names = {}
	for i = 1, #SKILLS do
		if self:Active(npc, SKILLS[i].key) then names[#names + 1] = SKILLS[i].label end
	end
	if #names == 0 then return "" end
	return table.concat(names, "、")
end

-- 只同步「可用性」：Modifier 与主动神通按钮；这里不施法、不扣灵气、不产石。
function P:Sync(npc)
	if npc == nil then return end
	local id = self:Id(npc)
	if id == nil then return end
	local st = self.state
	st.npcs[id] = npc
	st.mods[id] = st.mods[id] or {}
	st.magic[id] = st.magic[id] or {}

	local equipped = self:IsEquipped(npc)
	local first = not st.cleaned[id]
	local learnedCount = 0

	for i = 1, #SKILLS do
		local s = SKILLS[i]
		local learned = self:IsLearned(npc, s.key)
		if learned then learnedCount = learnedCount + 1 end
		local want = equipped and learned

		if s.mod ~= nil then
			-- 不信内存缓存：Modifier 可能被引擎（跨地图打包 ClearNoSyncModifier、
			-- 同名 RemoveModifier 全杀、死亡清理）外部撤掉，必须实测存活才跳过补挂。
			local alive = false
			local okf, mb = pcall(function() return npc.PropertyMgr:FindModifier(s.mod) end)
			if okf and mb ~= nil then
				local okv, v = pcall(function() return mb.IsVaild end)
				alive = (not okv) or v == true
			end
			if want then
				if not alive then
					local ok = pcall(function() npc:AddModifier(s.mod) end)
					if ok then st.mods[id][s.mod] = true end
				end
			elseif alive or st.mods[id][s.mod] or first then
				delMod(npc, s.mod)
				st.mods[id][s.mod] = nil
			end
		end
	end
	st.cleaned[id] = true

	-- 炼石：仅按钮可用性，绝不 MagicEnter / 自动施放
	local wantMagic = equipped and self:IsLearned(npc, "lingStone")
	local pr = self:Practice(npc)
	if pr ~= nil then
		local okh, has = pcall(function() return pr:CheckMagic(P.MAGIC) end)
		has = okh and has == true
		if wantMagic and not has then
			local oka = pcall(function() pr:AddMagic(P.MAGIC) end)
			if oka then has = true end
		elseif (not wantMagic) and has then
			pcall(function() pr:RemoveMagic(P.MAGIC) end)
			has = false
		end
		st.magic[id] = has
	end

	local was = st.active[id]
	local now = equipped and learnedCount > 0
	if now and not was then
		WFG:Log("[衍天佩] %s 已解锁 %d/%d 项", WFG.npc:GetName(npc), learnedCount, #SKILLS)
	end
	st.active[id] = now
end

function P:SyncAll()
	local list = WFG.npc.list or {}
	for i = 1, #list do
		pcall(function() P:Sync(list[i]) end)
	end
end

function P:Reset()
	self.state = freshState()
end

function P:ClearAll()
	local st = self.state
	for id, npc in pairs(st.npcs or {}) do
		for name in pairs(st.mods[id] or {}) do
			delMod(npc, name)
		end
		local pr = self:Practice(npc)
		if pr ~= nil then
			pcall(function() pr:RemoveMagic(P.MAGIC) end)
		end
	end
	self.state = freshState()
end

WFG.YanTian.pei = P

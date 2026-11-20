--[[
    衍天诀 · 模块注册与数据总闸
    - 维护每个修炼者的存档数据（境界、素材库、程序开关、法宝设置）
    - ontStageChange 时更新并广播给各子系统
    - 各子系统（heal/guard/derive/fabao/hall）只操作 M:Char(npc)
]]

WFG = WFG or {}

local M = {
	id      = "yantian",
	gong    = "WFG_Gong_YanTian",
	label   = "衍天诀",
	dataVer = 1,
}

M.store = M.store or { char = {}, world = {} }

local hallUnlock = {}   -- npcId -> true，已按「万法阁·衍天传人」经历解锁两座奇观
local HALL_EXP_PREFIX = "WFG_Exp_"   -- 任一「万法阁」开局经历（衍天传人 / 衍天遗泽）

-- 老存档补发：凝练衍天珠神通
local NING_MAGIC = "WFG_Magic_NingZhu"
local ningSynced = {}   -- npcId -> true，不入档

local ZHU_MAX = 4
local ZHU_USE = "WFG_Mod_YanTian_ZhuUse"
local ZHU_EQUIP = "WFG_Mod_YanTian_ZhuEquip"
local ZHU_WEAR_HP = 0.003   -- 佩带：每秒回复最大气血的 0.3%
local ZHU_WEAR_LING = 0.01  -- 佩带：每秒回复最大灵气的 1%

-- 法宝激活：槽位与旧档补条件缓存（均不入档）
-- 秘宝 Lable=Treasure 由 CheckEquipCell 的 default 分支放进道具槽 Tool1..Tool6（1001..1006）。
local FABAO_SLOTS = { 1, 2, 81, 82, 83, 84, 85, 1001, 1002, 1003, 1004, 1005, 1006 }
local fabaoCond = {}   -- npcId/itemId -> true
local fabaoWarned = {} -- 失败日志只报一次

local function D() return WFG.YanTianDef end

-- 保留空字段的拆分：素材存档段里 stuffs/quals 可能为空，
-- WFG:Split 会丢弃空段导致后续字段错位，这里单独实现。
local function splitKeep(s, sep)
	local out = {}
	s = tostring(s or "")
	local start = 1
	while true do
		local i = string.find(s, sep, start, true)
		if i == nil then
			out[#out + 1] = string.sub(s, start)
			break
		end
		out[#out + 1] = string.sub(s, start, i - 1)
		start = i + #sep
	end
	return out
end

------------------------------------------------------------------------
-- 数据
------------------------------------------------------------------------
function M:Char(npc, create)
	local id = WFG.npc:Id(npc)
	if id == nil then return nil end
	local c = self.store.char[id]
	if c == nil and create then
		c = {
			stage = 0,
			lib   = {},   -- [defName] = { q = 品级, lv = 等阶 }
			heal  = 0,    -- 自愈程序开关
			guard = 0,    -- 避天机开关（学没学会看秘籍，这里是玩家是否启用主动渡劫入口）
			zhu   = 0,    -- 已服用的衍天珠（0..4，每层 +25% 根本灵气）
			ld    = 0,    -- 灵道剑：存入剑中的道行（属于修士自身，换剑/易主不迁移）
			fabao = { mode = 1, x = 0, limit = 0, used = 0, burst = 0 },
		}
		self.store.char[id] = c
	end
	return c
end

function M:CharById(id)
	return self.store.char[tostring(id)]
end

function M:LibCount(c)
	local n = 0
	if c == nil or type(c.lib) ~= "table" then return 0 end
	for _ in pairs(c.lib) do n = n + 1 end
	return n
end

------------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------------
function M:OnInit()
	WFG:Log("衍天诀模块注册完成")
end

function M:OnEnter()
	WFG:Log("衍天诀进入世界")
	local h = WFG.YanTian.heal
	if h and h.ClearAll then h:ClearAll() end
	local p = WFG.YanTian.pei
	if p and p.Reset then p:Reset() end
	self:EnsureStep()
end

-- 自愈程序要每帧刷新回灵速率：地脉吸灵（LingMapData，16Hz）会覆盖 DynamicLing
function M:EnsureStep()
	if self._frame ~= nil then return end
	if type(WFG.OnStep) ~= "function" then return end
	self._frame = function(dt) M:OnStep(dt) end
	WFG:OnStep(self._frame)
end

function M:OnStep(dt)
	local h = WFG.YanTian and WFG.YanTian.heal
	if h and h.Frame then h:Frame(dt) end
end

function M:OnStageChange(npc, gong, fromLv, toLv)
	if gong ~= self.gong then return end
	local c = self:Char(npc, true)
	if c == nil then return end
	c.stage = toLv
	local def = D()
	local nm = def and def.stageName[toLv] or ("第" .. tostring(toLv) .. "境")
	WFG:Log("衍天诀：%s 由 %d 境 -> %d 境（%s）",
		tostring(npc:GetName()), fromLv or 0, toLv, nm)
	local p = WFG.YanTian and WFG.YanTian.pei
	if p and p.Sync then p:Sync(npc) end
end

-- 学会衍天诀却缺「凝练衍天珠」神通的老档，补上（每秒至多一次/人）
function M:EnsureNingMagic(npc)
	local id = WFG.npc:Id(npc)
	if id == nil or ningSynced[id] then return end
	if WFG.npc:GetGongName(npc) ~= self.gong then return end
	local pr = WFG.npc:Practice(npc)
	if pr == nil then return end
	local okh, has = pcall(function() return pr:CheckMagic(NING_MAGIC) end)
	if okh and has == true then
		ningSynced[id] = true
		return
	end
	local oka = pcall(function() pr:AddMagic(NING_MAGIC) end)
	if oka then
		ningSynced[id] = true
		WFG:Log("衍天诀：为 %s 补发神通「凝练衍天珠」", WFG.npc:GetName(npc))
	end
end


-- 经历解锁奇观：NpcExperienceDef 没有 Buildings 字段，Gongs/Esoterics 也不会建筑解锁，
-- 因此遍历 ExperienceList，命中任一「万法阁」经历（WFG_Exp_ 前缀）后调 WorldLua 的 UnLockBuilding。
function M:EnsureHallUnlock(npc)
	local id = WFG.npc:Id(npc)
	if id == nil or hallUnlock[id] then return end
	local okL, list = pcall(function() return npc.PropertyMgr.ExperienceList end)
	if not (okL and list ~= nil) then return end
	local okC, cnt = pcall(function() return list.Count end)
	if not (okC and type(cnt) == "number") then return end
	local has = false
	for i = 0, cnt - 1 do
		local okN, ex = pcall(function() return list[i] end)
		if okN and ex ~= nil then
			local okn, nm = pcall(function() return ex.Name end)
			if okn and type(nm) == "string" and nm:sub(1, #HALL_EXP_PREFIX) == HALL_EXP_PREFIX then has = true break end
		end
	end
	if not has then return end
	local wl = WorldLua or world
	if wl == nil then return end
	local def = D()
	if def == nil or def.build == nil then return end
	local all = { def.build.hallMat, def.build.hallEng }
	local done = 0
	for i = 1, #all do
		local name = all[i]
		local okq, already = pcall(function() return wl:IsBuildingUnlocked(name) end)
		local oku, err = pcall(function() wl:UnlockBuilding(name) end)
		if oku then
			done = done + 1
			if okq and already == false then
				WFG:Log("[奇观] 经历解锁建筑：%s", tostring(name))
			end
		else
			local key = "unlock:" .. tostring(name)
			if not fabaoWarned[key] then
				fabaoWarned[key] = true
				WFG:Error("build.unlock", tostring(err))
			end
		end
	end
	if done == #all then hallUnlock[id] = true end
end

-- GetModifierStack 只注册在 NpcLuaHelper 上，原始 Npc 没有这个方法；
-- 直接 npc:GetModifierStack 会抛「方法不存在」并被 pcall 吞掉，结果永远是 0。
local function zhuStack(npc, name)
	local h = WFG.npc:Helper(npc)
	if h == nil then return 0 end
	local ok, v = pcall(function() return h:GetModifierStack(name) end)
	if not ok or type(v) ~= "number" then return 0 end
	return math.floor(v)
end

-- 衍天珠：4 段永久根本灵气，按 c.zhu 逐层补齐/移除
function M:SyncZhuMods(npc, c)
	if npc == nil or c == nil then return end
	local want = math.floor(tonumber(c.zhu) or 0)
	if want < 0 then want = 0 end
	if want > ZHU_MAX then want = ZHU_MAX end
	c.zhu = want
	c._zhuOn = c._zhuOn or {}
	for i = 1, ZHU_MAX do
		local name = "WFG_Mod_YanTian_ZhuLing" .. i
		if i <= want then
			if c._zhuOn[i] ~= true then
				local ok = pcall(function() npc:AddModifier(name) end)
				if ok then c._zhuOn[i] = true end
			end
		elseif c._zhuOn[i] == true then
			pcall(function() npc:RemoveModifier(name) end)
			c._zhuOn[i] = false
		end
	end
end

-- 衍天珠：结算服用标记。每次服用恢复 10% 最大灵气；前 4 次各永久 +25% 根本灵气
function M:TickZhu(npc)
	if npc == nil then return end
	local stack = zhuStack(npc, ZHU_USE)

	local c = self:Char(npc, false)
	if stack > 0 then
		c = c or self:Char(npc, true)
		local before = c and (math.floor(tonumber(c.zhu) or 0)) or 0
		for _ = 1, stack do
			local maxLing = 0
			pcall(function() maxLing = WFG:MaxLing(npc) or 0 end)
			local gain = math.floor(maxLing * 0.10 + 0.5)
			if gain > 0 then pcall(function() npc:AddLing(gain) end) end
			if c ~= nil then
				local zhu = math.floor(tonumber(c.zhu) or 0)
				if zhu < ZHU_MAX then
					c.zhu = zhu + 1
					self:SyncZhuMods(npc, c)
				end
			end
		end
		pcall(function() npc:RemoveModifier(ZHU_USE) end)
		if c ~= nil then
			WFG:Log("[衍天珠] %s 服用 %d 颗，根本灵气层数 %d -> %d",
				WFG.npc:GetName(npc), stack, before, c.zhu or 0)
		end
	end

	c = c or self:Char(npc, false)
	if c ~= nil then self:SyncZhuMods(npc, c) end
end

-- 衍天珠：佩带时的缓慢恢复。伤势交给引擎（Modifier 里的 RecoveryPower 走自然恢复），
-- 这里只补引擎没有的两项：持续回气血、持续回灵气。
function M:TickZhuWear(npc)
	if npc == nil then return end
	if zhuStack(npc, ZHU_EQUIP) <= 0 then return end
	local dead = false
	pcall(function() dead = npc.IsDeath == true end)
	if dead then return end

	local maxHp = WFG:Prop(npc, "MaxHp", 0)
	local hp = WFG:Prop(npc, "Hp", 0)
	if maxHp > 0 and hp < maxHp - 0.01 then
		local add = maxHp * ZHU_WEAR_HP
		if add > maxHp - hp then add = maxHp - hp end
		if add > 0 then pcall(function() npc:AddHealth(add) end) end
	end

	local maxLing = WFG:MaxLing(npc) or 0
	if maxLing > 0 then
		pcall(function() npc:AddLing(maxLing * ZHU_WEAR_LING) end)
	end
end

-- 取法宝槽里的物品（槽位不存在时返回 nil）
local function fabaoAt(npc, slot)
	-- 入口是 NpcEquipData；Npc.GetEquip 也等价转发，但槽位必须包含道具槽 1001..1006。
	local ok, it = pcall(function() return npc.Equip:GetEquip(slot) end)
	if ok then return it end
	return nil
end

local function isOurFabao(dn)
	local def = D()
	if def == nil or def.item == nil or dn == nil then return false end
	return dn == def.item.hallMat or dn == def.item.hallEng or dn == def.item.lingDao
end

-- 兼容认主后的通用 FightFaBao：原定义名保存在 Fabao.Oitem 上
local function matchOurFabao(it)
	local okd, dn = pcall(function() return WFG.item:DefName(it) end)
	if okd and isOurFabao(dn) then return dn end
	local okf, fb = pcall(function() return it.Fabao end)
	if okf and fb ~= nil then
		local oko, oi = pcall(function() return fb.Oitem end)
		if oko and isOurFabao(oi) then return oi end
	end
	return nil
end

-- 旧档兜底：正常情况下 ItemThing.OnInit 读档会按 XML 的 ActiveCondition 重建 Actives；
-- 若某把未认主的剑仍为空，这里补一条 Other「修行衍天诀」，非衍天诀永远停在 0/1。
function M:EnsureFabaoCond(npc)
	if npc == nil then return end
	for i = 1, #FABAO_SLOTS do
		local it = fabaoAt(npc, FABAO_SLOTS[i])
		if it ~= nil then
			local dn = matchOurFabao(it)
			if dn ~= nil then
				local key = "cond:" .. tostring(WFG.npc:Id(npc)) .. ":" .. tostring(i)
				local okid, iid = pcall(function() return it.ID end)
				if okid and iid ~= nil then key = "cond:" .. tostring(iid) end
				if not fabaoWarned["seen:" .. tostring(iid)] then
					fabaoWarned["seen:" .. tostring(iid)] = true
					WFG:Log("[法宝] 检测到 %s 的 %s（槽位 %d）", WFG.npc:GetName(npc), tostring(dn), FABAO_SLOTS[i])
				end
				if not fabaoCond[key] then
					local oke, emb = pcall(function() return it.FabaoAcriveData end)
					if oke and emb ~= nil then
						local okl, list = pcall(function() return emb.Actives end)
						if okl and list ~= nil then
							local okc, count = pcall(function() return list.Count end)
							local hasOther = false
							if okc and type(count) == "number" then
								for j = 0, count - 1 do
									local okj, nad = pcall(function() return list[j] end)
									if okj and nad ~= nil then
										local okad, ad = pcall(function() return nad.def end)
										if okad and ad ~= nil then
											local okev, ev = pcall(function() return ad.eventid end)
											if okev and ev == CS.XiaWorld.FabaoEvenType.Other then
												hasOther = true
												break
											end
										end
									end
								end
							end
							if hasOther then
								fabaoCond[key] = true
							else
								local okAdd, err = pcall(function()
									local ad = CS.XiaWorld.FabaoActiveData()
									ad.eventid = CS.XiaWorld.FabaoEvenType.Other
									ad.des = "修行衍天诀"
									ad.needcount = 1
									ad.needday = 0
									pcall(function() ad:Init() end)
									local nad = CS.XiaWorld.NpcFabaoActiveData()
									nad.def = ad
									list:Add(nad)
								end)
								if okAdd then
									fabaoCond[key] = true
									WFG:Log("[法宝] 为 %s 的 %s 补上「修行衍天诀」激活条件", WFG.npc:GetName(npc), tostring(dn))
								elseif not fabaoWarned[key] then
									fabaoWarned[key] = true
									WFG:Error("fabao.cond", tostring(err))
								end
							end
						end
					end
				end
			end
		end
	end
end

-- 已认主前：修行衍天诀者每秒推进一次 Other 条件；非衍天诀不推进。
function M:TickFabao(npc)
	if npc == nil then return end
	local isYan = false
	pcall(function() isYan = WFG.npc:GetGongName(npc) == self.gong end)
	if not isYan then return end
	for i = 1, #FABAO_SLOTS do
		local it = fabaoAt(npc, FABAO_SLOTS[i])
		if it ~= nil then
			local dn = matchOurFabao(it)
			if dn ~= nil then
				local oke, emb = pcall(function() return it.FabaoAcriveData end)
				if oke and emb ~= nil then
					local oki, iid = pcall(function() return it.ID end)
					local seenKey = "tickseen:" .. tostring(oki and iid or i)
					if not fabaoWarned[seenKey] then
						fabaoWarned[seenKey] = true
						WFG:Log("[法宝] %s 的 %s（%s）已读到激活数据", WFG.npc:GetName(npc), tostring(dn), tostring(iid))
					end
					local okc, can = pcall(function() return emb:CanActive() end)
					if okc and can == false then
						-- 我们的 Other 已经满格时不再重复调用，避免刷日志
						local okf, otherDone = pcall(function()
							local list = emb.Actives
							for j = 0, list.Count - 1 do
								local nad = list[j]
								if nad.def.eventid == CS.XiaWorld.FabaoEvenType.Other then
									return nad.Count >= nad.GetActiveMax
								end
							end
							return false
						end)
						if not (okf and otherDone) then
							local okS, done = pcall(function()
								return CS.XiaWorld.FabaoEventMgr.SetFabaoActive(it, CS.XiaWorld.FabaoEvenType.Other, 1)
							end)
							if okS and done == true then
								WFG:Log("[法宝] %s 的 %s 激活条件推进：修行衍天诀 1/1", WFG.npc:GetName(npc), tostring(dn))
							else
								local key = "tick:" .. tostring(WFG.npc:Id(npc)) .. ":" .. tostring(i)
								if not fabaoWarned[key] then
									fabaoWarned[key] = true
									WFG:Error("fabao.active", tostring(done))
								end
							end
						end
					end
				end
			end
		end
	end
end

-- 佩带已认主灵源剑的衍天诀修士，在角色指令栏获得「衍天能源中心」按钮，点击直接开管理窗。
local ENERGY_BTN_NAME = "衍天能源中心"
function M:EnsureEnergyButton(npc)
	if npc == nil then return end
	local hall = WFG.YanTian and WFG.YanTian.hall
	if hall == nil then return end
	local want = hall:CanUseEng(npc)
	local has = false
	local okN, n = pcall(function() return npc:GetLuaBtnCount() end)
	if okN and type(n) == "number" then
		for i = 0, n - 1 do
			local okD, d = pcall(function() return npc:GetLuaBtnData(i) end)
			if okD and d ~= nil and d.name == ENERGY_BTN_NAME then has = true break end
		end
	end
	if want and not has then
		pcall(function()
			npc:AddSaveBtnData(ENERGY_BTN_NAME, "res/Sprs/ui/icon_hand",
				"WFG.ui.hallEng:OpenNpc(bind)",
				"管理与衍天能源中心的灵气存取参数。")
		end)
	elseif (not want) and has then
		pcall(function() npc:RemoveBtnData(ENERGY_BTN_NAME) end)
	end
end

	-- 灵道剑：把自身道行存入剑中，换取无上限的法宝威力加成
	--
	-- 加成只能走 NPC 属性 NpcFight_FabaoPowerAddP（FabaoBase.GetPower 会乘 1+该值）：
	-- FabaoData 没有 XLua 包装（XLua_Gen 只注册 ItemThing），it.Fabao 取 metatable 就会抛异常，
	-- 单件法宝的 AttackPower 在 Lua 侧改不了。修正器「先移除、再按 scale 加回」即精确设值，
	-- 每秒复核一次，换剑 / 转功法 / 读档均幂等。
	local LINGDAO_BTN = "灵道剑"

	local function lingDaoCfg()
		local def = D()
		return (def and def.lingDao) or {}
	end

	-- 只读基础道行（不含 AbilityLvAddV 加值），避免钳制按含加值的数算、扣的却是基础值
	local function daoHangOf(p)
		if p == nil then return 0 end
		local v = nil
		pcall(function() v = tonumber(p.DaoHang) end)
		if v == nil then
			local ok, g = pcall(function() return p:GetDaoHang() end)
			if ok then v = tonumber(g) end
		end
		v = tonumber(v) or 0
		if v < 0 then v = 0 end
		return math.floor(v)
	end

	function M:LingDaoAddp(ld)
		local rate = tonumber(lingDaoCfg().rate) or 0.01
		ld = math.floor(tonumber(ld) or 0)
		if ld <= 0 then return 0 end
		return ld * rate
	end

	function M:LingDaoStored(npc)
		if npc == nil then return 0 end
		local id = WFG.npc:Id(npc)
		local c = id and self.store.char[id]
		return (c and tonumber(c.ld)) or 0
	end

	function M:HasLingDaoEquipped(npc)
		if npc == nil then return false end
		local def = D()
		local target = def and def.item and def.item.lingDao
		if target == nil then return false end
		for i = 1, #FABAO_SLOTS do
			local it = fabaoAt(npc, FABAO_SLOTS[i])
			if it ~= nil and matchOurFabao(it) == target then return true end
		end
		return false
	end

	-- 生效条件：衍天诀 + 灵道剑在法宝格（认主由 EnsureFabaoCond / TickFabao 维护）
	function M:LingDaoActive(npc)
		if npc == nil then return false end
		local ok, g = pcall(function() return WFG.npc:GetGongName(npc) end)
		if not ok or g ~= self.gong then return false end
		return self:HasLingDaoEquipped(npc)
	end

	function M:SyncLingDao(npc, force)
		if npc == nil then return end
		local cfg = lingDaoCfg()
		local name = cfg.mod
		if name == nil then return end
		local c = self:Char(npc, true)
		if c == nil then return end
		local want = 0
		if self:LingDaoActive(npc) then want = self:LingDaoAddp(c.ld) end
		local cur = tonumber(c.ldAddp) or 0
		local eps = tonumber(cfg.eps) or 0.005
		if (not force) and math.abs(want - cur) < eps then return end
		pcall(function() npc:RemoveModifier(name) end)
		if want > 0 then
			-- XML 里 AddV=1，scale 直接就是「+want」（want=5 即 +500%）
			local ok, err = pcall(function() npc.PropertyMgr:AddModifier(name, want) end)
			if not ok then
				WFG:Error("yantian.lingdao", "修正器写入失败：" .. tostring(err))
				return
			end
		end
		c.ldAddp = (want > 0) and want or nil
	end

	function M:DepositLingDao(npc, n)
		if npc == nil then return 0, "没有角色" end
		if not self:LingDaoActive(npc) then return 0, "需佩带并认主灵道剑" end
		n = math.floor(tonumber(n) or 0)
		if n <= 0 then return 0, "请先选择要存入的道行" end
		local c = self:Char(npc, true)
		if c == nil then return 0, "无法读取角色数据" end
		local p = WFG.npc:Practice(npc)
		if p == nil then return 0, "无法读取道行" end
		local base = daoHangOf(p)
		if base <= 0 then return 0, "没有可存入的道行" end
		if n > base then n = base end
		WFG:Safe(function() p:AddDaoHang(-n) end)
		local moved = base - daoHangOf(p)
		if moved <= 0 then return 0, "没有可存入的道行" end
		c.ld = math.max(0, (tonumber(c.ld) or 0) + moved)
		self:SyncLingDao(npc, true)
		return moved
	end

	function M:WithdrawLingDao(npc, n)
		if npc == nil then return 0, "没有角色" end
		local c = self:Char(npc, true)
		if c == nil then return 0, "无法读取角色数据" end
		local cap = math.max(0, math.floor(tonumber(c.ld) or 0))
		if cap <= 0 then return 0, "剑中没有存道" end
		n = math.floor(tonumber(n) or 0)
		if n <= 0 then return 0, "请先选择要取回的道行" end
		if n > cap then n = cap end
		local p = WFG.npc:Practice(npc)
		if p == nil then return 0, "无法读取道行" end
		local before = daoHangOf(p)
		WFG:Safe(function() p:AddDaoHang(n) end)
		local moved = daoHangOf(p) - before
		if moved <= 0 then return 0, "取回道行失败" end
		c.ld = math.max(0, cap - moved)
		self:SyncLingDao(npc, true)
		return moved
	end

	function M:TickLingDao(npc)
		local id = WFG.npc:Id(npc)
		local c = id and self.store.char[id]
		if c == nil and not self:HasLingDaoEquipped(npc) then return end
		self:SyncLingDao(npc, false)
	end

	-- 佩带灵道剑、或剑外仍有存道时，角色指令栏出现「灵道剑」；
	-- 后者保证剑被毁 / 转手后仍能把道行取回来。
	function M:EnsureLingDaoButton(npc)
		if npc == nil then return end
		local want = self:HasLingDaoEquipped(npc) or self:LingDaoStored(npc) > 0
		local has = false
		local okN, n = pcall(function() return npc:GetLuaBtnCount() end)
		if okN and type(n) == "number" then
			for i = 0, n - 1 do
				local okD, d = pcall(function() return npc:GetLuaBtnData(i) end)
				if okD and d ~= nil and d.name == LINGDAO_BTN then has = true break end
			end
		end
		if want and not has then
			pcall(function()
				npc:AddSaveBtnData(LINGDAO_BTN, "res/Sprs/ui/icon_hand",
					"WFG.ui.lingdao:OpenNpc(bind)",
					"存入或取回自身道行；每 1 点存道 +1% 法宝威力，无上限。")
			end)
		elseif (not want) and has then
			pcall(function() npc:RemoveBtnData(LINGDAO_BTN) end)
		end
	end

	-- 旧档兼容：秘籍的 <Fabaos> 只在「学会的那一刻」写进角色（EsotericaMgr.cs:466-472），
	-- 已学过总纲的旧档角色不会因 XML 新增配方而拿到灵道剑，这里按「是否学过总纲」补发。
	-- LearnFabaoFormulas 本身幂等（已存在返回 false），所以每秒调用没有副作用。
	function M:EnsureFabaoFormula(npc)
		if npc == nil then return end
		if WFG.npc:GetGongName(npc) ~= self.gong then return end
		local okP, p = pcall(function() return WFG.npc:Practice(npc) end)
		if not (okP and p) then return end
		local cfg = lingDaoCfg()
		-- 正确判定：参悟树节点（LearnedTreeV 以 <Node Name> 为键，实时更新）
		local okT, learned = pcall(function() return p:IsLearnedTreeUnit(cfg.tree) end)
		if not (okT and learned) then
			-- 兜底：总纲也可能是通过秘籍物品学到的，再按秘籍定义名试一次
			local okE, e = pcall(function() return p:CheckIsLearnEsotericaDisplayName(cfg.eso) end)
			if not (okE and e) then
				local c = self:Char(npc)
				if c and not c.ldDiag then
					c.ldDiag = true
					print("[WFG] 灵道剑：" .. tostring(npc:GetName()) .. " 未检测到总纲（tree=" .. tostring(okT and learned) .. "），跳过配方补发")
				end
				return
			end
		end
		local okL, added = pcall(function() return p:LearnFabaoFormulas(cfg.formula) end)
		if okL and added then
			print("[WFG] 灵道剑：已为 " .. tostring(npc:GetName()) .. " 补学炼制配方")
		end
	end

function M:OnSecond()
	self:EnsureStep()
	local list = WFG.npc.list or {}
	for i = 1, #list do
		self:EnsureHallUnlock(list[i])
		self:EnsureNingMagic(list[i])
		self:TickZhu(list[i])
		self:TickZhuWear(list[i])
		self:EnsureFabaoCond(list[i])
		self:TickFabao(list[i])
		self:EnsureEnergyButton(list[i])
		self:TickLingDao(list[i])
		self:EnsureLingDaoButton(list[i])
		self:EnsureFabaoFormula(list[i])
	end
	-- 衍天佩：只同步被动与主动神通按钮，不施法
	local pei = WFG.YanTian and WFG.YanTian.pei
	if pei and pei.SyncAll then pei:SyncAll() end
	-- 统一分发到各子系统（各自内部再做境界/秘籍判定，避免这里写死规则）
	if WFG.YanTian.heal and WFG.YanTian.heal.Second then
		WFG.YanTian.heal:Second(self)
	end
	if WFG.YanTian.guard and WFG.YanTian.guard.Second then
		WFG.YanTian.guard:Second(self)
	end
	if WFG.YanTian.hall and WFG.YanTian.hall.Second then
		WFG.YanTian.hall:Second(self)
	end
end

function M:OnLeave()
	if self._frame ~= nil and type(WFG.RemoveStep) == "function" then
		WFG:RemoveStep(self._frame)
	end
	self._frame = nil
	hallUnlock = {}
	ningSynced = {}
	fabaoCond = {}
	fabaoWarned = {}
	if WFG.YanTian and WFG.YanTian.hall and WFG.YanTian.hall.ClearAllBuffs then
		WFG.YanTian.hall:ClearAllBuffs(self)
	end
	local h = WFG.YanTian and WFG.YanTian.heal
	if h and h.ClearAll then h:ClearAll() end
	local p = WFG.YanTian and WFG.YanTian.pei
	if p and p.ClearAll then p:ClearAll() end
	WFG.npc:ClearCache()
end

function M:OnSave()
	-- 只写纯数据；素材库为紧凑字符串数组，取时再拆
	local charOut = {}
	for id, c in pairs(self.store.char) do
		local lib = {}
		for defName, v in pairs(c.lib or {}) do
			local nm = tostring(v.name or ""):gsub("|", "/"):gsub(",", ";")
			local stuffs = {}
			for st in pairs(v.stuffs or {}) do stuffs[#stuffs + 1] = st end
			table.sort(stuffs)
			local quals = {}
			for q in pairs(v.quals or {}) do quals[#quals + 1] = tostring(q) end
			table.sort(quals)
			-- 兼容旧档：没有 quals 集合时用单值 q 补一个
			if #quals == 0 and v.q ~= nil then quals[1] = tostring(v.q) end
			lib[#lib + 1] = table.concat({
				defName, tostring(v.q or 1), tostring(v.lv or 0), nm,
				table.concat(stuffs, ","), table.concat(quals, ","),
				(v.own == false) and "0" or "1",
			}, "|")
		end
		table.sort(lib)
		charOut[id] = {
			stage = c.stage or 0,
			lib   = lib,
			heal  = c.heal or 0,
			guard = c.guard or 0,
			zhu   = c.zhu or 0,
			ld    = c.ld or 0,
			path  = c.path,
			fabao = {
				mode  = (c.fabao and c.fabao.mode) or 1,
				x     = (c.fabao and c.fabao.x) or 0,
				limit = (c.fabao and c.fabao.limit) or 0,
				used  = (c.fabao and c.fabao.used) or 0,
				burst = (c.fabao and c.fabao.burst) or 0,
			},
			terminal = {
				mat = (c.terminal and c.terminal.mat) or false,
				eng = (c.terminal and c.terminal.eng) or false,
			},
		}
	end
	local worldOut = { hallMat = {}, hallEng = {} }
	for k, v in pairs(self.store.world or {}) do
		worldOut[k] = v
	end
	return { char = charOut, world = worldOut }
end

function M:OnLoad(tb)
	self.store = { char = {}, world = {} }
	hallUnlock = {}
	ningSynced = {}
	fabaoCond = {}
	fabaoWarned = {}
	if type(tb) ~= "table" then return end
	local chars = tb.char or {}
	for id, c in pairs(chars) do
		local lib = {}
		for _, s in ipairs(c.lib or {}) do
			local parts = splitKeep(tostring(s), "|")
			if #parts >= 3 then
				local q = tonumber(parts[2]) or 1
				local e = {
					q = q,
					maxq = q,
					lv = tonumber(parts[3]) or 0,
					name = parts[4],
					n = 0,
					stuffs = {},
					quals = {},
				}
				if parts[7] == "0" then e.own = false end
				e.quals[q] = true
				if parts[5] ~= nil and parts[5] ~= "" then
					for _, st in ipairs(WFG:Split(parts[5], ",")) do
						if st ~= "" then e.stuffs[st] = true end
					end
				end
				if parts[6] ~= nil and parts[6] ~= "" then
					for _, qq in ipairs(WFG:Split(parts[6], ",")) do
						local v = tonumber(qq)
						if v ~= nil then e.quals[v] = true end
					end
				end
				lib[parts[1]] = e
			elseif #parts == 1 then
				lib[parts[1]] = { q = 1, maxq = 1, lv = 0, n = 0, stuffs = {}, quals = { [1] = true } }
			end
		end
		self.store.char[tostring(id)] = {
			stage = c.stage or 0,
			lib   = lib,
			heal  = c.heal or 0,
			guard = c.guard or 0,
			zhu   = c.zhu or 0,
			ld    = tonumber(c.ld) or 0,
			path  = c.path,
			fabao = c.fabao or { mode = 1, x = 0, limit = 0, used = 0, burst = 0 },
			terminal = c.terminal or {},
		}
	end
	self.store.world = tb.world or { hallMat = {}, hallEng = {} }
end

function M:OnAfterLoad()
	-- 对象重建：总库建筑实体在 world 子系统里按 ID 重新解析
	hallUnlock = {}
	ningSynced = {}
	fabaoCond = {}
	fabaoWarned = {}
	-- 修正器缓存不入档：读档后按存道重算，避免旧档残留导致重复加成
	for _, c in pairs(self.store.char) do c.ldAddp = nil; c.ldDiag = nil end
	WFG.npc:ClearCache()
end

------------------------------------------------------------------------
-- 注册（加载顺序无关）
------------------------------------------------------------------------
if type(WFG.Register) == "function" then
	WFG:Register(M)
else
	WFG.pending = WFG.pending or {}
	table.insert(WFG.pending, M)
end

return M

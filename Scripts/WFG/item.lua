--[[
    万法阁 · 物品服务
    统一封装「取定义 / 等阶 / 品级 / 名称 / 造物 / 佩戴判定」，把不确定的引擎差异收在这一层。

    造物走 World.map:DropItems（游戏原生 Lua 用法，见 BuildingDiMu.lua），
    它会创建物品并直接落在目标格，避免「造出来但不在世界里」的空物。
]]

WFG = WFG or {}
WFG.item = WFG.item or {}
local I = WFG.item

I.warned = I.warned or {}

local function warnOnce(key, msg)
	if not I.warned[key] then
		I.warned[key] = true
		WFG:Error("item." .. key, msg)
	end
end

local function safeGet(obj, key)
	if obj == nil then return nil end
	local ok, v = pcall(function() return obj[key] end)
	if ok then return v end
	return nil
end

-- 是否纯 ASCII（用来识别「英文键名冒充显示名」）
local function isAscii(s)
	if type(s) ~= "string" or s == "" then return false end
	return s:find("^[\32-\126]+$") ~= nil
end

-- 由物品对象取定义名
function I:DefName(thing)
	if thing == nil then return nil end
	local v = safeGet(thing, "DefName")
	if type(v) == "string" then return v end
	v = safeGet(thing, "defName")
	if type(v) == "string" then return v end
	local d = safeGet(thing, "def")
	if d ~= nil then
		v = safeGet(d, "Name")
		if type(v) == "string" then return v end
	end
	d = safeGet(thing, "Def")
	if d ~= nil then
		v = safeGet(d, "Name")
		if type(v) == "string" then return v end
	end
	return nil
end

-- 实体显示名：走引擎原生 GetName()（物品浮窗标题同源，见 Wnd_TipPopPanel.cs:410）
-- 玩家制成品在创建时会把「材质+类型」写进 m_szName，GetName() 才拿得到，
-- 直接读 def.ThingName 只能拿到内部键名。
function I:ThingName(thing)
	if thing == nil then return nil end
	local ok, v = pcall(function() return thing:GetName() end)
	if ok and type(v) == "string" and v ~= "" and not isAscii(v) then return v end
	if not I.diagName then
		I.diagName = true
		WFG:Log("[item] GetName 诊断：ok=%s value=%s err=%s",
			tostring(ok), tostring(ok and v or ""), tostring(ok and "" or v))
		-- 备用路径：实体上的 Name 属性 / def.ThingName
		local n1 = safeGet(thing, "Name")
		local d1 = safeGet(thing, "def")
		local d2 = safeGet(thing, "Def")
		WFG:Log("[item] 实体 Name=%s def=%s Def=%s", tostring(n1), tostring(d1 ~= nil), tostring(d2 ~= nil))
		for _, d in ipairs({ d1, d2 }) do
			if d ~= nil then
				WFG:Log("[item] def.Name=%s def.ThingName=%s",
					tostring(safeGet(d, "Name")), tostring(safeGet(d, "ThingName")))
			end
		end
	end
	-- 备用 1：实体自带的 Name 属性
	local n = safeGet(thing, "Name")
	if type(n) == "string" and n ~= "" and not isAscii(n) then return n end

	-- 备用 2：直接读实体身上的定义（Thing.def 是 property，XiaWorld/Thing.cs:248）
	for _, key in ipairs({ "def", "Def" }) do
		local d = safeGet(thing, key)
		if d ~= nil then
			for _, f in ipairs({ "ThingName", "DisplayName", "Name" }) do
				local v = safeGet(d, f)
				if type(v) == "string" and v ~= "" and not isAscii(v) then return v end
			end
		end
	end

	local dn = self:DefName(thing)
	if dn ~= nil then return self:Show(dn) end
	return nil
end

-- 物品的展示元数据：大分类 / 品阶 / 五行
-- def.Item.Kind 是 g_emItemKind 枚举（ItemData.cs:9）
-- def.ElementKind 是 g_emElementKind 枚举（None,Jin,Mu,Shui,Huo,Tu,Chaos）
-- def.Level 是 1..12 的品阶
local KIND_MAP = { material = "mat", equipment = "equip", consumable = "cons", practice = "prac" }
local EL_MAP = { jin = "jin", mu = "mu", shui = "shui", huo = "huo", tu = "tu" }

local function enumName(v)
	if v == nil then return "" end
	local ok, t = pcall(function() return tostring(v) end)
	if not ok or t == nil then return "" end
	return string.lower(t)
end

local function guessKind(defName)
	local n = tostring(defName or "")
	if n:find("Dan", 1, true) or n:find("Pill", 1, true) then return "cons" end
	if n:find("Weapon", 1, true) or n:find("Armor", 1, true) or n:find("Equipment", 1, true) then return "equip" end
	if n:find("Symbol", 1, true) or n:find("Talisman", 1, true) or n:find("Fabao", 1, true) then return "prac" end
	if n:find("Material", 1, true) or n:find("Wood", 1, true) or n:find("Stone", 1, true) or n:find("Ore", 1, true) then return "mat" end
	return "misc"
end

function I:Meta(defName)
	I.metaCache = I.metaCache or {}
	local hit = I.metaCache[defName]
	if hit ~= nil then return hit end

	local m = { kind = guessKind(defName), lv = 1, el = "none" }
	local def = I:Def(defName)
	if def ~= nil then
		pcall(function()
			local k = enumName(def.Item and def.Item.Kind)
			if k ~= "" then m.kind = KIND_MAP[k] or m.kind end
		end)
		pcall(function()
			local lv = tonumber(def.Level)
			if lv ~= nil and lv > 0 then m.lv = lv end
		end)
		pcall(function()
			local e = enumName(def.ElementKind)
			if e ~= "" then m.el = EL_MAP[e] or "none" end
		end)
	end
	if not I.metaDiag then
		I.metaDiag = true
		WFG:Log("[item] meta 诊断：%s -> kind=%s lv=%s el=%s", tostring(defName), m.kind, tostring(m.lv), m.el)
	end
	I.metaCache[defName] = m
	return m
end

-- 取物品/建筑定义（ThingMgr:GetDef 是唯一真实存在的入口）
-- g_emThingType: None=0 Npc=1 Item=2 Plant=3 Building=4 Space=5 CMD=6
-- 第三个参数 lost 必须传 false，否则查不到时会返回「遗失物品」占位定义。
function I:Def(defName)
	if type(defName) ~= "string" or defName == "" then return nil end
	I.defCache = I.defCache or {}
	local hit = I.defCache[defName]
	if hit ~= nil then return hit or nil end

	local def = nil
	local errs = {}
	-- XLua 不接受 int，必须传真正的枚举值
	local T = {}
	pcall(function()
		local e = CS.XiaWorld.g_emThingType
		T = { e.Item, e.Building, e.Plant }
	end)
	if #T == 0 then T = { 2, 4, 3 } end
	for _, t in ipairs(T) do
		local ok, err = pcall(function()
			def = ThingMgr:GetDef(t, defName, false)
			if def == nil then def = ThingMgr:GetDef(t, defName) end
		end)
		if not ok then errs[#errs + 1] = tostring(err) end
		if def ~= nil then break end
	end
	if def == nil and not I.defDiag then
		I.defDiag = true
		WFG:Log("[item] GetDef 诊断：%s -> %s（错误：%s）", defName, tostring(def), table.concat(errs, " | "))
	end
	if def == nil then
		-- 兼容可能存在的别名入口
		for _, fn in ipairs({ "GetThingDef", "GetThingDefByName", "FindThingDef" }) do
			local ok, v = pcall(function() return ThingMgr[fn](ThingMgr, defName) end)
			if ok and v ~= nil then def = v break end
		end
	end
	I.defCache[defName] = def or false
	return def
end

-- 物品等阶：先问定义，再问对象
function I:Level(thing)
	local name = self:DefName(thing)
	if name ~= nil then
		local def = self:Def(name)
		if def ~= nil then
			local lv = safeGet(def, "Level")
			if type(lv) == "number" then return lv end
			lv = safeGet(def, "ItemLevel")
			if type(lv) == "number" then return lv end
		end
	end
	local lv = safeGet(thing, "Level")
	if type(lv) == "number" then return lv end
	return 0
end

-- 品级 1~5（引擎里 Quality 是 0..1 的浮点，直接 floor 会恒等于 1）
function I:Quality(thing)
	local q = safeGet(thing, "Quality")
	if type(q) == "number" then
		local v = math.floor(q * 5) + 1
		if v < 1 then v = 1 end
		if v > 5 then v = 5 end
		return v
	end
	return 1
end

-- 材料定义名（合成物才有；普通物品返回 nil）
function I:Stuff(thing)
	if thing == nil then return nil end
	local ok, v = pcall(function()
		local sd = thing.StuffDef
		if sd ~= nil then return sd.Name end
		return thing.StuffDefName
	end)
	if ok and type(v) == "string" and v ~= "" then return v end
	return nil
end

-- 材料显示名
function I:StuffName(stuff)
	if type(stuff) ~= "string" or stuff == "" then return "未记录" end
	I.stuffCache = I.stuffCache or {}
	local hit = I.stuffCache[stuff]
	if hit ~= nil then return hit end
	local name = self:Show(stuff)
	I.stuffCache[stuff] = name
	return name
end

-- 该定义单件能储存的灵气上限（<=0 表示不能储灵）
function I:LingCap(defName)
	local def = self:Def(defName)
	if def == nil then return 0 end
	local ok, v = pcall(function() return def.LingMax end)
	if ok and type(v) == "number" and v > 0 and v < 1e9 then return v end
	return 0
end

-- 显示名
function I:DisplayName(thing)
	local ok, v = pcall(function() return thing.ThingName end)
	if ok and type(v) == "string" and v ~= "" then return v end
	return self:DefName(thing) or ""
end

function I:DefDisplayName(defName)
	if type(defName) ~= "string" or defName == "" then return "未知物品" end
	I.nameCache = I.nameCache or {}
	local hit = I.nameCache[defName]
	if hit ~= nil then return hit end

	local def = self:Def(defName)

	local name = nil
	if def ~= nil then
		for _, key in ipairs({ "ThingName", "DisplayName", "Name" }) do
			local v = safeGet(def, key)
			if type(v) == "string" and v ~= "" and v ~= defName then
				name = v
				break
			end
		end
		if name == nil then I:WarnBadDef(defName, def) end
	else
		I:WarnBadDef(defName, nil)
	end

	if name == nil or name == defName or isAscii(name) then
		-- 没有中文名：不再拿英文键名冒充显示名，交给调用方显示「未知物品」
		name = ""
	end
	I.nameCache[defName] = name
	if not I.sampleLogged then
		I.sampleLogged = true
		WFG:Log("[item] 名称解析示例：%s -> %s", defName, tostring(name))
	end
	return name
end

-- 定义查不到时只记一次，便于下次从日志里定位是哪一类物品
function I:WarnBadDef(defName, def)
	I.badDefs = I.badDefs or {}
	if I.badDefs[defName] then return end
	I.badDefs[defName] = true
	if def == nil then
		WFG:Log("[item] 取不到定义：%s（ThingMgr.GetThingDef 返回空）", defName)
		return
	end
	local keys = {}
	pcall(function()
		for k, v in pairs(def) do
			if type(k) == "string" and type(v) == "string" then
				keys[#keys + 1] = k
			end
		end
	end)
	WFG:Log("[item] 定义 %s 无 ThingName，可用字符串字段：%s", defName, table.concat(keys, ","))
end

-- 由物品实体取显示名：优先引擎 GetName()，取不到再回退到定义
function I:NameOf(thing)
	if thing == nil then return "未知物品" end
	local v = self:ThingName(thing)
	if type(v) == "string" and v ~= "" then return v end
	return "未知物品"
end

-- 定义名 → 可展示名字（取不到给中文兜底，不暴露英文键名）
function I:Show(defName)
	local s = self:DefDisplayName(defName or "")
	if type(s) == "string" and s ~= "" then return s end
	return "未知物品"
end

------------------------------------------------------------------
-- 造物
------------------------------------------------------------------
local function npcKey(npc)
	local k = 0
	if npc ~= nil then
		local ok, v = pcall(function() return npc.Key end)
		if ok and type(v) == "number" then k = v end
	end
	return k
end

-- 把物品落到地图（key 为 0 时交给引擎自行安置）
local function dropOnMap(thing, key)
	if key ~= nil and key > 0 then
		local ok = pcall(function() World.map:DropItem(thing, key) end)
		if ok then return true end
	end
	local ok = pcall(function() World.map:DropItem(thing) end)
	return ok
end

-- 造物：quality 1~5，stuff 材料定义名（nil 交给引擎随机），ling 为存入灵气总量；成功返回 true
function I:Create(defName, quality, count, npc, gridKey, stuff, ling)
	if defName == nil then return false end
	count = math.max(1, math.floor(count or 1))
	quality = math.max(1, math.min(5, math.floor(quality or 1)))
	local key = gridKey
	if type(key) ~= "number" or key <= 0 then key = npcKey(npc) end
	local addq = (quality - 1) * 0.2 + 0.1
	ling = tonumber(ling) or 0
	if ling < 0 then ling = 0 end

	-- 原版多数工具/材料的 def.LingMax 为 0，引擎 AddLing 会直接丢弃灵气。
	-- 造物瞬间临时抬高该 def 的上限，落格后立刻还原；已写入的 LingV 会保留。
	local restore = nil
	if ling > 0 then
		local d = self:Def(defName)
		if d ~= nil then
			local per = ling / count
			local capOk, cap = pcall(function() return d.LingMax end)
			if capOk and type(cap) == "number" and cap < per then
				restore = cap
				pcall(function() d.LingMax = per end)
			end
		end
	end
	local function putBack()
		if restore == nil then return end
		local d = self:Def(defName)
		if d ~= nil then pcall(function() d.LingMax = restore end) end
		restore = nil
	end

	local ok, err = pcall(function()
		World.map:DropItems(defName, stuff, count, key, true, true, ling, addq)
	end)
	putBack()
	if ok then
		if not I.createdOnce then
			I.createdOnce = true
			WFG:Log("[item] 造物样例：%s stuff=%s q=%d ling=%d", defName, tostring(stuff), quality, ling)
		end
		return true
	end

	-- 回退一：直接造物后落格
	local ok2, thing = pcall(function() return ThingMgr:AddItemThing(0, defName, World.map, count) end)
	if ok2 and thing ~= nil then
		if dropOnMap(thing, key) then return true end
	end

	-- 回退二：旧接口（部分版本可用）
	local ok3 = pcall(function() ThingMgr:CreateItem(defName, count, quality) end)
	if ok3 then return true end

	warnOnce("create", tostring(err))
	return false
end

------------------------------------------------------------------
-- 佩戴判定
------------------------------------------------------------------
-- 法宝槽：主攻法宝 + 额外法宝格（AtkFabao=2, AtkFabao2..6=81..85）
-- 秘宝/本命法宝胚胎的 Lable=Treasure 没有专门槽位，CheckEquipCell 走 default → GetToolEquipCell，
-- 实际落在道具槽 Tool1..Tool6（1001..1006）；武器槽 1 作兜底。
-- 只按本命法宝定义名/Oitem 匹配，不会误判普通道具。
local FABAO_SLOTS = { 1, 2, 81, 82, 83, 84, 85, 1001, 1002, 1003, 1004, 1005, 1006 }

local function getEquip(npc, slot)
	-- 装备读取在 NpcEquipData 上：npc.Equip:GetEquip(g_emEquipType)（Npc.GetEquip 也等价转发）
	local ok, v = pcall(function() return npc.Equip:GetEquip(slot) end)
	return v, ok
end

-- 认主后原剑会变成通用 FightFaBao，原定义名保留在 Fabao.Oitem 上
local function matchFabaoDef(thing, defName)
	local okd, dn = pcall(function() return I:DefName(thing) end)
	if okd and dn == defName then return true end
	local okf, fb = pcall(function() return thing.Fabao end)
	if okf and fb ~= nil then
		local oko, oi = pcall(function() return fb.Oitem end)
		if oko and oi == defName then return true end
	end
	return false
end

-- 佩戴四态：equipped / inactive / none / unavailable
-- inactive = 已装备但仍是法宝胚胎（FabaoAcriveData 非空），尚未右键认主；
-- 认主后 ActiveFabaoEmbryo 会把 FabaoAcriveData 置空并换成 FightFaBao。
function I:EquipState(npc, defName)
	if npc == nil or defName == nil then return "none" end
	local usable = 0
	for i = 1, #FABAO_SLOTS do
		local it, ok = getEquip(npc, FABAO_SLOTS[i])
		if ok then
			usable = usable + 1
			if it ~= nil and matchFabaoDef(it, defName) then
				local oke, emb = pcall(function() return it.FabaoAcriveData end)
				if oke and emb ~= nil then return "inactive" end
				return "equipped"
			end
		end
	end
	if usable == 0 then return "unavailable" end
	return "none"
end

-- 角色身上是否佩带着该定义的法宝（接口不可用时按未佩带处理）
function I:IsEquipped(npc, defName)
	return self:EquipState(npc, defName) == "equipped"
end

-- 角色身上是否佩带着任意一件给定的定义
function I:IsEquippedAny(npc, names)
	if npc == nil or type(names) ~= "table" then return false end
	for i = 1, #names do
		if self:IsEquipped(npc, names[i]) then return true end
	end
	return false
end

WFG.item = I
return I

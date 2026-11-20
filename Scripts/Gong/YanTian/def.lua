--[[
    衍天诀 · 数值与常量表
    所有可调数值集中在本文件，方便平衡；其它文件不写死数字。
]]

WFG = WFG or {}

local D = {}

D.gong        = "WFG_Gong_YanTian"
D.name        = "衍天诀"

-- 秘籍
D.eso = {
	gong     = "WFG_Eso_YanTian_Gong",
	heal     = "WFG_Eso_YanTian_Heal",
	healPlus = "WFG_Eso_YanTian_HealPlus",
	derive   = "WFG_Eso_YanTian_Derive",
	create   = "WFG_Eso_YanTian_Create",
	fabao    = "WFG_Eso_YanTian_Fabao",
	guard    = "WFG_Eso_YanTian_Guard",
	lingStone = "WFG_Eso_YanTian_LingStone",
	sword    = "WFG_Eso_YanTian_Sword",
	shield   = "WFG_Eso_YanTian_Shield",
	codex    = "WFG_Eso_YanTian_Codex",
	cycle    = "WFG_Eso_YanTian_Cycle",
	edge     = "WFG_Eso_YanTian_Edge",
	undying  = "WFG_Eso_YanTian_Undying",
}

-- 九境名（键为 Gong XML 的 Stage@Level，非序号）
D.stageName = {
	[1]  = "引灵入体",
	[3]  = "灵息初生",
	[5]  = "灵息圆满",
	[6]  = "灵子飞升",
	[7]  = "灵体·凝形",
	[8]  = "灵体·固本",
	[9]  = "衍天境",
	[10] = "避天机",
	[12] = "天门",
}

-- 关键境界节点（值为 GetGLevel() 返回的境界层，须与 Gong XML 的 Level 对齐）
D.stageFly    = 6    -- 灵子飞升
D.stageDerive = 9    -- 衍天境
D.stageGuard  = 10   -- 避天机
D.stageFinal  = 12   -- 天门

-- >>> WFG_TEST_MODE
-- 测试模式开关：true 时所有境界门槛归零（参悟树已全部下放练气期），
-- 仅为实机验证用；正式版请改为 false 或执行 tools/apply_test_mode.py --restore。
D.test = false
D.gateFly, D.gateDerive, D.gateGuard, D.gateFinal =
	D.stageFly, D.stageDerive, D.stageGuard, D.stageFinal
if D.test then
	D.gateFly, D.gateDerive, D.gateGuard, D.gateFinal = 0, 0, 0, 0
end
-- <<< WFG_TEST_MODE

-- 自愈程序：回灵速率 = 灵气上限 × 百分比 / 秒（经引擎 DynamicLing 速率管线生效，
-- 官方面板灵气行会显示真实的 +X/秒）；百分比 = 基础 + (境界层 - 飞升层) * 增长。
-- 血量仍按每秒结算，灵气满时溢出比例转为额外回血。
D.heal = {
	baseLingPct = 4.0,    -- 灵气回复 %（折算成 点/秒）
	baseHpPct   = 1.5,    -- 血量回复 %
	perStageLing = 0.5,
	perStageHp   = 0.2,
}

-- 衍天：解析
D.derive = {
	-- 可解析的最高物品等阶
	maxLevelBase   = 2,
	maxLevelPerStage = 1.2,   -- 每超出飞升境一层 +1.2
	-- 解析成本 = 50 * (L+1)^2 * Q
	costBase = 50,
	-- 创造成本 = 解析成本 * 该比例
	createRate = 0.3,
	-- 批量
	batchDiscountAt = 10,     -- 单次 >=10 件打九折
	batchDiscount   = 0.9,
	batchMaxBase    = 20,
	batchMaxAtStage10 = 100,
}

-- 本命法宝
D.fabao = {
	hallMatCostLing = 1000,      -- 共享素材库
	hallMatNeedKinds = 50,       -- 素材库种类 > 50
	hallEngCostLing = 1000000,   -- 共享能源核心（100 万）
	energyCap = 100000000,       -- 总能源核心容量
	defaultMode = 1,             -- 1 实时获取 2 充满获取
	defaultThresholdPct = 0.6,   -- 实时获取：自身灵气低于 60% 时补
	defaultLimit = 1000000,      -- 实时获取：累计取用总限额
	defaultBurst = 10000,        -- 充满获取：一次取用灵气量
}

-- 灵道剑：把自身道行存入剑中，换取「每 point 无上限」的法宝威力加成
-- addp = 存道 * rate；scale 直接写进修正器，所以不需要封顶/收敛
D.lingDao = {
	mod  = "WFG_Mod_YanTian_LingDao",   -- NpcFight_FabaoPowerAddP 修正器（AddV=1）
	rate = 0.01,                          -- 每 1 点存道 +1% 法宝威力
	eps  = 0.005,                         -- 变化小于 0.5% 不重设修正器，省得每秒抖动
	formula = "WFG_Formula_LingDaoJian",  -- 官方炼器配方
	-- 兼容旧档：秘籍的 <Fabaos> 只在「学会的那一刻」写进角色（EsotericaMgr.cs:466-472），
	-- 之后往 XML 新增配方不会补发，所以按「是否学过总纲」给老角色补学。
	-- 判定只能用参悟树节点名：EsotericaV / LearnedEsotericaList 都以「秘籍实例 ID」为键，
	-- 传定义名永远 false；LearnedTreeV 以 <Node Name> 为键且实时更新（NpcPractice.cs:1058/1075）。
	eso  = "WFG_Eso_YanTian_Fabao",
	tree = "WFG_Tree_YanTian_D0",  -- 授予总纲的参悟树节点（本命法宝，Dan1）
}

-- 储灵兜底：原版多数工具/材料的 ThingDef.LingMax 为 0，
-- 这类物品按「每件 lingFallback」给一个功法侧上限（造物时临时抬高 def 上限写入）。
D.lingFallback = 100

-- 物品与建筑
D.item = {
	hallMat  = "WFG_Item_HallMatFabao",   -- 共享素材库（终端法宝）
	hallEng  = "WFG_Item_HallEngFabao",   -- 共享能源核心（终端法宝）
	lingStone = "Item_LingStone",         -- 能源核心炼制前置：素材库需含灵石
	lingDao  = "WFG_Item_LingDaoJian",   -- 灵道剑（纳道行）
}

D.build = {
	hallMat = "WFG_Build_HallMat",
	hallEng = "WFG_Build_HallEng",
}

-- 数值查询
function D:MaxDeriveLevel(stage)
	if stage < D.stageFly then return 0 end
	return math.floor(D.derive.maxLevelBase + (stage - D.stageFly) * D.derive.maxLevelPerStage)
end

function D:DeriveCost(level, quality, npc)
	level = math.max(0, tonumber(level) or 0)
	quality = math.max(1, tonumber(quality) or 1)
	local cost = math.floor(D.derive.costBase * (level + 1) * (level + 1) * quality)
	-- 衍天佩解锁「解析」：解析耗灵减半
	local p = WFG.YanTian and WFG.YanTian.pei
	if npc ~= nil and p and p:Active(npc, "derive") then
		cost = math.max(1, math.floor(cost * 0.5))
	end
	return cost
end

function D:CreateCost(level, quality, count, npc)
	-- count 必须容错：UI 上「造 1 件耗灵 N」这类单件报价不会传第三个参数，
	-- 早期版本直接 unit * count → attempt to perform arithmetic on a nil value
	count = math.max(1, math.floor(tonumber(count) or 1))
	-- 基价不传 npc，避免「解析」折扣混入「创造」再叠乘
	local unit = math.floor(self:DeriveCost(level, quality) * D.derive.createRate)
	local total = unit * count
	if count >= D.derive.batchDiscountAt then
		total = math.floor(total * D.derive.batchDiscount)
	end
	-- 衍天佩解锁「创造」：创造耗灵减半（只作用于创造部分）
	local p = WFG.YanTian and WFG.YanTian.pei
	if npc ~= nil and p and p:Active(npc, "create") then
		total = math.max(1, math.floor(total * 0.5))
	end
	return total
end

function D:HealPercent(stage)
	local s = math.max(D.stageFly, stage or D.stageFly)
	local extra = (s - D.stageFly) * D.heal.perStageLing
	local extraHp = (s - D.stageFly) * D.heal.perStageHp
	return D.heal.baseLingPct + extra, D.heal.baseHpPct + extraHp
end

function D:BatchMax(stage)
	if stage >= 10 then return D.derive.batchMaxAtStage10 end
	return D.derive.batchMaxBase
end

WFG.YanTianDef = D

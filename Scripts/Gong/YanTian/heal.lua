--[[
    衍天诀 · 自愈程序（回灵速率制）
    - 每秒结算：把「灵气回复」折算成 点/秒 的回灵速率，发布到 npc.DynamicLing
    - 每帧刷新：地脉吸灵（LingMapData，16Hz）会覆盖 DynamicLing，必须每帧重新叠加
    - 引擎按 DynamicLing*dt 自行加灵气（Npc.cs:5706），因此官方面板灵气行的「+X.XX/秒」
      就是真实恢复速度（Panel_ThingInfo.cs:2801 只读 npc.DynamicLing）
    - 仅对「灵子飞升（飞升层）之后 + 已学自愈程序秘籍 + 开关为开」的角色生效
]]

WFG = WFG or {}
WFG.YanTian = WFG.YanTian or {}

local H = {}

-- 运行时表（不进存档）：[npcId] = { npc, base, last, rate, ling0, logged }
H.live = {}
-- 发布失败计数：连续失败就整体停用，避免每帧刷日志
H.fail = 0
H.off  = false
-- 神通按钮双态：两个 MagicDef 共用同一段点击逻辑，靠 Practice.Magics 里挂哪一个来区分开/关
H.ON   = "WFG_Magic_HealOn"
H.OFF  = "WFG_Magic_HealOff"
H.OLD  = "WFG_Magic_HealToggle"   -- 旧版单按钮：迁移时清掉
-- 已同步过的按钮态：[npcId] = "on" | "off" | "none"，避免每秒重复写
H.sync = {}
-- 已告警过数值异常（NaN）的角色，避免每秒刷日志
H.nanWarned = {}

-- 数值是否有限（排除 NaN / ±inf）。引擎的 Mathf.Clamp 遇到 NaN 会原样返回，
-- 一旦把 NaN 写进 LingV 就再也拉不回来，只能在读档时由引擎把 NaN 重置为 0。
local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function num(npc, key)
	local ok, v = pcall(function() return npc[key] end)
	if ok and type(v) == "number" then return v end
	if key == "Ling" then
		ok, v = pcall(function() return npc.LingV end)
		if ok and type(v) == "number" then return v end
	end
	return 0
end

-- 读当前回灵速率（点/秒）
local function readDyn(npc)
	local ok, v = pcall(function() return npc.DynamicLing end)
	if ok and finite(v) then return v end
	return nil
end

-- 写回灵速率（点/秒）；非有限值一律不写，失败返回 false
local function writeDyn(npc, v)
	if not finite(v) then return false end
	local ok = pcall(function() npc:DynamicAddLing(v) end)
	return ok
end

local function noRecover(npc)
	local ok, v = pcall(function() return npc:IsNoRecoverLing() end)
	return ok and v == true
end

function H:Pct(M, npc, c)
	local def = WFG.YanTianDef
	local lingPct, hpPct = def:HealPercent(c.stage or def.stageFly)

	-- 精研：原书 +50%；衍天佩解锁精研后再 +50%
	local bonus = 0
	if WFG.npc:IsLearned(npc, def.eso.healPlus or "WFG_Eso_YanTian_HealPlus") then
		bonus = bonus + 0.5
	end
	local p = WFG.YanTian and WFG.YanTian.pei
	if p and p:Active(npc, "healPlus") then
		bonus = bonus + 0.5
	end

	local mult = 1 + bonus
	-- 衍天佩解锁自愈：整段治疗速率再翻一倍
	if p and p:Active(npc, "heal") then
		mult = mult * 2
	end
	return lingPct * mult, hpPct * mult
end

-- 取 NPC 的修炼数据对象（Practice），失败返回 nil
function H:Practice(npc)
	return WFG.npc:Practice(npc)
end

-- 把神通按钮同步成开/关两态：面板上显示哪一个，取决于 Practice.Magics 里挂的是哪一个
-- on=true 只留「·开启」；on=false 只留「·关闭」；learned=false（含尚未灵子飞升）两个都不挂，解锁后下一秒自动出现
function H:SyncMagic(npc, on, learned)
	local id = WFG.npc:Id(npc)
	if id == nil then return end
	local want = "none"
	if learned then want = on and "on" or "off" end
	if self.sync[id] == want then return end

	local p = self:Practice(npc)
	if p == nil then return end

	local function has(n)
		local ok, r = pcall(function() return p:CheckMagic(n) end)
		return ok and r == true
	end
	local function add(n)
		if not has(n) then pcall(function() p:AddMagic(n) end) end
	end
	local function del(n)
		if has(n) then pcall(function() p:RemoveMagic(n) end) end
	end

	del(self.OLD)   -- 旧版单按钮：旧档迁移时清掉
	if want == "on" then
		del(self.OFF)
		add(self.ON)
	elseif want == "off" then
		del(self.ON)
		add(self.OFF)
	else
		del(self.ON)
		del(self.OFF)
	end

	-- 只有真正落到期望状态才记账，写失败就下一轮重试
	local done
	if want == "on" then done = has(self.ON) and not has(self.OFF)
	elseif want == "off" then done = has(self.OFF) and not has(self.ON)
	else done = not has(self.ON) and not has(self.OFF) end
	self.sync[id] = done and want or nil
end

-- 每秒：把门下衍天弟子的按钮态校正一遍（兼做旧档迁移）
function H:SyncAll(M)
	local def = WFG.YanTianDef
	local list = WFG.npc.list or {}
	for i = 1, #list do
		local npc = list[i]
		if WFG.npc:GetGongName(npc) == def.gong then
			local c = M:Char(npc, true)
			local learned = WFG.npc:IsLearned(npc, def.eso.heal)
			local unlocked = c ~= nil and (c.stage or 0) >= def.gateFly
			self:SyncMagic(npc, unlocked and learned and c.heal == 1, unlocked and learned)
		end
	end
end

function H:Second(M)
	local def = WFG.YanTianDef
	local npcs = WFG.npc.list or {}
	self:SyncAll(M)
	local keep = {}
	for i = 1, #npcs do
		local npc = npcs[i]
		if WFG.npc:GetGongName(npc) == def.gong then
			local c = M:Char(npc, true)
			if c and (c.stage or 0) >= def.gateFly and c.heal == 1
				and WFG.npc:IsLearned(npc, def.eso.heal) then
				local id = WFG.npc:Id(npc)
				if id ~= nil then
					keep[id] = true
					self:Tick(M, npc, c, id)
				end
			end
		end
	end
	-- 关闭开关 / 离开场景 / 不再合格的条目：写回原速率后移除
	local dead = nil
	for id, e in pairs(self.live) do
		if not keep[id] then
			dead = dead or {}
			dead[#dead + 1] = id
		end
	end
	if dead ~= nil then
		for i = 1, #dead do
			local e = self.live[dead[i]]
			if e ~= nil then self:Restore(e) end
			self.live[dead[i]] = nil
		end
	end
end

function H:Tick(M, npc, c, id)
	local def = WFG.YanTianDef
	local lingPct, hpPct = self:Pct(M, npc, c)

	local maxLing = num(npc, "MaxLing")
	local ling    = num(npc, "Ling")
	local maxHp   = num(npc, "MaxHp")
	local hp      = num(npc, "Hp")
	if maxLing <= 0 or maxHp <= 0 then
		local e = self.live[id]
		if e ~= nil then self:Restore(e); self.live[id] = nil end
		return
	end

	-- 灵气/气血已成 NaN 时不能继续写速率：DynamicLing 会被引擎累加进 LingV，
	-- 而 NaN 一旦进了 LingV，Clamp 也不会还原（只能在读档时被引擎重置）。
	if not finite(ling) or not finite(hp) then
		local e0 = self.live[id]
		if e0 ~= nil then self:Restore(e0); self.live[id] = nil end
		self:NanWarn(npc)
		return
	end

	local lingGain = maxLing * lingPct / 100   -- 点/秒
	local hpGain   = maxHp * hpPct / 100
	local need     = maxLing - ling
	if need < 0 then need = 0 end

	local e = self.live[id]
	if e == nil or e.npc ~= npc then
		local base = readDyn(npc) or 0
		e = { npc = npc, base = base, last = base, rate = 0, ling0 = ling, logged = false, hpRate = 0, hpAcc = 0 }
		self.live[id] = e
		self:AddBuff(npc)
	end

	-- 上一秒的校正：帧序竞争时引擎可能少吃掉一部分速率，这里补齐，保证面板数字 = 实际恢复
	if e.ling0 ~= nil and (e.rate or 0) > 0 and not self.off then
		local gained = ling - e.ling0
		if gained < 0 then gained = 0 end
		if gained < e.rate * 0.75 then
			local add = math.min(e.rate - gained, need)
			if add > 0 then
				WFG:Safe(function() npc:AddLing(add) end)
			end
		end
	end

	-- 灵气未满：全速回灵。引擎按 DynamicLing*dt 连续结算并在上限处钳制，
	-- 因此这里不再按 need 掐断速率，避免「快到上限时被降速」的假象。
	local lingFull = need <= 0.01
	local rate = 0
	if not lingFull and lingGain > 0 and not self.off and not noRecover(npc) then
		rate = lingGain
	end
	e.rate  = rate
	e.ling0 = ling

	if not e.logged then
		e.logged = true
		WFG:Log("自愈程序：%s 回灵 %.2f/秒（上限 %.0f，当前 %.0f）",
			tostring(WFG.npc:GetName(npc)), rate, maxLing, ling)
	end

	-- 气血：只在灵气已满后恢复，按「点/秒」交给 Frame 每帧少量结算，
	-- 灵气溢出的部分全部转为气血，保证不会在接近上限时被一次性打满而浪费。
	e.hpRate = 0
	if lingFull and hpGain > 0 and not self.off then
		e.hpRate = hpGain + lingGain
	end
	e.hpMax = maxHp
	e.hp    = hp
end

-- 数值异常告警：每个角色只报一次，提示用读档修复
function H:NanWarn(npc)
	local id = WFG.npc:Id(npc)
	if id == nil or self.nanWarned[id] then return end
	self.nanWarned[id] = true
	WFG:Error("heal.nan", string.format(
		"%s 的灵气或气血数值是 NaN，自愈程序已暂停对它的速率写入；引擎只在读档时把 NaN 灵气重置为 0，存档后重读该存档即可修复",
		tostring(WFG.npc:GetName(npc))))
end

-- 每帧：把「基值 + 回灵速率」发布回 DynamicLing（叠加在地脉吸灵之上）
function H:Frame(dt)
	if self.off then return end
	if self.live == nil then return end
	for id, e in pairs(self.live) do
		local npc = e.npc
		self:FrameHp(e, dt)
		local cur = readDyn(npc)
		if cur == nil then
			self.live[id] = nil
		else
			-- 值被引擎/地脉改写过 → 把当前值当作新的基值（保留环境吸灵贡献）
			if math.abs(cur - e.last) > 0.001 then e.base = cur end
			local target = e.base + e.rate
			if math.abs(target - cur) > 0.0005 then
				if writeDyn(npc, target) then
					e.last = target
					self.fail = 0
				else
					self.live[id] = nil
					self.fail = self.fail + 1
					if self.fail >= 3 then
						self.off = true
						WFG:Error("heal.frame", "回灵速率发布连续失败，已停用自愈速率")
					end
				end
			else
				e.last = target
			end
		end
	end
end

-- 「自愈程序」状态图标（Modifier）：让 UI 有一枚可见的持续效果，并说明每秒恢复口径
function H:AddBuff(npc)
	WFG:Safe(function() npc:AddModifier("WFG_Mod_YanTian_Heal") end)
end

function H:DelBuff(npc)
	WFG:Safe(function() npc:RemoveModifier("WFG_Mod_YanTian_Heal") end)
end

-- 每帧：气血按 dt 少量多次结算，接近上限时自动截断，不会溢出浪费
function H:FrameHp(e, dt)
	local rate = e.hpRate or 0
	if rate <= 0 then return end
	local npc = e.npc
	local maxHp = e.hpMax or num(npc, "MaxHp")
	local hp = num(npc, "Hp")
	if not finite(hp) or not finite(maxHp) or maxHp <= 0 or hp >= maxHp - 0.01 then
		e.hpAcc = 0
		return
	end
	e.hpAcc = (e.hpAcc or 0) + rate * dt
	if e.hpAcc < 0.25 then return end
	local add = e.hpAcc
	if add > maxHp - hp then add = maxHp - hp end
	if add > 0 then
		WFG:Safe(function() npc:AddHealth(add) end)
		e.hpAcc = e.hpAcc - add
		if e.hpAcc < 0 then e.hpAcc = 0 end
	end
end

-- 把某个角色写回原速率
function H:Restore(e)
	if e == nil or e.npc == nil then return end
	writeDyn(e.npc, e.base or 0)
	self:DelBuff(e.npc)
end

-- 全量还原（离开世界 / 读档前）
function H:ClearAll()
	local ids = {}
	for id in pairs(self.live) do ids[#ids + 1] = id end
	for i = 1, #ids do
		local e = self.live[ids[i]]
		if e ~= nil then self:Restore(e) end
		self.live[ids[i]] = nil
	end
	self.fail = 0
	self.off  = false
	self.sync = {}
	self.nanWarned = {}
end

-- 供 UI 读取：返回（面板总速率，其中自愈贡献）
function H:RateOf(npc)
	local id = WFG.npc:Id(npc)
	local e = id and self.live[id] or nil
	if e == nil then return 0, 0 end
	return (e.base or 0) + (e.rate or 0), (e.rate or 0)
end

-- 供 UI 读取：当前气血回复速率（点/秒）
function H:HpRateOf(npc)
	local id = WFG.npc:Id(npc)
	local e = id and self.live[id] or nil
	if e == nil then return 0 end
	if e.hpRate == nil then return 0 end
	return e.hpRate
end

-- 神通/面板调用：切换开关
function H:Toggle(M, npc)
	local c = M:Char(npc, true)
	if c == nil then return false, "未找到角色数据" end
	local def = WFG.YanTianDef
	if (c.stage or 0) < def.gateFly then
		return false, "灵子未飞升，无法运行自愈程序"
	end
	if not WFG.npc:IsLearned(npc, def.eso.heal) then
		return false, "尚未习得自愈程序"
	end
	c.heal = (c.heal == 1) and 0 or 1
	self:SyncMagic(npc, c.heal == 1, true)
	if c.heal ~= 1 then
		local id = WFG.npc:Id(npc)
		local e = id and self.live[id] or nil
		if e ~= nil then self:Restore(e); self.live[id] = nil end
	end
	return true, (c.heal == 1) and "自愈程序已开启" or "自愈程序已关闭"
end

WFG.YanTian.heal = H
return H

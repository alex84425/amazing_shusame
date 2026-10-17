-- 覓長生傳承（離火門、竹山宗…）：回合引擎
-- 把覓長生的回合制搬進即時戰鬥：每 TURN 秒算一回合。
--   回合開始：狀態結算（灼燒、纏繞）、焚心訣
--   吸收靈氣：依五行根基權重抽取五行靈氣
--   出手：AI 依當前靈氣規劃一串技能（考慮連擊、【同】、後繼無力），間隔施放
--   回合結束：化焰相關、靈氣溢出消散
-- 所有和遊戲本體互動的呼叫都經過 MCS.Host（見 MCS_Host.lua），方便離線測試。

local MCS = GameMain:GetMod("MCS_LiHuo")

MCS.TURN = 3.0                 -- 一回合的秒數（遊戲時間）
MCS.CAST_GAP = 0.55            -- 同回合內連續出手的間隔
MCS.K = { 12, 15, 20 }         -- 覓長生傷害點數 → 本遊戲傷害 的換算（煉氣/築基/金丹）
MCS.BURN_RATE = 0.2            -- 灼燒每層的傷害 = K × 此倍率
MCS.BURN_CAP = 99              -- 灼燒／中毒／化焰層數上限
MCS.POISON_RATE = 0.15         -- 中毒每層的傷害 = K × 此倍率（中毒不衰減，所以比灼燒低）
MCS.LIFESTEAL = 0.5            -- 【吸血】：恢復造成傷害的比例
MCS.ABSORB = { 3, 4, 5 }       -- 每回合吸收靈氣點數
MCS.CAP = { 8, 12, 16 }        -- 靈氣上限
MCS.ELEMS = { "Jin", "Mu", "Shui", "Huo", "Tu" }
MCS.ENAME = { Jin = "金", Mu = "木", Shui = "水", Huo = "火", Tu = "土" }

MCS.st = MCS.st or {}          -- [npcID] = 個體資料
MCS.timers = MCS.timers or {}
MCS.clock = MCS.clock or 0
MCS.acc = 0

local function H() return MCS.Host end

---------------------------------------------------------------------------
-- 小工具
---------------------------------------------------------------------------
local function has(list, x)
	for _, v in ipairs(list or {}) do
		if v == x then return true end
	end
	return false
end

local function val(t, r)
	if type(t) == "table" then return t[r] or t[#t] end
	return t or 0
end

function MCS:After(delay, fn)
	self.timers[#self.timers + 1] = { at = self.clock + delay, fn = fn }
end

function MCS:Log(s)
	if self.verbose then print("[MCS] " .. s) end
	if self.onLog then self.onLog(s) end
end

-- 每個角色一份資料：靈氣、狀態、回合計時
function MCS:S(id)
	local s = self.st[id]
	if s == nil then
		s = { id = id, qi = {}, turnT = 0, inFight = false, outT = 0, lastLing = nil,
			burn = 0, burnK = 12, burnFrom = nil, yan = 0, huayan = 0, chanrao = 0,
			mark = nil, nextFire = 0, juhuo = 0, huoW = 0, firstFireDone = false, last = nil,
			poison = 0, poisonK = 12, poisonFrom = nil, nextWood = 0, boostMu = 0, muW = 0,
			firstWoodDone = false, muUsed = 0, yinduCount = 0 }
		for _, e in ipairs(self.ELEMS) do s.qi[e] = 0 end
		self.st[id] = s
	end
	return s
end

function MCS:QiTotal(s)
	local n = 0
	for _, e in ipairs(self.ELEMS) do n = n + s.qi[e] end
	return n
end

function MCS:Hurt(target, amount, from, desc, elem)
	local s = self.st[H().id(target)]
	if s ~= nil and from ~= nil and H().id(from) == s.id then s.ignoreDrop = (s.ignoreDrop or 0) + amount end
	H().damage(target, amount, from, desc, elem or "Huo")
end

-- 技能的主屬性（【同】優先用它支付）
function MCS:Main(d)
	local sc = self.SCHOOLS and self.SCHOOLS[d.school]
	return (sc and sc.main) or d.elems[1]
end

function MCS:Passive(npc, id)
	return H().learned(npc, self:EsoName(id))
end

function MCS:PVal(npc, id, key, r)
	if not self:Passive(npc, id) then return 0 end
	return val(self.PASSIVES[id][key], r)
end

---------------------------------------------------------------------------
-- 狀態
---------------------------------------------------------------------------
function MCS:AddBurn(target, n, from)
	if n <= 0 or target == nil then return end
	local s = self:S(H().id(target))
	s.burn = math.min(self.BURN_CAP, s.burn + n)
	if from ~= nil then
		local fr = H().realm(from)
		s.burnK = math.max(self.K[fr], s.burnK or 0)
		s.burnFrom = H().id(from)
	end
	s.tracked = true
	H().showStatus(target, "Burn", s.burn)
	H().fx("burn", from, target, n)
end

function MCS:AddPoison(target, n, from)
	if n <= 0 or target == nil then return end
	local s = self:S(H().id(target))
	s.poison = math.min(self.BURN_CAP, s.poison + n)
	if from ~= nil then
		s.poisonK = math.max(self.K[H().realm(from)], s.poisonK or 0)
		s.poisonFrom = H().id(from)
	end
	s.tracked = true
	H().showStatus(target, "Poison", s.poison)
	H().fx("poison", from, target, n)
end

-- 中毒：回合結束時受到「層數」點木系傷害，層數不會自然減少
function MCS:TickPoison(npc, s, times)
	if s.poison <= 0 then return 0 end
	local dmg = s.poison * (s.poisonK or 12) * self.POISON_RATE * (times or 1)
	local from = s.poisonFrom and H().find(s.poisonFrom) or nil
	s.ignoreDrop = (s.ignoreDrop or 0) + dmg
	H().damage(npc, dmg, from, "中毒", "Mu")
	self:Log(H().name(npc) .. " 中毒×" .. s.poison .. " 受到 " .. dmg .. " 點木傷")
	return dmg
end

function MCS:AddChanRao(target, n)
	if n <= 0 then return end
	local s = self:S(H().id(target))
	s.chanrao = s.chanrao + n
	s.tracked = true
	H().showStatus(target, "ChanRao", s.chanrao)
end

function MCS:SetYan(npc, s, v)
	s.yan = math.max(0, v)
	H().showStatus(npc, "Yan", s.yan)
end

function MCS:SetHuaYan(npc, s, v, enemy)
	local before = s.huayan
	s.huayan = math.max(0, math.min(self.BURN_CAP, v))
	H().showStatus(npc, "HuaYan", s.huayan)
	-- 玄陽哺焰訣：脫離化焰時，對手獲得化焰層數倍數的灼燒
	if before > 0 and s.huayan == 0 and enemy ~= nil then
		local mul = self:PVal(npc, "XuanYang", "leaveHuaYanMul", H().realm(npc))
		if mul > 0 then
			self:AddBurn(enemy, before * mul, npc)
			self:Log(H().name(npc) .. " 脫離化焰，玄陽哺焰訣使對手灼燒+" .. before * mul)
		end
	end
end

-- 灼燒：回合開始時，受到「層數 × 1 點」火系傷害，之後移除一層
function MCS:TickBurn(npc, s)
	if s.burn <= 0 then return end
	local dmg = s.burn * (s.burnK or 12) * self.BURN_RATE
	local from = s.burnFrom and H().find(s.burnFrom) or nil
	-- 自身的灼燒不算「被打」
	s.ignoreDrop = (s.ignoreDrop or 0) + dmg
	H().damage(npc, dmg, from, "灼燒", "Huo")
	self:Log(H().name(npc) .. " 灼燒×" .. s.burn .. " 受到 " .. dmg .. " 點火傷")
	s.burn = s.burn - 1
	H().showStatus(npc, "Burn", s.burn)
end

---------------------------------------------------------------------------
-- 五行靈氣
---------------------------------------------------------------------------
function MCS:Absorb(npc, s, n)
	local w, total = {}, 0
	for _, e in ipairs(self.ELEMS) do
		local x = math.max(0.05, H().weight(npc, e))
		if e == "Huo" then x = x * (1 + 0.5 * s.juhuo + s.huoW) end
		if e == "Mu" then x = x * (1 + 0.5 * s.boostMu + s.muW) end
		w[e] = x
		total = total + x
	end
	local got = {}
	for _ = 1, n do
		local r = math.random() * total
		for _, e in ipairs(self.ELEMS) do
			r = r - w[e]
			if r <= 0 then
				s.qi[e] = s.qi[e] + 1
				got[#got + 1] = self.ENAME[e]
				break
			end
		end
	end
	return table.concat(got)
end

-- 付費：先付指定五行，再用「同」付任意靈氣（優先用 main 以觸發【同】）
function MCS:CanPay(qi, cost)
	local left = 0
	for _, e in ipairs(self.ELEMS) do
		local need = cost[e] or 0
		if qi[e] < need then return false end
		left = left + qi[e] - need
	end
	return left >= (cost.any or 0)
end

-- 實際消耗：引毒咒這類「同回合每多用一次就多耗一點」的技能
function MCS:CostOf(d, uses)
	if not d.costRamp or (uses or 0) == 0 then return d.cost end
	local c = {}
	for k, v in pairs(d.cost) do c[k] = v end
	c[d.costRamp] = (c[d.costRamp] or 0) + uses
	return c
end

function MCS:Pay(qi, cost, main)
	for _, e in ipairs(self.ELEMS) do
		qi[e] = qi[e] - (cost[e] or 0)
	end
	local same = (cost.any or 0) > 0
	for _ = 1, cost.any or 0 do
		local pick = (main and qi[main] > 0) and main or nil
		if pick == nil then
			same = false
			for _, e in ipairs(self.ELEMS) do
				if pick == nil or qi[e] > qi[pick] then pick = e end
			end
		end
		qi[pick] = qi[pick] - 1
	end
	return same
end

function MCS:Overflow(s, r)
	local cap = self.CAP[r]
	local lost = 0
	while self:QiTotal(s) > cap do
		local pick
		for _, e in ipairs(self.ELEMS) do
			if s.qi[e] > 0 and (pick == nil or (s.qi[e] >= s.qi[pick] and e ~= (s.keepElem or "Huo"))) then pick = e end
		end
		s.qi[pick] = s.qi[pick] - 1
		lost = lost + 1
	end
	return lost
end

function MCS:QiText(s, r)
	local parts = {}
	for _, e in ipairs(self.ELEMS) do
		if s.qi[e] > 0 then parts[#parts + 1] = self.ENAME[e] .. s.qi[e] end
	end
	return (#parts > 0 and table.concat(parts, " ") or "無") .. "（上限 " .. self.CAP[r] .. "）"
end

---------------------------------------------------------------------------
-- 出手規劃（AI）
---------------------------------------------------------------------------
function MCS:Learned(npc)
	local list = {}
	for id in pairs(self.SKILLS) do
		if H().learned(npc, self:EsoName(id)) then list[#list + 1] = id end
	end
	table.sort(list)
	return list
end

-- 依「目前狀況」估計一招的價值；回傳 0 表示不值得出
function MCS:Score(npc, s, ts, id, ctx, r)
	local d = self.SKILLS[id]
	local combo = d.combo and ctx.last and has(ctx.last, d.combo.elem)
	local room = function(n) return math.max(0, math.min(n, self.BURN_CAP - ts.burn)) end
	local v = 0
	if d.dmg then v = v + val(d.dmg, r) + (combo and val(d.combo.dmg, r) or 0) + (d.same and val(d.same, r) * 0.7 or 0) end
	if d.dmg and has(d.elems, "Huo") then v = v + s.yan + ctx.nextFire end
	if d.burn then v = v + room(val(d.burn, r)) * 2.2 end
	if combo and d.combo.burn then v = v + room(val(d.combo.burn, r)) * 2.2 end
	if combo and d.combo.selfYan then v = v + val(d.combo.selfYan, r) * 2 end
	if d.selfYan then v = v + val(d.selfYan, r) * 1.8 end
	if d.burnedEntangle and ts.burn > 0 then v = v + val(d.burnedEntangle, r) end
	if d.burnedDissipate and ts.burn > 0 then v = v + d.burnedDissipate * 1.5 end
	if d.dissipate then v = v + d.dissipate * 1.5 end
	if d.triggerYan then v = v + s.yan * (combo and 2 or 1) end
	if d.shield then
		local low = H().lingRatio(npc) < 0.5
		v = v + val(d.shield, r) * (combo and d.combo.shieldMul or 1) * (low and 1.6 or 0.6)
	end
	if d.mark and d.mark.burn then v = v + (s.mark and 0 or room(val(d.mark.burn, r)) * 1.2) end
	if d.juhuo then v = v + (s.juhuo < 2 and 4 or 0) end
	-- 已在化焰中就幾乎不必再放（只剩疊層數的小收益）
	if d.selfHuaYan then v = v + (s.huayan == 0 and (5 + (self:Passive(npc, "RongDun") and 3 or 0)) or 0.3) end
	if d.removeSelfBurn then v = v + math.min(s.burn, d.removeSelfBurn) * 1.5 + val(d.heal, r) end
	if d.eatYan then v = v + (s.yan >= 5 and s.yan * val(d.eatYan, r) * (H().lingRatio(npc) < 0.6 and 1 or 0.3) or 0) end
	if d.mirrorBurn then v = v + room(s.burn) * 2.2 end
	if d.selfBurn then
		local fenTian = self:PVal(npc, "FenTian", "perSelfBurn", r)
		v = v - val(d.selfBurn, r) * (fenTian > 0 and 0.2 or 1.0)
	end
	-- 竹山宗：中毒（不會衰減，價值高）、纏繞、吸血、引毒
	local proom = function(n) return math.max(0, math.min(n, self.BURN_CAP - ts.poison)) end
	if d.poison then v = v + proom(val(d.poison, r)) * 2.5 end
	if d.chanrao then v = v + val(d.chanrao, r) * (ctx.usesEntangle and 1.6 or 0.8) end
	if combo and d.combo.chanrao then v = v + val(d.combo.chanrao, r) * 1.2 end
	if combo and d.combo.randomDebuff then v = v + d.combo.randomDebuff * 2 end
	if d.perEntangle then v = v + ts.chanrao * d.perEntangle end
	if d.vsPoisonDouble and ts.poison > 0 then v = v + val(d.dmg, r) end
	if d.dmg and d.school == "ZhuShan" then v = v + ctx.nextWood end
	if d.lifesteal or (d.lifestealIfEntangled and ts.chanrao > 0) then
		v = v + (d.dmg and val(d.dmg, r) or 0) * (H().lingRatio(npc) < 0.6 and 0.8 or 0.3)
	end
	-- 引毒：立即結算一次中毒，價值 = 中毒層數 × 每層傷害倍率（換成點數）
	if d.triggerPoison then v = v + ts.poison * self.POISON_RATE * 1.2 end
	if d.nextWood then v = v + (ctx.nextWood == 0 and val(d.nextWood, r) * 0.8 or 0) end
	if d.boostMu then v = v + (s.boostMu < 2 and 4 or 0) end
	if d.mark and d.mark.chanrao then v = v + (s.mark and 0 or val(d.mark.chanrao, r)) end
	-- 鋪連擊：木系技能為火系連擊鋪路、水系技能為木系連擊鋪路
	if has(d.elems, "Mu") and ctx.comboReady then v = v + 3 end
	if has(d.elems, "Shui") and ctx.comboReadyShui then v = v + 3 end
	if d.hou then v = v * 0.7 end
	return v
end

---------------------------------------------------------------------------
-- 自訂出招順序（由出招設定視窗編輯，存在存檔裡）
-- MCS.orders[npcID] = { manual = true/false, list = { 技能id... }, off = { [技能id] = true } }
---------------------------------------------------------------------------
MCS.orders = MCS.orders or {}

-- 預設順序：照技能樹（煉氣 → 築基 → 金丹）
function MCS:DefaultOrder()
	local list = {}
	for _, school in ipairs({ "LiHuo", "ZhuShan" }) do
		local tree = self.TREES and self.TREES[school]
		if tree then
			for _, lv in ipairs({ "Qi", "Dan1", "Dan2" }) do
				for _, id in ipairs(tree[lv] or {}) do
					if self.SKILLS[id] then list[#list + 1] = id end
				end
			end
		end
	end
	return list
end

-- 取得某弟子的順序設定；會補上新學會、尚未排進清單的技能
function MCS:GetOrder(npcId)
	local o = self.orders[npcId]
	if o == nil then
		o = { manual = false, list = self:DefaultOrder(), off = {} }
		self.orders[npcId] = o
	end
	local seen = {}
	for _, id in ipairs(o.list) do seen[id] = true end
	for _, id in ipairs(self:DefaultOrder()) do
		if not seen[id] then o.list[#o.list + 1] = id end
	end
	return o
end

-- 照玩家順序：每一步從清單最上面找第一個「已學會、已啟用、付得起」的技能
function MCS:PlanManual(npc, s, order)
	local qi = {}
	for k, x in pairs(s.qi) do qi[k] = x end
	local learned = {}
	for _, id in ipairs(self:Learned(npc)) do learned[id] = true end
	local last = s.last
	local plan = {}
	local uses = {}
	for _ = 1, 6 do
		local pick
		for _, id in ipairs(order.list) do
			if learned[id] and not order.off[id] and self:CanPay(qi, self:CostOf(self.SKILLS[id], uses[id])) then
				pick = id
				break
			end
		end
		if pick == nil then break end
		local d = self.SKILLS[pick]
		local same = self:Pay(qi, self:CostOf(d, uses[pick]), self:Main(d))
		uses[pick] = (uses[pick] or 0) + 1
		local combo = d.combo ~= nil and last ~= nil and has(last, d.combo.elem)
		plan[#plan + 1] = { id = pick, same = same, combo = combo, prevElems = last }
		last = d.elems
		if d.hou then break end
	end
	return plan, qi
end

function MCS:Plan(npc, s, target)
	local order = self.orders[H().id(npc)]
	if order ~= nil and order.manual then
		return self:PlanManual(npc, s, self:GetOrder(H().id(npc)))
	end
	local r = H().realm(npc)
	local ts = self:S(H().id(target))
	local qi = {}
	for k, x in pairs(s.qi) do qi[k] = x end
	local learned = self:Learned(npc)
	local ctx = { last = s.last, nextFire = s.nextFire, nextWood = s.nextWood }
	-- 有沒有學會「吃木系連擊」的火系技能、「吃水系連擊」的木系技能、會吃纏繞的技能
	for _, id in ipairs(learned) do
		local sk = self.SKILLS[id]
		if sk.combo and sk.combo.elem == "Mu" then ctx.comboReady = true end
		if sk.combo and sk.combo.elem == "Shui" then ctx.comboReadyShui = true end
		if sk.perEntangle or sk.lifestealIfEntangled then ctx.usesEntangle = true end
	end
	if self:Passive(npc, "YinHuo") or self:Passive(npc, "DieYan") then ctx.comboReady = true end
	if self:Passive(npc, "ShangQing") then ctx.comboReadyShui = true end
	local uses = {}

	local plan = {}
	for _ = 1, 6 do
		local best, bestV
		for _, id in ipairs(learned) do
			local d = self.SKILLS[id]
			if self:CanPay(qi, self:CostOf(d, uses[id])) then
				local v = self:Score(npc, s, ts, id, ctx, r)
				if v > 0.5 and (bestV == nil or v > bestV) then best, bestV = id, v end
			end
		end
		if best == nil then break end
		local d = self.SKILLS[best]
		local same = self:Pay(qi, self:CostOf(d, uses[best]), self:Main(d))
		uses[best] = (uses[best] or 0) + 1
		local combo = d.combo ~= nil and ctx.last ~= nil and has(ctx.last, d.combo.elem)
		plan[#plan + 1] = { id = best, same = same, combo = combo, prevElems = ctx.last }
		ctx.last = d.elems
		if d.dmg and has(d.elems, "Huo") then ctx.nextFire = 0 end
		if d.dmg and d.school == "ZhuShan" then ctx.nextWood = 0 end
		if d.nextWood then ctx.nextWood = val(d.nextWood, r) end
		if d.hou then break end
	end
	return plan, qi
end

---------------------------------------------------------------------------
-- 施放：在施法時刻結算效果（傷害在飛彈命中時才結算）
---------------------------------------------------------------------------
function MCS:Execute(npc, s, target, step)
	if not H().alive(npc) or not H().alive(target) then return end
	local d = self.SKILLS[step.id]
	local r = H().realm(npc)
	local ts = self:S(H().id(target))
	local isFire = has(d.elems, "Huo")
	-- 非火系技能會脫離化焰
	if not isFire and s.huayan > 0 then self:SetHuaYan(npc, s, 0, target) end
	s.last = d.elems
	self:Log(H().name(npc) .. " 施展【" .. d.name .. "】" .. (step.combo and "（連擊）" or "") .. (step.same and "（同）" or ""))
	H().fx(d.fx, npc, target, step.id)

	-- 自身效果立即生效
	if d.selfYan then self:SetYan(npc, s, s.yan + val(d.selfYan, r)) end
	if step.combo and d.combo.selfYan then self:SetYan(npc, s, s.yan + val(d.combo.selfYan, r)) end
	if d.selfHuaYan then self:SetHuaYan(npc, s, s.huayan + val(d.selfHuaYan, r), target) end
	if d.juhuo then s.juhuo = s.juhuo + d.juhuo end
	if d.mark then
		s.mark = { burn = d.mark.burn and val(d.mark.burn, r), chanrao = d.mark.chanrao and val(d.mark.chanrao, r) }
	end
	if d.boostMu then s.boostMu = s.boostMu + d.boostMu end
	if d.nextWood then s.nextWood = s.nextWood + val(d.nextWood, r) end
	-- 回春訣：每消耗 5 點木系靈氣恢復生命
	local mu = (d.cost.Mu or 0) + ((d.costRamp == "Mu") and math.max(0, s.yinduCount) or 0)
	if d.costRamp then s.yinduCount = s.yinduCount + 1 end
	if mu > 0 then
		s.muUsed = s.muUsed + mu
		local heal = self:PVal(npc, "HuiChunJue", "healPer5Mu", r)
		while s.muUsed >= 5 do
			s.muUsed = s.muUsed - 5
			if heal > 0 then H().heal(npc, heal * self.K[r], "回春訣") end
		end
	end
	if d.shield then
		local n = val(d.shield, r) * ((step.combo and d.combo.shieldMul) or 1)
		H().heal(npc, n * self.K[r], "護罩")
	end
	if d.removeSelfBurn then
		s.burn = math.max(0, s.burn - d.removeSelfBurn)
		H().showStatus(npc, "Burn", s.burn)
		H().heal(npc, val(d.heal, r) * self.K[r], "吞焰")
		s.nextFire = s.nextFire + val(d.nextFire, r)
	end
	if d.eatYan and s.yan > 0 then
		H().heal(npc, s.yan * val(d.eatYan, r) * self.K[r], "大吞焰")
		self:SetYan(npc, s, 0)
	end
	if d.selfBurn then
		s.burn = math.min(self.BURN_CAP, s.burn + val(d.selfBurn, r))
		s.burnK = self.K[r]
		s.burnFrom = H().id(npc)
		s.tracked = true
		H().showStatus(npc, "Burn", s.burn)
	end
	-- 疊焰訣：火系技能且上一招為木系 → 焰
	if isFire and step.prevElems and has(step.prevElems, "Mu") then
		local add = self:PVal(npc, "DieYan", "comboYan", r)
		if add > 0 then self:SetYan(npc, s, s.yan + add) end
	end

	-- 打到對方的效果：飛彈飛行時間後結算
	local delay = (d.fx == "bolt" or d.fx == "big" or d.fx == "wbolt" or d.fx == "wbig") and 0.35 or 0.15
	self:After(delay, function()
		if not H().alive(target) then return end
		self:Hit(npc, s, target, ts, d, step, r, isFire)
	end)
end

function MCS:Hit(npc, s, target, ts, d, step, r, isFire)
	if d.dmg then
		local pts = val(d.dmg, r)
		if step.combo and d.combo.dmg then pts = pts + val(d.combo.dmg, r) end
		if step.same and d.same then pts = pts + val(d.same, r) end
		if isFire then
			pts = pts + s.yan + s.nextFire
			s.nextFire = 0
			if step.prevElems and has(step.prevElems, "Mu") then pts = pts + self:PVal(npc, "YinHuo", "comboDmg", r) end
			if not s.firstFireDone then
				pts = pts + self:PVal(npc, "NongYan", "firstDmg", r)
				s.firstFireDone = true
			end
			pts = pts + s.burn * self:PVal(npc, "FenTian", "perSelfBurn", r)
		end
		local isWood = d.school == "ZhuShan"
		if isWood then
			pts = pts + s.nextWood
			s.nextWood = 0
			if step.prevElems and has(step.prevElems, "Shui") then pts = pts + self:PVal(npc, "ShangQing", "comboDmg", r) end
			if not s.firstWoodDone then
				pts = pts + self:PVal(npc, "ShengMu", "firstDmg", r)
				s.firstWoodDone = true
			end
			if ts.poison > 0 then pts = pts + self:PVal(npc, "TaiYin", "vsPoison", r) end
			if d.perEntangle then pts = pts + ts.chanrao * d.perEntangle end
			-- 障毒訣：對中毒目標「基礎傷害」翻倍（功法加成不翻倍）
			if d.vsPoisonDouble and ts.poison > 0 then pts = pts + val(d.dmg, r) end
		end
		local dealt = pts * self.K[r]
		self:Hurt(target, dealt, npc, d.name, isWood and "Mu" or "Huo")
		if d.lifesteal or (d.lifestealIfEntangled and ts.chanrao > 0) then
			H().heal(npc, dealt * self.LIFESTEAL, "吸血")
			H().fx("lifesteal", target, npc, d.name)
		end
		-- 萬象纏身訣：單次木系傷害夠高 → 纏繞
		local needW = self:PVal(npc, "WanXiang", "bigHit", r)
		if isWood and needW > 0 and pts >= needW then
			self:AddChanRao(target, self:PVal(npc, "WanXiang", "bigHitChanRao", r))
		end
		self:Log("  → " .. H().name(target) .. " 受到 " .. pts .. " 點（×" .. self.K[r] .. "）")
		-- 燃焰訣：單次火系傷害夠高 → 灼燒
		local need = self:PVal(npc, "RanYan", "bigHit", r)
		if isFire and need > 0 and pts >= need then
			self:AddBurn(target, self:PVal(npc, "RanYan", "bigHitBurn", r), npc)
		end
	end
	if d.triggerYan and s.yan > 0 then
		local times = d.triggerYan + ((step.combo and d.combo.triggerYan) or 0)
		self:Hurt(target, s.yan * times * self.K[r], npc, "焰")
		self:Log("  → 觸發【焰】×" .. times .. "：" .. s.yan * times .. " 點")
	end
	if d.burn then self:AddBurn(target, val(d.burn, r), npc) end
	if step.combo and d.combo.burn then self:AddBurn(target, val(d.combo.burn, r), npc) end
	if d.burnedEntangle and ts.burn > 0 then self:AddChanRao(target, val(d.burnedEntangle, r)) end
	local diss = (d.dissipate or 0) + ((d.burnedDissipate and ts.burn > 0) and d.burnedDissipate or 0)
	if diss > 0 then self:Dissipate(target, ts, diss, npc, r) end
	if d.mirrorBurn and s.burn > 0 then self:AddBurn(target, s.burn, npc) end
	-- 竹山宗
	if d.poison then
		local n = val(d.poison, r)
		if step.id == "QingShe" then n = n + self:PVal(npc, "QingSheYao", "qingSheExtra", r) end
		self:AddPoison(target, n, npc)
	end
	if d.chanrao then self:AddChanRao(target, val(d.chanrao, r)) end
	if step.combo and d.combo.chanrao then self:AddChanRao(target, val(d.combo.chanrao, r)) end
	if step.combo and d.combo.randomDebuff then
		for _ = 1, d.combo.randomDebuff do
			local k = math.random(3)
			if k == 1 then
				self:AddPoison(target, 1, npc)
			elseif k == 2 then
				self:AddChanRao(target, 1)
			else
				self:AddBurn(target, 1, npc)
			end
		end
	end
	if d.triggerPoison and ts.poison > 0 then
		self:TickPoison(target, ts, 1)
		self:Log("  → 引毒：觸發中毒×" .. ts.poison)
	end
end

-- 消散靈氣：對方若也有五行靈氣就直接散掉，否則轉成等量靈氣傷害
function MCS:Dissipate(target, ts, n, from, r)
	local removed = 0
	for _ = 1, n do
		local pool = {}
		for _, e in ipairs(self.ELEMS) do
			if ts.qi[e] > 0 then pool[#pool + 1] = e end
		end
		if #pool == 0 then break end
		local e = pool[math.random(#pool)]
		ts.qi[e] = ts.qi[e] - 1
		removed = removed + 1
	end
	if removed < n then
		self:Hurt(target, (n - removed) * self.K[r], from, "靈氣潰散")
	end
end

---------------------------------------------------------------------------
-- 回合
---------------------------------------------------------------------------
function MCS:BeginBattle(npc, s, target)
	local r = H().realm(npc)
	s.inFight = true
	for _, e in ipairs(self.ELEMS) do s.qi[e] = 0 end
	s.juhuo, s.last, s.nextFire, s.turnT = 0, nil, 0, self.TURN * 0.6
	s.boostMu, s.nextWood, s.muUsed = 0, 0, 0
	s.huoW = self:PVal(npc, "ZhenYang", "huoWeight", r)
	s.muW = self:PVal(npc, "WanMu", "muWeight", r)
	s.qi.Huo = s.qi.Huo + self:PVal(npc, "LieYan", "startHuo", r)
	s.keepElem = self:Passive(npc, "ChunCao") and "Mu" or "Huo"
	if target ~= nil then
		local p = self:PVal(npc, "ZhenYu", "startPoison", r)
		if p > 0 then self:AddPoison(target, p, npc) end
		local c = self:PVal(npc, "QingTeng", "startChanRao", r)
		if c > 0 then self:AddChanRao(target, c) end
	end
	self:Log(H().name(npc) .. " 進入戰鬥，靈氣 " .. self:QiText(s, r))
end

function MCS:EndBattle(npc, s)
	s.inFight = false
	for _, e in ipairs(self.ELEMS) do s.qi[e] = 0 end
	self:SetYan(npc, s, 0)
	if s.huayan > 0 then self:SetHuaYan(npc, s, 0, nil) end
	s.mark = nil
	self:ClearStatuses(npc, s)
	-- 春草訣：戰鬥結束後恢復生命
	local heal = self:PVal(npc, "ChunCao", "winHeal", H().realm(npc))
	if heal > 0 then H().heal(npc, heal * self.K[H().realm(npc)], "春草訣") end
	H().showQi(npc, "未在戰鬥中")
end

-- 每個被追蹤的角色（不管是不是修士）都有自己的回合鐘，用來結算狀態
function MCS:StatusTurn(npc, s)
	self:TickBurn(npc, s)
	self:TickPoison(npc, s, 1)
	-- 纏繞：回合結束時清除
	if s.chanrao > 0 then
		s.chanrao = 0
		H().showStatus(npc, "ChanRao", 0)
	end
	if s.burn <= 0 and s.poison <= 0 and not s.practitioner then s.tracked = false end
end

function MCS:Turn(npc, s, target)
	local r = H().realm(npc)
	s.firstFireDone = false
	s.firstWoodDone = false
	s.yinduCount = 0
	-- 焚心訣：回合開始時敵方灼燒
	local fx = self:PVal(npc, "FenXin", "turnBurn", r)
	if fx > 0 then self:AddBurn(target, fx, npc) end

	local got = self:Absorb(npc, s, self.ABSORB[r])
	local plan, qiAfter = self:Plan(npc, s, target)
	s.qi = qiAfter
	self:Log(H().name(npc) .. " 回合：吸收 " .. got .. "，出手 " .. #plan .. " 招")
	for i, step in ipairs(plan) do
		self:After((i - 1) * self.CAST_GAP, function() self:Execute(npc, s, target, step) end)
	end
	self:After(#plan * self.CAST_GAP + 0.1, function() self:EndTurn(npc, s, target, r) end)
	s.busyUntil = self.clock + #plan * self.CAST_GAP + 0.1
end

function MCS:EndTurn(npc, s, target, r)
	if not H().alive(npc) then return end
	if s.huayan > 0 then
		-- 化焰：回合結束獲得灼燒×1；化焰訣/熔盾訣加成
		s.burn = math.min(self.BURN_CAP, s.burn + 1)
		s.burnK = self.K[r]
		s.burnFrom = H().id(npc)
		s.tracked = true
		H().showStatus(npc, "Burn", s.burn)
		local g = self:PVal(npc, "HuaYanJue", "huayanGain", r)
		if g > 0 then self:SetHuaYan(npc, s, s.huayan + g, target) end
		local sh = self:PVal(npc, "RongDun", "huayanShield", r)
		if sh > 0 then H().heal(npc, sh * self.K[r] * 0.2, "熔盾") end
	end
	-- 五毒蝕心訣：回合結束時敵方中毒
	local wp = self:PVal(npc, "WuDuShiXin", "turnPoison", r)
	if wp > 0 and H().alive(target) then self:AddPoison(target, wp, npc) end
	s.mark = nil
	local lost = self:Overflow(s, r)
	H().showQi(npc, self:QiText(s, r) .. (lost > 0 and ("，消散 " .. lost) or ""))
end

-- 受擊偵測：靈氣下降就視為被打（用於化焰反震、炙火印）
function MCS:CheckHit(npc, s)
	local ling = H().ling(npc)
	local drop = (s.lastLing or ling) - ling - (s.ignoreDrop or 0)
	s.ignoreDrop = 0
	if s.lastLing ~= nil and drop > 0.5 then
		local attacker = H().attacker(npc)
		if attacker ~= nil and H().alive(attacker) then
			local r = H().realm(npc)
			if s.huayan > 0 then
				-- 化焰：每次受到傷害時，反彈 1 點火屬性傷害
				self:Hurt(attacker, self.K[r], npc, "化焰反震")
				s.reflects = (s.reflects or 0) + 1
			end
			if s.mark then
				if s.mark.burn then self:AddBurn(attacker, s.mark.burn, npc) end
				if s.mark.chanrao then self:AddChanRao(attacker, s.mark.chanrao) end
				self:Log(H().name(npc) .. " 印記觸發（受擊反制）")
				s.mark = nil
			end
		end
	end
	s.lastLing = H().ling(npc)
end

function MCS:StepNpc(npc, s, dt)
	if s.practitioner then
		local fighting, target = H().fighting(npc)
		if fighting then
			s.outT = 0
			if not s.inFight then self:BeginBattle(npc, s, target) end
			if s.huayan > 0 or s.mark then self:CheckHit(npc, s) else s.lastLing, s.ignoreDrop = H().ling(npc), 0 end
			s.turnT = s.turnT + dt
			if s.turnT >= self.TURN and self.clock >= (s.busyUntil or 0) then
				s.turnT = 0
				self:StatusTurn(npc, s)
				if H().alive(npc) and H().alive(target) then self:Turn(npc, s, target) end
			end
			return
		elseif s.inFight then
			s.outT = s.outT + dt
			if s.outT > self.TURN * 2 then self:EndBattle(npc, s) end
		end
	end
	if s.tracked then
		-- 覓長生的狀態只存在於戰鬥中：會戰鬥的角色離開戰鬥一陣子後，清除灼燒／中毒／纏繞
		if H().canFight(npc) and not H().fighting(npc) then
			s.idleT = (s.idleT or 0) + dt
			if s.idleT > self.TURN * 2 then
				self:ClearStatuses(npc, s)
				return
			end
		else
			s.idleT = 0
		end
		s.turnT = s.turnT + dt
		if s.turnT >= self.TURN then
			s.turnT = 0
			self:StatusTurn(npc, s)
		end
	end
end

function MCS:ClearStatuses(npc, s)
	s.burn, s.poison, s.chanrao, s.idleT = 0, 0, 0, 0
	H().showStatus(npc, "Burn", 0)
	H().showStatus(npc, "Poison", 0)
	H().showStatus(npc, "ChanRao", 0)
	if not s.practitioner then s.tracked = false end
end

-- 主迴圈：由遊戲每幀呼叫（OnStep，遊戲時間）
function MCS:Update(dt)
	self.clock = self.clock + dt
	local due = self.timers
	self.timers = {}
	for _, t in ipairs(due) do
		if t.at <= self.clock then
			local ok, err = pcall(t.fn)
			if not ok then print("[MCS] timer error: " .. tostring(err)) end
		else
			self.timers[#self.timers + 1] = t
		end
	end
	self.acc = self.acc + dt
	if self.acc < 0.25 then return end
	local step = self.acc
	self.acc = 0
	for id, s in pairs(self.st) do
		if s.practitioner or s.tracked then
			local npc = H().find(id)
			if npc == nil or not H().alive(npc) then
				self.st[id] = nil
			else
				local ok, err = pcall(self.StepNpc, self, npc, s, step)
				if not ok then print("[MCS] step error: " .. tostring(err)) end
			end
		end
	end
end

-- 修士登記（由功法根節點的 modifier 每幀呼叫）
function MCS:Register(npc)
	local s = self:S(H().id(npc))
	s.practitioner = true
end

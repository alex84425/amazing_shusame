-- 覓長生·離火傳承：遊戲本體介面
-- 引擎（MCS_Core.lua）只透過這裡和《了不起的修仙模擬器》互動。

local MCS = GameMain:GetMod("MCS_LiHuo")
local XW = CS.XiaWorld

local EK = {
	Jin = XW.g_emElementKind.Jin, Mu = XW.g_emElementKind.Mu, Shui = XW.g_emElementKind.Shui,
	Huo = XW.g_emElementKind.Huo, Tu = XW.g_emElementKind.Tu,
}

local STATUS_MOD = {
	Burn = { mod = "MCS_St_Burn", name = "灼燒", desc = "回合開始時受到等同層數的火系傷害，之後移除一層。" },
	Yan = { mod = "MCS_St_Yan", name = "焰", desc = "每層使火系技能傷害提升。" },
	HuaYan = { mod = "MCS_St_HuaYan", name = "化焰", desc = "受到傷害時反震火傷；回合結束獲得灼燒×1；施展非火系技能便會脫離。" },
	ChanRao = { mod = "MCS_St_ChanRao", name = "纏繞", desc = "行動與法寶飛行變慢；回合結束時清除。" },
	Poison = { mod = "MCS_St_Poison", name = "中毒", desc = "回合結束時受到等同層數的木系傷害，層數不會自然減少。" },
}

local Host = {}
MCS.Host = Host

local function safe(fn, default)
	local ok, v = pcall(fn)
	if ok then return v end
	return default
end

function Host.id(npc) return npc.ID end

function Host.find(id)
	return ThingMgr:FindThingByID(id)
end

function Host.alive(t)
	return t ~= nil and safe(function() return not t.IsDeath end, false)
end

function Host.name(npc)
	return safe(function() return npc:GetName() end, "?")
end

-- 離火試煉木樁：打不壞的測試靶
local DUMMY = "Building_MCS_MuZhuang"
function Host.isDummy(t)
	return t ~= nil and safe(function() return t.def ~= nil and t.def.Name == DUMMY end, false)
end

-- 注意：safe() 只保留第一個回傳值，這裡要回傳兩個值（是否戰鬥、目標），所以自己處理 pcall
function Host.fighting(npc)
	local ok, fighting, target = pcall(function()
		local fb = npc.FightBody
		if fb == nil or not fb.IsFighting then return false end
		local t = fb.Target
		if t ~= nil and t.ThingType == g_emThingType.Npc and not t.IsDeath then
			return true, t
		end
		if Host.isDummy(t) then return true, t end
		return false
	end)
	if not ok then return false end
	return fighting, target
end

-- 會戰鬥的角色（有戰鬥身體的 NPC）；木樁等建築不算
function Host.canFight(t)
	return safe(function() return t.ThingType == g_emThingType.Npc and t.FightBody ~= nil end, false)
end

function Host.attacker(npc)
	local _, t = Host.fighting(npc)
	return t
end

-- 境界：看目前功法階段（Stage1 煉氣、Stage2 築基、Stage3 以上視為金丹）
function Host.realm(npc)
	local n = safe(function() return tonumber(string.match(npc.PropertyMgr.Practice.CurStage.Name, "%d+")) end, nil)
	if n ~= nil then return math.max(1, math.min(3, n)) end
	local lv = safe(function() return tostring(npc.PropertyMgr.Practice.GongStateLevel) end, "")
	if string.find(lv, "God") or string.find(lv, "Dan2") then return 3 end
	if string.find(lv, "Dan1") then return 2 end
	return 1
end

function Host.weight(npc, e)
	return safe(function() return npc.PropertyMgr.Practice:GetFiveBaseEfficiency(EK[e]) end, 1)
end

function Host.learned(npc, eso)
	return safe(function() return npc.LuaHelper:IsLearnedEsoteric(eso) end, false)
end

function Host.ling(npc)
	return safe(function() return npc.LingV end, 0)
end

function Host.lingRatio(npc)
	return safe(function()
		local max = npc.PropertyMgr:GetProperty("NpcLingMaxValue")
		if max <= 0 then return 1 end
		return npc.LingV / max
	end, 1)
end

-- 火系傷害：先打靈氣（修士的戰鬥血量），沒有靈氣的對象改打肉身
function Host.damage(target, amount, from, desc, elem)
	if amount <= 0 then return end
	local ek = EK[elem or "Huo"] or EK.Huo
	if Host.isDummy(target) then
		MCS:Meter(target, amount, from, desc)
		return
	end
	local ok = pcall(function()
		local body = target.LingV <= 0
		target:ReduceLingDamage(amount, ek, body, desc, from)
	end)
	if not ok then
		pcall(function() target:AddDamage("TheWholeBody", "Damage_MCS_Fire") end)
	end
end

function Host.heal(npc, amount, desc)
	pcall(function() npc:AddLing(amount) end)
end

-- 狀態用 modifier 顯示在角色面板上（層數 + 說明）
function Host.showStatus(npc, key, n)
	local def = STATUS_MOD[key]
	pcall(function()
		local pm = npc.PropertyMgr
		local m = pm:FindModifier(def.mod)
		if n <= 0 then
			if m ~= nil then npc:RemoveModifier(def.mod) end
			return
		end
		if m == nil then
			npc:AddModifier(def.mod, 1, false, n)
			m = pm:FindModifier(def.mod)
		end
		if m ~= nil then
			m.Stack = n
			m.Desc = def.desc .. "\n[color=#FF8A3C]目前 " .. n .. " 層[/color]"
		end
	end)
end

function Host.showQi(npc, text)
	pcall(function()
		for _, sc in pairs(MCS.SCHOOLS or {}) do
			local m = npc.PropertyMgr:FindModifier(sc.rootMod)
			if m ~= nil then
				m.Desc = "修習" .. sc.name .. "心法，戰鬥時依五行根基吸收五行靈氣。\n[color=#FF8A3C]五行靈氣：" .. text .. "[/color]"
			end
		end
	end)
end

function Host.fx(kind, from, to, arg)
	if MCS.FX ~= nil then
		pcall(MCS.FX, MCS, kind, from, to, arg)
	end
end

---------------------------------------------------------------------------
-- Mod 生命週期
---------------------------------------------------------------------------
function MCS:OnStep(dt)
	self:Update(dt)
end

function MCS:OnAfterLoad()
	self.st, self.timers = {}, {}
end

-- 功法根節點的 modifier：每幀把持有者登記為修士
local tbMod = GameMain:GetMod("_ModifierScript"):GetModifier("MCS_Root")
function tbMod:Step(modifier, npc, dt)
	MCS:Register(npc)
end

---------------------------------------------------------------------------
-- 快捷鍵（測試用）
--   LeftShift+5：選中的弟子解鎖《烈焰訣》並習得所有離火神通與功法
---------------------------------------------------------------------------
function MCS:OnSetHotKey()
	return {
		{ ID = "MCS_LiHuo_LearnAll", Name = "離火·一鍵習得（測試）", Type = "Mod", InitialKey1 = "LeftShift+Alpha5" },
		{ ID = "MCS_LiHuo_Order", Name = "覓長生·出招設定", Type = "Mod", InitialKey1 = "LeftShift+Alpha4" },
		{ ID = "MCS_ZhuShan_LearnAll", Name = "竹山·一鍵習得（測試）", Type = "Mod", InitialKey1 = "LeftShift+Alpha3" },
	}
end

-- 習得某門派全部傳承（school 預設離火門）
function MCS:LearnAll(npc, school)
	school = school or "LiHuo"
	local meta = self.SCHOOLS[school]
	local h = npc.LuaHelper
	h:UnLockGong(meta.gong)
	h:LearnEsoteric(self:EsoName(meta.root))
	for id, d in pairs(self.SKILLS) do if d.school == school then h:LearnEsoteric(self:EsoName(id)) end end
	for id, d in pairs(self.PASSIVES) do if d.school == school then h:LearnEsoteric(self:EsoName(id)) end end
	h:AddMsg(XT("[NAME]習得了" .. meta.name .. "全部傳承。"))
end

function MCS:OnHotKey(ID, state)
	if state ~= "down" then return end
	if ID == "MCS_LiHuo_Order" then
		local ok, err = pcall(self.OpenOrderWindow, self)
		if not ok then print("[MCS] order window " .. tostring(err)) end
		return
	end
	local school = (ID == "MCS_LiHuo_LearnAll" and "LiHuo") or (ID == "MCS_ZhuShan_LearnAll" and "ZhuShan") or nil
	if school == nil then return end
	local sel = WorldLua:GetSelectThing()
	if sel ~= nil and sel.ThingType == g_emThingType.Npc and sel.IsPlayerThing then
		local ok, err = pcall(self.LearnAll, self, sel, school)
		print("[MCS] learn all " .. tostring(ok) .. " " .. tostring(err))
	end
end

---------------------------------------------------------------------------
-- 傷害統計：打木樁時記錄每種來源的傷害，每 15 秒回報一次
---------------------------------------------------------------------------
MCS.meters = MCS.meters or {}

function MCS:Meter(dummy, amount, from, desc)
	local m = self.meters[dummy.ID]
	if m == nil or self.clock - m.last > 20 then
		m = { start = self.clock, total = 0, src = {}, report = self.clock, last = self.clock, who = nil }
		self.meters[dummy.ID] = m
	end
	m.total = m.total + amount
	m.src[desc or "?"] = (m.src[desc or "?"] or 0) + amount
	m.last = self.clock
	if from ~= nil then m.who = from end
	if self.clock - m.report >= 15 then
		m.report = self.clock
		self:MeterReport(dummy, m)
	end
end

function MCS:MeterReport(dummy, m)
	local secs = math.max(1, self.clock - m.start)
	local parts = {}
	for k, v in pairs(m.src) do parts[#parts + 1] = { k, v } end
	table.sort(parts, function(a, b) return a[2] > b[2] end)
	local srcText = {}
	for i = 1, math.min(6, #parts) do srcText[#srcText + 1] = string.format("%s %.0f", parts[i][1], parts[i][2]) end
	local s = self.st[dummy.ID]
	local text = string.format("【試煉木樁】%.0f 秒內離火總傷害 %.0f（每秒 %.1f），灼燒 %d 層。來源：%s",
		secs, m.total, m.total / secs, s and s.burn or 0, table.concat(srcText, "、"))
	print("[MCS] " .. text)
	if m.who ~= nil then
		pcall(function() m.who.LuaHelper:AddMsg(text) end)
	end
end

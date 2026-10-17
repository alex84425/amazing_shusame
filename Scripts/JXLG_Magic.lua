-- 九霄流光訣：神通邏輯 + 測試熱鍵

local VFX = GameMain:GetMod("JXLG_VFX")
local tbTable = GameMain:GetMod("MagicHelper")

local function getter(thing)
	local last = { 0, 0, 0 }
	return function()
		if thing ~= nil and not thing.IsDeath then
			local p = thing.Pos
			last = { p.x, p.y, p.z }
		end
		return last[1], last[2], last[3]
	end
end

local function alive(t)
	return t ~= nil and t.ThingType == g_emThingType.Npc and not t.IsDeath
end

-- 共用：讀條期間顯示蓄力光點；讀條結束才放出主特效
local function makeMagic(name, auraCol, check, cast)
	local tbMagic = tbTable:GetMagic(name)

	function tbMagic:TargetCheck(k, t)
		return check(self, t)
	end

	function tbMagic:MagicEnter(IDs, IsThing)
		self.targetId = IDs[0]
		self.target = ThingMgr:FindThingByID(self.targetId)
		VFX:Aura(getter(self.bind), auraCol, self.magic.Param1)
	end

	function tbMagic:MagicStep(dt, duration)
		self:SetProgress(duration / self.magic.Param1)
		if duration >= self.magic.Param1 then
			return 1
		end
		return 0
	end

	function tbMagic:MagicLeave(success)
		if success == true and alive(self.target) then
			cast(self.bind, self.target)
		end
		self.target = nil
	end

	function tbMagic:OnLoadData(tbData, IDs, IsThing)
		self.targetId = IDs[0]
		self.target = ThingMgr:FindThingByID(self.targetId)
	end
end

local function enemyCheck(self, t)
	if not alive(t) or t == self.bind then
		self:SetCheckMsg(XT("請選擇一個活著的目標"))
		return false
	end
	if t.IsPlayerThing then
		self:SetCheckMsg(XT("不能對自己人施展"))
		return false
	end
	return true
end

local function allyCheck(self, t)
	if not alive(t) or not t.IsPlayerThing then
		self:SetCheckMsg(XT("只能對門內弟子施展"))
		return false
	end
	return true
end

-- 實際效果（傷害 / 增益）在特效命中的那一刻才套用
local Cast = {}

function Cast.Sword(caster, target)
	VFX:Fx_Sword(getter(caster), getter(target), function()
		if alive(target) then
			target:AddDamage("TheWholeBody", "Damage_JXLG_Sword")
		end
	end)
end

function Cast.Lotus(caster, target)
	VFX:Fx_Lotus(getter(target), function()
		if alive(target) then
			target:AddModifier("Modifier_JXLG_Lotus")
		end
	end)
end

function Cast.Thunder(caster, target)
	VFX:Fx_Thunder(getter(target), function(i, n)
		if (i == 1 or i == n) and alive(target) then
			target:AddDamage("TheWholeBody", "Damage_JXLG_Thunder")
		end
	end)
end

function Cast.Phoenix(caster, target)
	VFX:Fx_Phoenix(getter(caster), getter(target), function()
		if alive(target) then
			target:AddDamage("TheWholeBody", "Damage_JXLG_Fire")
		end
	end)
end

makeMagic("JXLG_Magic_Phoenix", { 1.0, 0.5, 0.15 }, enemyCheck, Cast.Phoenix)
makeMagic("JXLG_Magic_Sword", { 0.55, 0.92, 1.0 }, enemyCheck, Cast.Sword)
makeMagic("JXLG_Magic_Lotus", { 0.62, 0.86, 1.0 }, allyCheck, Cast.Lotus)
makeMagic("JXLG_Magic_Thunder", { 0.72, 0.5, 1.0 }, enemyCheck, Cast.Thunder)

---------------------------------------------------------------------------
-- 測試熱鍵：不用學功法也能直接預覽特效（純視覺，不造成傷害）
--   LeftShift+7 / 8 / 9 ：在選中的角色（沒選就在滑鼠位置）播放三個特效
--   LeftShift+0         ：讓選中的弟子解鎖《九霄流光訣》
---------------------------------------------------------------------------
local Hot = GameMain:GetMod("JXLG_Hotkey")

function Hot:OnSetHotKey()
	return {
		{ ID = "JXLG_V2_Fx4", Name = "九霄·預覽朱雀焚天", Type = "Mod", InitialKey1 = "LeftShift+Alpha6" },
		{ ID = "JXLG_V2_Fx1", Name = "九霄·預覽流光劍雨", Type = "Mod", InitialKey1 = "LeftShift+Alpha7" },
		{ ID = "JXLG_V2_Fx2", Name = "九霄·預覽寒月冰蓮", Type = "Mod", InitialKey1 = "LeftShift+Alpha8" },
		{ ID = "JXLG_V2_Fx3", Name = "九霄·預覽紫霄雷印", Type = "Mod", InitialKey1 = "LeftShift+Alpha9" },
		{ ID = "JXLG_V2_Unlock", Name = "九霄·解鎖功法", Type = "Mod", InitialKey1 = "LeftShift+Alpha0" },
	}
end

local function mouseWorld()
	local cam = VFX:FindCamera()
	if cam == nil or cam:Equals(nil) then
		return 0, 0, 0
	end
	local m = CS.UnityEngine.Input.mousePosition
	local w = cam:ScreenToWorldPoint(CS.UnityEngine.Vector3(m.x, m.y, math.abs(cam.transform.position.z)))
	return w.x, w.y, 0
end

local function previewTargets()
	local sel = WorldLua:GetSelectThing()
	if alive(sel) then
		local g = getter(sel)
		local x, y, z = g()
		-- 劍雨需要施法者與目標兩個點：施法者放在目標左下方
		return function() return x - 5, y - 2, z end, g
	end
	local x, y, z = mouseWorld()
	return function() return x - 5, y - 2, z end, function() return x, y, z end
end

function Hot:OnHotKey(ID, state)
	if state ~= "down" or string.sub(ID, 1, 5) ~= "JXLG_" then
		return
	end
	VFX.log("hotkey " .. ID)
	if ID == "JXLG_V2_Unlock" then
		local sel = WorldLua:GetSelectThing()
		if alive(sel) and sel.IsPlayerThing then
			sel.LuaHelper:UnLockGong("Gong_JXLG")
			sel.LuaHelper:AddMsg(XT("[NAME]心有所感，參悟了《九霄流光訣》的法門。"))
		else
			VFX.log("先選中一名弟子再按 LeftShift+0")
		end
		return
	end
	local c, t = previewTargets()
	if ID == "JXLG_V2_Fx1" then
		VFX:Fx_Sword(c, t)
	elseif ID == "JXLG_V2_Fx2" then
		VFX:Fx_Lotus(t)
	elseif ID == "JXLG_V2_Fx3" then
		VFX:Fx_Thunder(t)
	elseif ID == "JXLG_V2_Fx4" then
		VFX:Fx_Phoenix(c, t)
	end
end

-- 九霄流光訣：Unity 原生 ParticleSystem 引擎
-- 每種粒子（火、煙、火星、電花…）各建一個常駐、世界座標的 ParticleSystem，
-- 由 Lua 用 Emit(EmitParams) 指定每顆粒子的位置/速度/大小/顏色，
-- 模擬、亂流、序列幀、拖尾等全部交給 Unity 原生程式碼在 GPU/C++ 端跑。

local VFX = GameMain:GetMod("JXLG_VFX")
local U = CS.UnityEngine
local PS = U.ParticleSystem
local Vector3 = U.Vector3

VFX.systems = VFX.systems or {}

local function log(s)
	print("[JXLG] " .. tostring(s))
end

local function isDead(obj)
	return obj == nil or obj:Equals(nil)
end

local function MMC(v)
	return PS.MinMaxCurve(v)
end

local function curve(points)
	local c = U.AnimationCurve()
	for _, p in ipairs(points) do
		c:AddKey(p[1], p[2])
	end
	return c
end

-- stops: {{t, r,g,b,a}, ...}
local function gradient(stops)
	local g = U.Gradient()
	local ck = CS.System.Array.CreateInstance(typeof(U.GradientColorKey), #stops)
	local ak = CS.System.Array.CreateInstance(typeof(U.GradientAlphaKey), #stops)
	for i, s in ipairs(stops) do
		ck[i - 1] = U.GradientColorKey(U.Color(s[2], s[3], s[4], 1), s[1])
		ak[i - 1] = U.GradientAlphaKey(s[5], s[1])
	end
	g:SetKeys(ck, ak)
	return g
end

local function findShader(names)
	for _, n in ipairs(names) do
		local s = U.Shader.Find(n)
		if not isDead(s) then
			return s, n
		end
	end
end

local ADD = { "Particles/Additive", "Legacy Shaders/Particles/Additive", "Mobile/Particles/Additive" }
local BLEND = { "Particles/Alpha Blended", "Legacy Shaders/Particles/Alpha Blended",
	"Mobile/Particles/Alpha Blended", "Sprites/Default" }

-- 每個模組獨立 pcall：某個模組不支援時只少那一層效果，不會整個失敗
local function try(tag, name, fn)
	local ok, err = pcall(fn)
	if not ok then
		log("ps " .. name .. " module " .. tag .. " failed: " .. tostring(err))
	end
	return ok
end

--[[ cfg:
	tex, blend("add"|"alpha"), order, max
	sheet = {x,y}          序列幀
	grad  = stops          生命週期顏色
	size  = points         生命週期尺寸曲線
	spin  = {min,max}      每秒旋轉（度）
	noise = {strength, freq, scroll}
	drag  = 0..1           每秒速度衰減
	gravity = g            重力倍率（負數往上飄）
	trail = {life, widthStart}
	stretch = {velScale, lenScale}
--]]
function VFX:MakeSystem(name, cfg)
	local go = U.GameObject("JXLG_ps_" .. name)
	local ps = go:AddComponent(typeof(PS))
	local r = go:GetComponent(typeof(U.ParticleSystemRenderer))
	ps:Stop(true, U.ParticleSystemStopBehavior.StopEmittingAndClear)

	local shader, sname = findShader(cfg.blend == "alpha" and BLEND or ADD)
	local mat = U.Material(shader)
	mat.mainTexture = self.textures[cfg.tex]

	try("main", name, function()
		local m = ps.main
		m.loop = true
		m.playOnAwake = false
		m.simulationSpace = U.ParticleSystemSimulationSpace.World
		m.maxParticles = cfg.max or 1500
		m.startLifetime = MMC(1)
		m.startSpeed = MMC(0)
		m.startSize = MMC(1)
		m.gravityModifier = MMC(cfg.gravity or 0)
	end)
	try("unscaled", name, function()
		local m = ps.main
		m.useUnscaledTime = true
	end)
	try("emission", name, function()
		local e = ps.emission
		e.enabled = false
	end)
	try("shape", name, function()
		local s = ps.shape
		s.enabled = false
	end)
	if cfg.sheet then
		try("sheet", name, function()
			local ts = ps.textureSheetAnimation
			ts.enabled = true
			ts.numTilesX = cfg.sheet[1]
			ts.numTilesY = cfg.sheet[2]
			ts.frameOverTime = PS.MinMaxCurve(1, curve({ { 0, 0 }, { 1, 1 } }))
			ts.cycleCount = 1
		end)
	end
	if cfg.grad then
		try("color", name, function()
			local c = ps.colorOverLifetime
			c.enabled = true
			c.color = PS.MinMaxGradient(gradient(cfg.grad))
		end)
	end
	if cfg.size then
		try("size", name, function()
			local s = ps.sizeOverLifetime
			s.enabled = true
			s.size = PS.MinMaxCurve(1, curve(cfg.size))
		end)
	end
	if cfg.spin then
		try("spin", name, function()
			local ro = ps.rotationOverLifetime
			ro.enabled = true
			ro.z = PS.MinMaxCurve(math.rad(cfg.spin[1]), math.rad(cfg.spin[2]))
		end)
	end
	if cfg.noise then
		try("noise", name, function()
			local n = ps.noise
			n.enabled = true
			n.strength = MMC(cfg.noise[1])
			n.frequency = cfg.noise[2]
			n.scrollSpeed = MMC(cfg.noise[3] or 0.5)
			n.damping = true
			n.octaveCount = 2
		end)
	end
	if cfg.drag then
		try("drag", name, function()
			local lv = ps.limitVelocityOverLifetime
			lv.enabled = true
			lv.limit = MMC(0)
			lv.dampen = cfg.drag
		end)
	end
	if cfg.trail then
		try("trail", name, function()
			local t = ps.trails
			t.enabled = true
			t.ratio = 1
			t.lifetime = MMC(cfg.trail[1])
			t.minVertexDistance = 0.05
			t.dieWithParticles = true
			t.inheritParticleColor = true
			t.sizeAffectsWidth = true
			t.widthOverTrail = PS.MinMaxCurve(cfg.trail[2] or 1, curve({ { 0, 1 }, { 1, 0 } }))
			local tm = U.Material(shader)
			tm.mainTexture = self.textures.beam
			r.trailMaterial = tm
		end)
	end
	try("renderer", name, function()
		r.sharedMaterial = mat
		r.sortingLayerName = self.sortLayer
		r.sortingOrder = cfg.order or 200
		if cfg.stretch then
			r.renderMode = U.ParticleSystemRenderMode.Stretch
			r.velocityScale = cfg.stretch[1]
			r.lengthScale = cfg.stretch[2]
		else
			r.renderMode = U.ParticleSystemRenderMode.Billboard
		end
	end)

	ps:Play()
	local sys = { go = go, ps = ps, r = r, ep = PS.EmitParams(), cfg = cfg }
	self.systems[name] = sys
	log("ps " .. name .. " ready (" .. tostring(sname) .. ")")
	return sys
end

-- 所有粒子系統的定義
local DEFS = {
	fire = { tex = "fire", blend = "add", order = 210, max = 6000, sheet = { 4, 4 },
		grad = { { 0, 1, 1, 1, 0 }, { 0.08, 1, 1, 1, 1 }, { 0.5, 1, 0.75, 0.45, 0.9 }, { 1, 0.6, 0.15, 0.05, 0 } },
		size = { { 0, 0.4 }, { 0.25, 1 }, { 1, 0.6 } }, spin = { -40, 40 }, noise = { 0.3, 0.7, 0.8 }, drag = 0.08 },
	smoke = { tex = "smoke", blend = "alpha", order = 190, max = 1500, sheet = { 4, 4 },
		grad = { { 0, 1, 1, 1, 0 }, { 0.15, 1, 1, 1, 0.75 }, { 1, 1, 1, 1, 0 } },
		size = { { 0, 0.5 }, { 1, 1.6 } }, spin = { -25, 25 }, noise = { 0.5, 0.35, 0.3 }, drag = 0.05, gravity = -0.03 },
	ember = { tex = "core", blend = "add", order = 230, max = 1500,
		grad = { { 0, 1, 1, 1, 1 }, { 0.7, 1, 1, 1, 0.9 }, { 1, 1, 1, 1, 0 } },
		size = { { 0, 1 }, { 1, 0.2 } }, noise = { 1.2, 1.2, 1.0 }, drag = 0.04, gravity = 0.15,
		trail = { 0.25, 0.6 } },
	spark = { tex = "core", blend = "add", order = 235, max = 1500,
		grad = { { 0, 1, 1, 1, 1 }, { 1, 1, 1, 1, 0 } },
		size = { { 0, 1 }, { 1, 0.3 } }, drag = 0.12, stretch = { 0.08, 1.5 } },
	glow = { tex = "glow", blend = "add", order = 180, max = 2500,
		grad = { { 0, 1, 1, 1, 0 }, { 0.1, 1, 1, 1, 1 }, { 1, 1, 1, 1, 0 } },
		size = { { 0, 0.7 }, { 1, 1.2 } } },
	mist = { tex = "smoke", blend = "add", order = 185, max = 800, sheet = { 4, 4 },
		grad = { { 0, 1, 1, 1, 0 }, { 0.2, 1, 1, 1, 0.5 }, { 1, 1, 1, 1, 0 } },
		size = { { 0, 0.6 }, { 1, 1.5 } }, spin = { -20, 20 }, noise = { 0.4, 0.4, 0.3 }, drag = 0.05 },
}

-- 離線預覽器（Tools/previewer）會讀這份定義來模擬粒子
VFX.PS_DEFS = DEFS

function VFX:Sys(name)
	local s = self.systems[name]
	if s ~= nil and not isDead(s.go) then
		return s
	end
	if not self:Init() then
		return nil
	end
	return self:MakeSystem(name, DEFS[name])
end

-- 發射一顆（或 n 顆相同參數的）粒子
-- o: x y z vx vy size life col{r,g,b,a(0-1)} rot n
function VFX:Emit(name, o)
	local s = self:Sys(name)
	if s == nil then
		return
	end
	local ep = s.ep
	ep.position = Vector3(o.x, o.y, o.z)
	ep.velocity = Vector3((o.vx or 0) * self.S, (o.vy or 0) * self.S, 0)
	ep.startSize = (o.size or 1) * self.S
	ep.startLifetime = o.life or 1
	local c = o.col or { 1, 1, 1, 1 }
	ep.startColor = U.Color32(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255),
		math.floor((c[4] or 1) * 255))
	ep.rotation = o.rot or math.random() * 360
	ep.applyShapeToPosition = false
	s.ps:Emit(ep, o.n or 1)
end

-- 換地圖時重建
function VFX:ResetSystems()
	for _, s in pairs(self.systems) do
		if not isDead(s.go) then
			U.Object.Destroy(s.go)
		end
	end
	self.systems = {}
end

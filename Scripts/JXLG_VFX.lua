-- 九霄流光訣：自製視覺特效引擎
-- 不使用遊戲內建特效：貼圖由 Tools/make_textures.py 產生，
-- 這裡直接用 Unity 的 SpriteRenderer / LineRenderer 在地圖上畫出來。

local VFX = GameMain:GetMod("JXLG_VFX")
local U = CS.UnityEngine
local Vector3, Color = U.Vector3, U.Color

VFX.S = VFX.S or 1.0          -- 全域尺寸倍率，可在控制台調整：GameMain:GetMod("JXLG_VFX").S = 1.5
VFX.ready = false
VFX.failed = false
VFX.parts = {}
VFX.lines = {}
VFX.timers = {}
VFX.pool = {}
VFX.linePool = {}
VFX.textures = {}
VFX.sprites = {}
VFX.clock = 0

local TEX = { "glow", "core", "ring", "spark", "blade", "trail", "beam",
	"slash", "petal", "snow", "rune_outer", "rune_inner", "fire", "smoke" }

local function log(s)
	print("[JXLG] " .. tostring(s))
end
VFX.log = log

local function isDead(obj)
	return obj == nil or obj:Equals(nil)
end

---------------------------------------------------------------------------
-- 初始化：載入貼圖、建立材質、決定排序圖層
---------------------------------------------------------------------------
function VFX:ModDir()
	return U.Application.dataPath .. "/../Mods/JiuXiaoLiuGuang/"
end

function VFX:FindCamera()
	local cam = U.Camera.main
	if isDead(cam) then
		local go = U.GameObject.Find("MainCamera")
		if not isDead(go) then
			cam = go:GetComponent(typeof(U.Camera))
		end
	end
	return cam
end

function VFX:Init()
	if self.ready then
		return true
	end
	if self.failed then
		return false
	end
	local ok, err = pcall(function()
		local dir = self:ModDir() .. "Tex/"
		for _, n in ipairs(TEX) do
			local path = dir .. n .. ".png"
			if not CS.System.IO.File.Exists(path) then
				error("missing texture " .. path)
			end
			local tex = U.Texture2D(2, 2, U.TextureFormat.RGBA32, false)
			U.ImageConversion.LoadImage(tex, CS.System.IO.File.ReadAllBytes(path))
			tex.wrapMode = U.TextureWrapMode.Clamp
			tex.filterMode = U.FilterMode.Bilinear
			self.textures[n] = tex
			-- 最長邊 = 1 個世界單位，之後全部用 scale 控制大小
			local ppu = math.max(tex.width, tex.height)
			self.sprites[n] = U.Sprite.Create(tex, U.Rect(0, 0, tex.width, tex.height), U.Vector2(0.5, 0.5), ppu)
		end

		local shader
		for _, sn in ipairs({ "Particles/Additive", "Legacy Shaders/Particles/Additive",
			"Mobile/Particles/Additive", "Sprites/Default" }) do
			shader = U.Shader.Find(sn)
			if not isDead(shader) then
				self.shaderName = sn
				break
			end
		end
		self.matSprite = U.Material(shader)
		self.matLine = U.Material(shader)
		self.matLine.mainTexture = self.textures.beam

		local names = {}
		local layers = U.SortingLayer.layers
		for i = 0, layers.Length - 1 do
			names[#names + 1] = layers[i].name
		end
		self.sortLayer = names[#names]
		for _, n in ipairs(names) do
			if n == "Effect" then
				self.sortLayer = n
			end
		end

		local cam = self:FindCamera()
		self.camZ = isDead(cam) and -10 or cam.transform.position.z
		log("ready. shader=" .. self.shaderName .. " layer=" .. self.sortLayer ..
			" layers=" .. table.concat(names, ",") .. " camZ=" .. self.camZ ..
			" ortho=" .. tostring(not isDead(cam) and cam.orthographic))
	end)
	if not ok then
		self.failed = true
		log("init failed: " .. tostring(err))
		return false
	end
	self.ready = true
	return true
end

-- 特效放在角色平面與鏡頭之間，確保畫在角色上方
function VFX:FxZ(z)
	local dz = (self.camZ or -10) - z
	local step = dz < 0 and -1.5 or 1.5
	if math.abs(dz) < 3 then
		step = dz * 0.5
	end
	return z + step
end

---------------------------------------------------------------------------
-- 物件池
---------------------------------------------------------------------------
function VFX:GetSprite()
	local o = table.remove(self.pool)
	while o ~= nil and isDead(o.go) do
		o = table.remove(self.pool)
	end
	if o == nil then
		local go = U.GameObject("JXLG_fx")
		local sr = go:AddComponent(typeof(U.SpriteRenderer))
		sr.sharedMaterial = self.matSprite
		sr.sortingLayerName = self.sortLayer
		o = { go = go, tr = go.transform, sr = sr }
	end
	o.go:SetActive(true)
	return o
end

function VFX:GetLine()
	local o = table.remove(self.linePool)
	while o ~= nil and isDead(o.go) do
		o = table.remove(self.linePool)
	end
	if o == nil then
		local go = U.GameObject("JXLG_line")
		local lr = go:AddComponent(typeof(U.LineRenderer))
		lr.sharedMaterial = self.matLine
		lr.useWorldSpace = true
		lr.sortingLayerName = self.sortLayer
		lr.textureMode = U.LineTextureMode.Stretch
		lr.numCapVertices = 2
		o = { go = go, lr = lr }
	end
	o.go:SetActive(true)
	return o
end

local function release(pool, o)
	if not isDead(o.go) then
		o.go:SetActive(false)
		pool[#pool + 1] = o
	end
end

---------------------------------------------------------------------------
-- 工具
---------------------------------------------------------------------------
local E = {}
VFX.E = E
function E.outQuad(t) return 1 - (1 - t) * (1 - t) end
function E.inQuad(t) return t * t end
function E.inOut(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end
function E.outBack(t)
	local c = 1.9
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

function VFX:Rand(a, b)
	return a + math.random() * (b - a)
end

function VFX:After(delay, fn)
	self.timers[#self.timers + 1] = { at = self.clock + delay, fn = fn }
end

-- 連續生成：每 interval 秒呼叫一次 fn(經過時間)，共 duration 秒
function VFX:Every(interval, duration, fn, delay)
	local start = self.clock + (delay or 0)
	local rec
	rec = function()
		local el = self.clock - start
		if el > duration then
			return
		end
		fn(el)
		self.timers[#self.timers + 1] = { at = self.clock + interval, fn = rec }
	end
	self.timers[#self.timers + 1] = { at = start, fn = rec }
end

---------------------------------------------------------------------------
-- 粒子
-- spec: tex x y z | vx vy drag | life | s0 s1 (尺寸) sx sy (長寬比)
--       rot vrot | col{r,g,b} a fin fout | order | upd(p,t,dt) | ease
---------------------------------------------------------------------------
function VFX:Spawn(spec)
	if not self:Init() then
		return nil
	end
	local p = spec
	p.o = self:GetSprite()
	p.o.sr.sprite = self.sprites[p.tex]
	p.o.sr.sortingOrder = p.order or 100
	p.age = 0
	p.life = p.life or 1
	p.vx, p.vy = p.vx or 0, p.vy or 0
	p.drag = p.drag or 0
	p.s0 = p.s0 or 1
	p.s1 = p.s1 or p.s0
	p.sx, p.sy = p.sx or 1, p.sy or 1
	p.rot, p.vrot = p.rot or 0, p.vrot or 0
	p.col = p.col or { 1, 1, 1 }
	p.a = p.a or 1
	p.fin = p.fin or 0.1
	p.fout = p.fout or 0.4
	p.alpha = 1
	self:ApplyPart(p, 0)
	self.parts[#self.parts + 1] = p
	return p
end

function VFX:ApplyPart(p, t)
	local k = p.ease and p.ease(t) or t
	local s = (p.s0 + (p.s1 - p.s0) * k) * self.S
	local env = 1
	if t < p.fin then
		env = t / p.fin
	elseif t > 1 - p.fout then
		env = (1 - t) / p.fout
	end
	local c = p.col
	p.o.tr.position = Vector3(p.x, p.y, p.z)
	p.o.tr.localScale = Vector3(s * p.sx, s * p.sy, 1)
	p.o.tr.localEulerAngles = Vector3(0, 0, p.rot)
	p.o.sr.color = Color(c[1], c[2], c[3], p.a * env * p.alpha)
end

function VFX:StepPart(p, dt)
	p.age = p.age + dt
	local t = p.age / p.life
	if t >= 1 or p.kill then
		return false
	end
	if p.drag > 0 then
		local f = math.max(0, 1 - p.drag * dt)
		p.vx, p.vy = p.vx * f, p.vy * f
	end
	p.x = p.x + p.vx * dt * self.S
	p.y = p.y + p.vy * dt * self.S
	p.rot = p.rot + p.vrot * dt
	if p.upd then
		p.upd(p, t, dt)
	end
	self:ApplyPart(p, t)
	return true
end

---------------------------------------------------------------------------
-- 閃電（LineRenderer），每 refresh 秒重新生成折線造成閃爍
---------------------------------------------------------------------------
function VFX:Bolt(x0, y0, x1, y1, depth, rough)
	local pts = { { x0, y0 }, { x1, y1 } }
	local off = rough
	for _ = 1, depth do
		local np = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dy * dy) + 1e-6
			local o = (math.random() * 2 - 1) * off
			np[#np + 1] = { mx - dy / len * o, my + dx / len * o }
			np[#np + 1] = b
		end
		pts = np
		off = off * 0.55
	end
	return pts
end

-- spec: gen() -> pts, z, width, col, a, life, refresh, order
function VFX:Line(spec)
	if not self:Init() then
		return nil
	end
	local l = spec
	l.o = self:GetLine()
	l.age = 0
	l.next = 0
	l.o.lr.sortingOrder = l.order or 150
	self.lines[#self.lines + 1] = l
	self:StepLine(l, 0)
	return l
end

function VFX:StepLine(l, dt)
	l.age = l.age + dt
	local t = l.age / l.life
	if t >= 1 then
		return false
	end
	local lr = l.o.lr
	if l.age >= l.next then
		l.next = l.age + (l.refresh or 0.05)
		local pts = l.gen()
		lr.positionCount = #pts
		for i, q in ipairs(pts) do
			lr:SetPosition(i - 1, Vector3(q[1], q[2], l.z))
		end
	end
	local a = (l.a or 1) * (1 - t) ^ 0.6 * (0.75 + 0.25 * math.random())
	local c = l.col
	lr.startColor = Color(c[1], c[2], c[3], a)
	lr.endColor = Color(c[1], c[2], c[3], a * 0.6)
	lr.widthMultiplier = l.width * self.S
	return true
end

---------------------------------------------------------------------------
-- 主迴圈（每個畫面呼叫）
---------------------------------------------------------------------------
function VFX:Tick(dt)
	self.clock = self.clock + dt
	local due = self.timers
	self.timers = {}
	for _, tm in ipairs(due) do
		if tm.at <= self.clock then
			tm.fn()
		else
			self.timers[#self.timers + 1] = tm
		end
	end
	for i = #self.parts, 1, -1 do
		local p = self.parts[i]
		if isDead(p.o.go) or not self:StepPart(p, dt) then
			release(self.pool, p.o)
			table.remove(self.parts, i)
		end
	end
	for i = #self.lines, 1, -1 do
		local l = self.lines[i]
		if isDead(l.o.go) or not self:StepLine(l, dt) then
			release(self.linePool, l.o)
			table.remove(self.lines, i)
		end
	end
end

function VFX:Clear()
	for _, p in ipairs(self.parts) do
		release(self.pool, p.o)
	end
	for _, l in ipairs(self.lines) do
		release(self.linePool, l.o)
	end
	self.parts, self.lines, self.timers = {}, {}, {}
end

function VFX:OnRender(dt)
	if not self.ready then
		return
	end
	local rdt = U.Time.unscaledDeltaTime
	if rdt > 0.05 then
		rdt = 0.05
	end
	local ok, err = pcall(self.Tick, self, rdt)
	if not ok then
		log("tick error: " .. tostring(err))
		self:Clear()
	end
end

function VFX:OnEnter()
	self:Init()
end

function VFX:OnLeave()
	self:Clear()
end

function VFX:OnAfterLoad()
	-- 換地圖後舊物件可能已被銷毀，重新抓鏡頭並清空
	self:Clear()
	self.pool, self.linePool = {}, {}
	if self.ready then
		local cam = self:FindCamera()
		self.camZ = isDead(cam) and self.camZ or cam.transform.position.z
	end
end

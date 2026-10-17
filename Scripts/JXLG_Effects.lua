-- 九霄流光訣：三個神通的視覺特效編排
-- 每個效果都是一條時間軸：After/Every 排程 + Spawn 粒子 + Line 閃電。
-- getT() 回傳目標目前位置 (x, y, z)，讓特效能追著會移動的目標。

local VFX = GameMain:GetMod("JXLG_VFX")
-- 腳本載入順序不固定，緩動函數延遲到使用時才向引擎取
local E = setmetatable({}, { __index = function(_, k) return VFX.E[k] end })
local R = function(a, b) return VFX:Rand(a, b) end
local deg = math.deg
local atan2 = math.atan2 or math.atan   -- LuaJIT/5.1 與 5.3 相容

local SWORD = { 0.55, 0.92, 1.0 }
local GOLD = { 1.0, 0.86, 0.5 }
local ICE = { 0.62, 0.86, 1.0 }
local WHITE = { 1, 1, 1 }
local VIOLET = { 0.72, 0.5, 1.0 }
local LILAC = { 0.9, 0.8, 1.0 }

local function burst(x, y, z, n, col, speed, size, life)
	for _ = 1, n do
		local a = R(0, math.pi * 2)
		local v = R(speed * 0.5, speed)
		VFX:Spawn({ tex = "spark", x = x, y = y, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
			drag = 5, life = R(life * 0.6, life), s0 = size, s1 = size * 0.2, rot = R(0, 90), vrot = R(-200, 200),
			col = col, fin = 0.05, fout = 0.6, order = 160 })
	end
end

local function ring(x, y, z, s0, s1, col, life, a)
	VFX:Spawn({ tex = "ring", x = x, y = y, z = z, s0 = s0, s1 = s1, life = life, col = col, a = a or 0.9,
		ease = E.outQuad, fin = 0.02, fout = 0.8, order = 120 })
end

local function flash(x, y, z, s, col, life)
	VFX:Spawn({ tex = "glow", x = x, y = y, z = z, s0 = s * 0.6, s1 = s, life = life, col = col, a = 1,
		ease = E.outQuad, fin = 0.05, fout = 0.85, order = 110 })
end

-- 施法蓄力：光點從腳下升起，繞著施法者
function VFX:Aura(getC, col, duration)
	self:Every(0.06, duration, function()
		local x, y, z = getC()
		local a = R(0, math.pi * 2)
		local r = R(0.3, 0.7)
		self:Spawn({ tex = "core", x = x + math.cos(a) * r, y = y + math.sin(a) * r * 0.5 - 0.2, z = self:FxZ(z),
			vx = -math.cos(a) * 0.3, vy = R(0.8, 1.4), drag = 1, life = R(0.6, 1.0),
			s0 = R(0.12, 0.2), s1 = 0.02, col = col, a = 0.9, fin = 0.2, fout = 0.5 })
	end)
end

---------------------------------------------------------------------------
-- 流光劍雨：七柄光劍在頭頂排成扇形，依序破空射向目標
---------------------------------------------------------------------------
function VFX:Fx_Sword(getC, getT, onHit)
	if not self:Init() then
		return
	end
	local cx, cy, cz = getC()
	local z = self:FxZ(cz)
	local N = 7

	-- 聚氣：光點向施法者匯聚
	self:Every(0.025, 0.6, function()
		local a = R(0, math.pi * 2)
		local r = R(1.4, 2.0)
		local sx, sy = cx + math.cos(a) * r, cy + math.sin(a) * r
		self:Spawn({ tex = "spark", x = sx, y = sy, z = z, life = 0.4, s0 = 0.25, s1 = 0.05, col = SWORD, fout = 0.3,
			upd = function(p, t)
				local k = E.inQuad(t)
				p.x = sx + (cx - sx) * k
				p.y = sy + (cy + 0.6 - sy) * k
			end })
	end)

	for i = 1, N do
		local fan = math.rad(90 + (i - (N + 1) / 2) * 17)
		local ax, ay = cx + math.cos(fan) * 1.5, cy + 0.5 + math.sin(fan) * 1.1
		local launch = 0.75 + (i - 1) * 0.09
		local last = (i == N)
		self:After(0.05 * i, function()
			local halo = self:Spawn({ tex = "glow", x = ax, y = ay, z = z, s0 = 0, s1 = 0.7, life = launch - 0.05 * i + 0.05,
				col = SWORD, a = 0.55, ease = E.outBack, fin = 0.1, fout = 0.15, order = 90 })
			local state = { x = ax, y = ay, fired = false, done = false }
			local blade
			blade = self:Spawn({ tex = "blade", x = ax, y = ay, z = z, s0 = 0, s1 = 1.1, sy = 1, life = 4,
				col = WHITE, a = 1, fin = 0.02, fout = 0.02, order = 130,
				upd = function(p, t, dt)
					local tx, ty = getT()
					local age = p.age + 0.05 * i
					if age < launch then
						-- 懸浮瞄準
						local k = math.min(1, p.age / 0.3)
						p.s0, p.s1 = 1.1 * E.outBack(k), 1.1 * E.outBack(k)
						p.x = ax
						p.y = ay + math.sin((age) * 7 + i) * 0.06
						p.rot = deg(atan2(ty - p.y, tx - p.x))
						return
					end
					if not state.fired then
						state.fired = true
						state.t0 = p.age
						state.sx, state.sy = p.x, p.y
						state.jx, state.jy = R(-0.25, 0.25), R(-0.25, 0.25)
						local dx, dy = tx - p.x, ty - p.y
						state.dur = math.max(0.12, math.sqrt(dx * dx + dy * dy) / 16)
						VFX:Spawn({ tex = "ring", x = p.x, y = p.y, z = z, s0 = 0.2, s1 = 0.9, life = 0.2, col = SWORD,
							a = 0.7, ease = E.outQuad, order = 120 })
					end
					local u = (p.age - state.t0) / state.dur
					local px, py = p.x, p.y
					local ex, ey = tx + state.jx, ty + state.jy
					if u >= 1 then
						p.kill = true
						-- 命中：斬痕 + 火花 + 衝擊環
						local sl = R(0, 360)
						VFX:Spawn({ tex = "slash", x = ex, y = ey, z = z, s0 = 0.4, s1 = last and 2.2 or 1.4, rot = sl,
							life = 0.28, col = last and GOLD or SWORD, ease = E.outQuad, fin = 0.02, fout = 0.7, order = 170 })
						burst(ex, ey, z, last and 16 or 6, last and GOLD or SWORD, last and 8 or 5, 0.35, 0.45)
						for _ = 1, last and 26 or 7 do
							local a = R(0, math.pi * 2)
							local v = R(8, 15)
							VFX:Emit("spark", { x = ex, y = ey, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
								size = R(0.08, 0.14), life = R(0.2, 0.35), col = last and { 1, 0.9, 0.6, 1 } or { 0.7, 0.95, 1, 1 } })
						end
						if last then
							for _ = 1, 20 do
								local a = R(0, math.pi * 2)
								local v = R(3, 8)
								VFX:Emit("ember", { x = ex, y = ey, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v + 1,
									size = R(0.08, 0.15), life = R(0.7, 1.2), col = { 1, 0.85, 0.45, 1 } })
							end
						end
						ring(ex, ey, z, 0.2, last and 2.6 or 1.1, last and GOLD or SWORD, last and 0.45 or 0.3)
						if last then
							VFX:Spawn({ tex = "slash", x = ex, y = ey, z = z, s0 = 0.4, s1 = 2.2, rot = sl + 90, life = 0.32,
								col = WHITE, ease = E.outQuad, fin = 0.02, fout = 0.7, order = 171 })
							flash(ex, ey, z, 3.2, GOLD, 0.4)
							if onHit then
								onHit()
							end
						end
						return
					end
					local k = E.inQuad(u)
					p.x = state.sx + (ex - state.sx) * k
					p.y = state.sy + (ey - state.sy) * k
					p.rot = deg(atan2(ey - p.y, ex - p.x))
					-- 殘影 + 拖尾
					VFX:Spawn({ tex = "blade", x = p.x, y = p.y, z = z, s0 = 1.1, rot = p.rot, life = 0.12,
						col = SWORD, a = 0.45, fin = 0, fout = 1, order = 125 })
					local mx, my = p.x - px, p.y - py
					local seg = math.sqrt(mx * mx + my * my)
					if seg > 0.01 then
						local len = math.min(2.8, seg * 6)
						VFX:Spawn({ tex = "trail", x = p.x - math.cos(math.rad(p.rot)) * len * 0.5,
							y = p.y - math.sin(math.rad(p.rot)) * len * 0.5, z = z, s0 = len, sy = 1, rot = p.rot,
							life = 0.16, col = SWORD, a = 0.8, fin = 0, fout = 1, order = 124 })
					end
				end })
			if halo then
				halo.upd = function(p)
					if blade then
						p.x, p.y = blade.x, blade.y
					end
				end
			end
		end)
	end
end

---------------------------------------------------------------------------
-- 寒月冰蓮：雙層冰蓮在目標腳下綻放、旋轉，霜氣升騰，最後花瓣四散
---------------------------------------------------------------------------
function VFX:Fx_Lotus(getT, onBloom)
	if not self:Init() then
		return
	end
	local tx, ty, tz = getT()
	local z = self:FxZ(tz)
	local bloomAt = 2.2
	local total = 2.9

	ring(tx, ty, z, 0.2, 2.6, ICE, 0.6, 0.8)
	VFX:Spawn({ tex = "glow", x = tx, y = ty, z = z, s0 = 1.5, s1 = 3.4, life = total, col = ICE, a = 0.45,
		ease = E.outQuad, fin = 0.15, fout = 0.3, order = 80 })
	VFX:Spawn({ tex = "rune_inner", x = tx, y = ty, z = z, s0 = 0.5, s1 = 2.4, vrot = 25, life = total, col = ICE,
		a = 0.5, ease = E.outBack, fin = 0.1, fout = 0.25, order = 85 })

	local function layer(n, len, width, spin, phase, delay, col, order)
		for i = 1, n do
			local base = phase + (i - 1) * 360 / n
			VFX:After(delay + i * 0.03, function()
				local scatter = nil
				VFX:Spawn({ tex = "petal", x = tx, y = ty, z = z, s0 = len, sx = width, sy = 1, life = total - delay,
					col = col, a = 0.85, fin = 0.05, fout = 0.12, order = order,
					upd = function(p, t, dt)
						local age = p.age + delay
						local ang = base + spin * age
						if age < bloomAt then
							-- 綻放：花瓣從閉合到張開（長度與張角同時成長）
							local open = E.outBack(math.min(1, p.age / 0.7))
							p.s0 = len * (0.25 + 0.75 * open)
							p.s1 = p.s0
							p.sx = width * (0.35 + 0.65 * open)
							local dist = p.s0 * VFX.S * 0.5 * (0.6 + 0.4 * open)
							p.x = tx + math.cos(math.rad(ang)) * dist
							p.y = ty + math.sin(math.rad(ang)) * dist
							p.rot = ang - 90
						else
							if not scatter then
								scatter = { x = p.x, y = p.y, vx = math.cos(math.rad(ang)) * R(3, 5),
									vy = math.sin(math.rad(ang)) * R(3, 5), r = p.rot, vr = R(-300, 300) }
							end
							local k = age - bloomAt
							local f = math.max(0, 1 - 4 * dt)
							scatter.vx, scatter.vy = scatter.vx * f, scatter.vy * f
							scatter.x, scatter.y = scatter.x + scatter.vx * dt, scatter.y + scatter.vy * dt
							p.x, p.y = scatter.x, scatter.y
							p.rot = scatter.r + scatter.vr * k
							p.alpha = math.max(0, 1 - k / 0.6)
						end
					end })
			end)
		end
	end
	layer(8, 1.5, 0.95, 18, 0, 0.1, ICE, 100)
	layer(8, 1.0, 0.85, -30, 22.5, 0.3, WHITE, 101)

	-- 花心
	VFX:Spawn({ tex = "core", x = tx, y = ty, z = z, s0 = 0.2, s1 = 0.9, life = bloomAt, col = WHITE, a = 1,
		ease = E.outBack, fin = 0.2, fout = 0.1, order = 105,
		upd = function(p)
			p.alpha = 0.75 + 0.25 * math.sin(p.age * 9)
		end })

	-- 霜氣與雪花升騰
	VFX:Every(0.04, bloomAt - 0.3, function()
		local a = R(0, math.pi * 2)
		local r = R(0, 1.3)
		local snow = math.random() < 0.35
		VFX:Spawn({ tex = snow and "snow" or "glow", x = tx + math.cos(a) * r, y = ty + math.sin(a) * r * 0.6, z = z,
			vx = R(-0.15, 0.15), vy = R(0.6, 1.2), life = R(0.8, 1.3), s0 = snow and R(0.15, 0.25) or R(0.2, 0.35),
			s1 = 0.05, rot = R(0, 60), vrot = snow and R(-90, 90) or 0, col = snow and WHITE or ICE, a = 0.8,
			fin = 0.2, fout = 0.5, order = 140 })
	end, 0.3)

	-- 寒霧繚繞
	VFX:Every(0.06, bloomAt - 0.2, function(el)
		local a = R(0, math.pi * 2)
		local r = R(1.0, 1.8)
		VFX:Emit("mist", { x = tx + math.cos(a) * r, y = ty + math.sin(a) * r * 0.6, z = z,
			vx = -math.sin(a) * 0.8, vy = math.cos(a) * 0.5 + 0.2, size = R(1.0, 1.8), life = R(1.2, 1.8),
			col = { 0.5, 0.78, 1, 0.55 } })
	end, 0.2)

	-- 綻放終結
	VFX:After(bloomAt, function()
		flash(tx, ty, z, 3.0, ICE, 0.5)
		ring(tx, ty, z, 0.4, 3.4, WHITE, 0.55, 0.8)
		for _ = 1, 14 do
			local a = R(0, math.pi * 2)
			local v = R(2.5, 4.5)
			VFX:Spawn({ tex = "snow", x = tx, y = ty, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v, drag = 3,
				life = R(0.6, 0.9), s0 = R(0.25, 0.4), s1 = 0.08, rot = R(0, 60), vrot = R(-200, 200), col = WHITE,
				fin = 0.05, fout = 0.6, order = 150 })
		end
		for _ = 1, 26 do
			local a = R(0, math.pi * 2)
			local v = R(2, 4.5)
			VFX:Emit("mist", { x = tx, y = ty, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
				size = R(1.2, 2.0), life = R(0.9, 1.4), col = { 0.7, 0.88, 1, 0.6 } })
		end
		if onBloom then
			onBloom()
		end
	end)
end

---------------------------------------------------------------------------
-- 紫霄雷印：雷印法陣成形、雷氣內聚，三道天雷劈落，衝擊波擴散
---------------------------------------------------------------------------
function VFX:Fx_Thunder(getT, onStrike)
	if not self:Init() then
		return
	end
	local tx, ty, tz = getT()
	local z = self:FxZ(tz)
	local strikes = { 0.9, 1.08, 1.3 }
	local fadeAt = 1.55

	local outer = VFX:Spawn({ tex = "rune_outer", x = tx, y = ty, z = z, s0 = 0, s1 = 2.8, vrot = 40, life = 2.1,
		col = VIOLET, a = 0.9, ease = E.outBack, fin = 0.15, fout = 0.25, order = 90 })
	local inner = VFX:Spawn({ tex = "rune_inner", x = tx, y = ty, z = z, s0 = 0, s1 = 1.8, vrot = -75, life = 2.1,
		col = LILAC, a = 0.85, ease = E.outBack, fin = 0.2, fout = 0.25, order = 91 })
	for _, p in ipairs({ outer, inner }) do
		if p then
			local grow = p.s1
			p.upd = function(q, t)
				q.x, q.y = getT()
				-- 定型後縮回到原尺寸，雷落後再撐大淡出
				local age = q.age
				local k = math.min(1, age / 0.5)
				q.s0 = grow * E.outBack(k)
				if age > fadeAt then
					q.s0 = grow * (1 + (age - fadeAt) * 0.8)
				end
				q.s1 = q.s0
			end
		end
	end

	-- 雷氣內聚
	VFX:Every(0.025, 0.8, function()
		local a = R(0, math.pi * 2)
		local r = R(2.0, 2.6)
		local sx, sy = tx + math.cos(a) * r, ty + math.sin(a) * r
		VFX:Spawn({ tex = "spark", x = sx, y = sy, z = z, life = 0.35, s0 = 0.3, s1 = 0.08, rot = deg(a), col = LILAC,
			fin = 0.2, fout = 0.3, order = 140,
			upd = function(p, t)
				local k = E.inQuad(t)
				p.x = sx + (tx - sx) * k
				p.y = sy + (ty - sy) * k
			end })
	end)
	VFX:Spawn({ tex = "glow", x = tx, y = ty, z = z, s0 = 0.3, s1 = 1.6, life = 0.95, col = VIOLET, a = 0.8,
		ease = E.inQuad, fin = 0.3, fout = 0.1, order = 95 })

	for si, at in ipairs(strikes) do
		VFX:After(at, function()
			local hx, hy = getT()
			hx, hy = hx + R(-0.15, 0.15), hy + R(-0.15, 0.15)
			local topx, topy = hx + R(-0.8, 0.8), hy + 8
			local function main()
				return VFX:Bolt(topx, topy, hx, hy, 6, 1.1)
			end
			VFX:Line({ gen = main, z = z, width = 0.55, col = VIOLET, a = 0.55, life = 0.32, refresh = 0.045, order = 150 })
			VFX:Line({ gen = main, z = z, width = 0.13, col = WHITE, a = 1, life = 0.3, refresh = 0.045, order = 151 })
			for _ = 1, 2 do
				VFX:Line({ z = z, width = 0.08, col = LILAC, a = 0.8, life = 0.16, refresh = 0.05, order = 149,
					gen = function()
						local f = R(0.3, 0.8)
						local bx, by = topx + (hx - topx) * f, topy + (hy - topy) * f
						return VFX:Bolt(bx, by, bx + R(-1.6, 1.6), by - R(0.8, 2.0), 4, 0.5)
					end })
			end
			local big = (si == #strikes)
			flash(hx, hy, z, big and 4.5 or 2.8, VIOLET, 0.3)
			VFX:Spawn({ tex = "core", x = hx, y = hy, z = z, s0 = 1.4, s1 = 0.4, life = 0.25, col = WHITE, a = 1,
				fin = 0, fout = 0.9, order = 165 })
			ring(hx, hy, z, 0.3, big and 4.2 or 2.4, big and LILAC or VIOLET, big and 0.55 or 0.35)
			burst(hx, hy, z, big and 18 or 8, LILAC, big and 9 or 6, 0.35, 0.5)
			for _ = 1, big and 34 or 14 do
				local a = R(0, math.pi * 2)
				local v = R(10, 19)
				VFX:Emit("spark", { x = hx, y = hy, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
					size = R(0.07, 0.13), life = R(0.15, 0.3), col = { 0.88, 0.78, 1, 1 } })
			end
			for _ = 1, big and 12 or 4 do
				VFX:Emit("smoke", { x = hx + R(-0.6, 0.6), y = hy + R(-0.3, 0.3), z = z, vx = R(-0.4, 0.4),
					vy = R(0.5, 1.2), size = R(1.2, 2.2), life = R(1.6, 2.6), col = { 0.24, 0.2, 0.3, 0.7 } })
			end
			if big then
				for _ = 1, 18 do
					local a = R(0, math.pi * 2)
					local v = R(3, 9)
					VFX:Emit("ember", { x = hx, y = hy, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v + 1.5,
						size = R(0.08, 0.16), life = R(0.8, 1.4), col = { 0.82, 0.62, 1, 1 } })
				end
			end
			if onStrike then
				onStrike(si, #strikes)
			end
		end)
	end

	-- 餘燼上飄
	VFX:Every(0.05, 0.7, function()
		VFX:Spawn({ tex = "core", x = tx + R(-1.2, 1.2), y = ty + R(-0.6, 0.6), z = z, vx = R(-0.2, 0.2), vy = R(0.5, 1.1),
			life = R(0.6, 1.0), s0 = R(0.1, 0.2), s1 = 0.02, col = VIOLET, a = 0.8, fin = 0.1, fout = 0.6, order = 145 })
	end, 1.35)
end

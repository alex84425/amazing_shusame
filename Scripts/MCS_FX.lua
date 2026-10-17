-- 覓長生·離火傳承：視覺效果
-- 借用《九霄流光訣》的特效引擎（JXLG_VFX）；沒啟用那個 Mod 時就只有機制、沒有畫面。

local MCS = GameMain:GetMod("MCS_LiHuo")
local R = function(a, b) return a + math.random() * (b - a) end

local ORANGE = { 1, 0.5, 0.15 }
local GOLD = { 1, 0.8, 0.35 }
local RED = { 1, 0.25, 0.08 }

local function V()
	local v = GameMain:GetMod("JXLG_VFX")
	if v == nil or v.Emit == nil or v.Spawn == nil then return nil end
	return v
end

local function pos(t)
	local p = t.Pos
	return p.x, p.y, p.z
end

local function burst(v, x, y, z, n, speed, size)
	for _ = 1, n do
		local a = R(0, math.pi * 2)
		local s = R(speed * 0.4, speed)
		v:Emit("fire", { x = x, y = y, z = z, vx = math.cos(a) * s, vy = math.sin(a) * s, size = R(size * 0.6, size),
			life = R(0.3, 0.6) })
	end
end

-- 火球飛彈：亮核 + 火焰拖尾，命中時爆開
local function bolt(v, from, to, scale)
	local x0, y0, z = pos(from)
	local x1, y1 = pos(to)
	local zf = v:FxZ(z)
	local dur = 0.35
	local core = v:Spawn({ tex = "core", x = x0, y = y0, z = zf, s0 = 0.7 * scale, life = dur, col = GOLD, a = 1,
		fin = 0.05, fout = 0.05, order = 240 })
	local halo = v:Spawn({ tex = "glow", x = x0, y = y0, z = zf, s0 = 1.6 * scale, life = dur, col = ORANGE, a = 0.8,
		fin = 0.05, fout = 0.05, order = 175 })
	v:Every(0.016, dur, function(el)
		local u = math.min(1, el / dur)
		local x = x0 + (x1 - x0) * u
		local y = y0 + (y1 - y0) * u + math.sin(u * math.pi) * 0.8
		if core then core.x, core.y = x, y end
		if halo then halo.x, halo.y = x, y end
		v:Emit("fire", { x = x + R(-0.08, 0.08), y = y + R(-0.08, 0.08), z = zf, vx = R(-0.4, 0.4), vy = R(-0.2, 0.6),
			size = R(0.5, 0.8) * scale, life = R(0.2, 0.35) })
	end)
	v:After(dur, function()
		local tx, ty = pos(to)
		v:Spawn({ tex = "glow", x = tx, y = ty, z = zf, s0 = 1.2 * scale, s1 = 2.8 * scale, life = 0.35, col = ORANGE, a = 0.9,
			fin = 0.02, fout = 0.8, order = 176 })
		burst(v, tx, ty, zf, math.floor(14 * scale), 4 * scale, 0.8 * scale)
		for _ = 1, math.floor(8 * scale) do
			local a = R(0, math.pi * 2)
			local s = R(6, 11)
			v:Emit("spark", { x = tx, y = ty, z = zf, vx = math.cos(a) * s, vy = math.sin(a) * s, size = R(0.08, 0.14),
				life = R(0.2, 0.35), col = { 1, 0.85, 0.5, 1 } })
		end
	end)
end

-- 自身：腳下火環 + 螺旋上升的火
local function selfBuff(v, npc)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	v:Spawn({ tex = "ring", x = x, y = y, z = zf, s0 = 0.3, s1 = 2.2, life = 0.5, col = ORANGE, a = 0.8, fin = 0.02,
		fout = 0.8, order = 120 })
	v:Every(0.02, 0.5, function(el)
		for k = 0, 1 do
			local a = el * 14 + k * math.pi
			local r = 0.7 * (1 - el / 0.5) + 0.15
			v:Emit("fire", { x = x + math.cos(a) * r, y = y + el * 2 + math.sin(a) * r * 0.35, z = zf, vy = R(0.3, 0.8),
				size = R(0.35, 0.55), life = R(0.3, 0.45) })
		end
	end)
end

-- 敵方身上：赤色法陣 + 由地面竄起的火舌
local function curse(v, npc, big)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	local s = big and 1.5 or 1
	v:Spawn({ tex = "rune_outer", x = x, y = y, z = zf, s0 = 0.4, s1 = 2.4 * s, vrot = 50, life = 1.0, col = RED, a = 0.85,
		ease = v.E.outBack, fin = 0.1, fout = 0.4, order = 100 })
	v:Every(0.03, 0.7, function()
		local a = R(0, math.pi * 2)
		local r = R(0, 1.1 * s)
		v:Emit("fire", { x = x + math.cos(a) * r, y = y + math.sin(a) * r * 0.6, z = zf, vy = R(1.0, 2.0) * s,
			size = R(0.5, 0.9) * s, life = R(0.4, 0.7) })
	end)
end

-- 九天劫火、麟火：天降火柱
local function pillar(v, npc)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	v:Spawn({ tex = "glow", x = x, y = y, z = zf, s0 = 2, s1 = 6, life = 0.6, col = ORANGE, a = 1, fin = 0.02, fout = 0.8,
		order = 172 })
	v:Spawn({ tex = "ring", x = x, y = y, z = zf, s0 = 0.4, s1 = 5, life = 0.6, col = GOLD, a = 0.9, fin = 0.02,
		fout = 0.8, order = 176 })
	v:Every(0.016, 0.6, function(el)
		for _ = 1, 4 do
			v:Emit("fire", { x = x + R(-0.6, 0.6), y = y + 7 * (1 - el / 0.6) + R(0, 1.5), z = zf, vy = R(-9, -6),
				size = R(0.9, 1.5), life = R(0.3, 0.5) })
		end
	end)
	burst(v, x, y, zf, 60, 7, 1.4)
	v:Every(0.05, 1.2, function()
		v:Emit("smoke", { x = x + R(-1, 1), y = y + R(-0.5, 0.5), z = zf, vy = R(0.6, 1.2), size = R(1.8, 3),
			life = R(2, 3), col = { 0.18, 0.15, 0.14, 0.9 } })
	end, 0.3)
end

-- 灼燒：目標身上冒出幾縷火苗（層數越多越旺）
local function burn(v, npc, n)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	for _ = 1, math.min(30, 3 + n * 2) do
		v:Emit("fire", { x = x + R(-0.5, 0.5), y = y + R(-0.3, 0.3), z = zf, vy = R(0.8, 1.6), size = R(0.5, 0.9),
			life = R(0.4, 0.7) })
	end
end


---------------------------------------------------------------------------
-- 竹山宗（木系）
---------------------------------------------------------------------------
local LEAF = { 0.55, 1.0, 0.35 }
local JADE = { 0.75, 1.0, 0.75 }
local TOXIC = { 0.55, 0.85, 0.25 }

-- 木系飛彈：綠色光核 + 一路飄落的葉片
local function wbolt(v, from, to, scale)
	local x0, y0, z = pos(from)
	local x1, y1 = pos(to)
	local zf = v:FxZ(z)
	local dur = 0.35
	local core = v:Spawn({ tex = "core", x = x0, y = y0, z = zf, s0 = 0.6 * scale, life = dur, col = JADE, a = 1,
		fin = 0.05, fout = 0.05, order = 240 })
	local halo = v:Spawn({ tex = "glow", x = x0, y = y0, z = zf, s0 = 2.0 * scale, life = dur, col = LEAF, a = 0.9,
		fin = 0.05, fout = 0.05, order = 175 })
	v:Every(0.02, dur, function(el)
		local u = math.min(1, el / dur)
		local x = x0 + (x1 - x0) * u
		local y = y0 + (y1 - y0) * u + math.sin(u * math.pi) * 0.6
		if core then core.x, core.y = x, y end
		if halo then halo.x, halo.y = x, y end
		v:Spawn({ tex = "petal", x = x + R(-0.1, 0.1), y = y + R(-0.1, 0.1), z = zf, vx = R(-0.6, 0.6), vy = R(-1.0, -0.3),
			s0 = R(0.25, 0.4) * scale, sx = 0.6, rot = R(0, 360), vrot = R(-240, 240), life = R(0.4, 0.6),
			col = LEAF, a = 1, fin = 0.05, fout = 0.6, order = 230 })
	end)
	v:After(dur, function()
		local tx, ty = pos(to)
		v:Spawn({ tex = "ring", x = tx, y = ty, z = zf, s0 = 0.3, s1 = 2.2 * scale, life = 0.35, col = LEAF, a = 0.8,
			fin = 0.02, fout = 0.8, order = 176 })
		for _ = 1, math.floor(10 * scale) do
			local a = R(0, math.pi * 2)
			local sp = R(2, 4.5)
			v:Spawn({ tex = "petal", x = tx, y = ty, z = zf, vx = math.cos(a) * sp, vy = math.sin(a) * sp, drag = 3,
				s0 = R(0.3, 0.45) * scale, sx = 0.6, rot = R(0, 360), vrot = R(-300, 300), life = R(0.5, 0.8),
				col = LEAF, a = 0.9, fin = 0.02, fout = 0.6, order = 231 })
		end
	end)
end

-- 敵方腳下：綠色法陣 + 由地面竄起的藤葉
local function wcurse(v, npc, big)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	local sc = big and 2.0 or 1.5
	v:Spawn({ tex = "glow", x = x, y = y, z = zf, s0 = 1.5 * sc, s1 = 2.5 * sc, life = 1.0, col = LEAF, a = 0.5,
		fin = 0.1, fout = 0.5, order = 95 })
	v:Spawn({ tex = "rune_inner", x = x, y = y, z = zf, s0 = 0.3, s1 = 2.0 * sc, vrot = -45, life = 1.0, col = LEAF,
		a = 0.85, ease = v.E.outBack, fin = 0.1, fout = 0.4, order = 100 })
	v:Every(0.04, 0.6, function()
		local a = R(0, math.pi * 2)
		local r = R(0.2, 1.0 * sc)
		v:Spawn({ tex = "petal", x = x + math.cos(a) * r, y = y + math.sin(a) * r * 0.6, z = zf, vy = R(1.0, 2.0),
			s0 = R(0.3, 0.5) * sc, sx = 0.55, rot = R(-30, 30), life = R(0.4, 0.7), col = LEAF, a = 0.85,
			fin = 0.1, fout = 0.5, order = 200 })
	end)
end

-- 自身：翠綠光環與上升光點
local function wself(v, npc)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	v:Spawn({ tex = "ring", x = x, y = y, z = zf, s0 = 0.3, s1 = 2.0, life = 0.5, col = JADE, a = 0.8, fin = 0.02,
		fout = 0.8, order = 120 })
	v:Every(0.03, 0.5, function()
		local a = R(0, math.pi * 2)
		v:Spawn({ tex = "core", x = x + math.cos(a) * 0.6, y = y + math.sin(a) * 0.3, z = zf, vy = R(0.8, 1.5),
			s0 = R(0.12, 0.2), s1 = 0.03, life = R(0.5, 0.8), col = JADE, a = 0.9, fin = 0.2, fout = 0.5, order = 210 })
	end)
end

-- 中毒：目標身上冒出毒霧
local function poison(v, npc, n)
	local x, y, z = pos(npc)
	local zf = v:FxZ(z)
	v:Spawn({ tex = "glow", x = x, y = y, z = zf, s0 = 1.6, s1 = 2.6, life = 0.8, col = TOXIC, a = 0.7,
		fin = 0.1, fout = 0.6, order = 96 })
	for _ = 1, math.min(18, 5 + n) do
		v:Emit("mist", { x = x + R(-0.6, 0.6), y = y + R(-0.3, 0.4), z = zf, vx = R(-0.3, 0.3), vy = R(0.4, 1.0),
			size = R(1.0, 1.7), life = R(0.9, 1.4), col = { 0.6, 1.0, 0.2, 0.8 } })
	end
end

-- 吸血：綠色光點從敵人飛回施法者
local function lifesteal(v, from, to)
	local x0, y0, z = pos(from)
	local zf = v:FxZ(z)
	for i = 1, 8 do
		local ox, oy = R(-0.3, 0.3), R(-0.2, 0.4)
		v:After(i * 0.04, function()
			local x1, y1 = pos(to)
			v:Spawn({ tex = "core", x = x0 + ox, y = y0 + oy, z = zf, s0 = 0.38, s1 = 0.18, life = 0.5, col = JADE, a = 1,
				fin = 0.1, fout = 0.3, order = 245,
				upd = function(p, t)
					local k = t * t
					p.x = x0 + ox + (x1 - x0 - ox) * k
					p.y = y0 + oy + (y1 - y0 - oy) * k + math.sin(t * math.pi) * 0.6
				end })
		end)
	end
end

function MCS:FX(kind, from, to, arg)
	local v = V()
	if v == nil or not v:Init() then return end
	if kind == "bolt" then
		bolt(v, from, to, 1.5)
	elseif kind == "big" then
		if arg == "BaoRan" then bolt(v, from, to, 2.4) else pillar(v, to) end
	elseif kind == "self" then
		selfBuff(v, from)
	elseif kind == "curse" then
		curse(v, to, arg == "FanHuo")
	elseif kind == "burn" then
		burn(v, to, arg or 1)
	elseif kind == "wbolt" then
		wbolt(v, from, to, 1.6)
	elseif kind == "wbig" then
		wbolt(v, from, to, 2.4)
		wcurse(v, to, true)
	elseif kind == "wcurse" then
		wcurse(v, to, arg == "QingShe")
	elseif kind == "wself" then
		wself(v, from)
	elseif kind == "poison" then
		poison(v, to, arg or 1)
	elseif kind == "lifesteal" then
		lifesteal(v, from, to)
	end
end

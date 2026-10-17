-- 九霄流光訣：朱雀焚天
-- 一隻由火焰粒子組成的朱雀：起勢火旋 → 振翅飛行（拖著火尾）→ 撞擊爆炸 → 火環、濃煙、火星、餘火

local VFX = GameMain:GetMod("JXLG_VFX")
local R = function(a, b) return VFX:Rand(a, b) end
local atan2 = math.atan2 or math.atan

local FLAME = { 1, 0.85, 0.55, 1 }
local PART_COL = {
	head = { 1, 1, 0.82, 1 },
	body = { 1, 0.72, 0.38, 1 },
	edge = { 1, 0.78, 0.4, 1 },
	wing = { 1, 0.5, 0.2, 0.9 },
	tail = { 1, 0.35, 0.12, 0.9 },
}
local GOLD = { 1.0, 0.8, 0.35 }
local ORANGE = { 1.0, 0.45, 0.12 }
local SCORCH = { 0.7, 0.18, 0.05 }

-- 朱雀的骨架（局部座標：+x 為前方），每個點 {x, y, 尺寸, 部位}
-- 翅膀與尾羽在每一幀依拍翅相位重新計算
local function birdPoints(time)
	local pts = {}
	for i = 0, 5 do
		pts[#pts + 1] = { 0.6 - i * 0.22, 0, 0.75 - i * 0.05, "body" }
	end
	pts[#pts + 1] = { 0.85, 0.0, 0.6, "head" }
	pts[#pts + 1] = { 1.05, 0.0, 0.35, "head" }
	pts[#pts + 1] = { 0.78, 0.18, 0.35, "head" }      -- 頭冠
	local flap = math.sin(time * 11)
	local span = 0.45 + 0.55 * (0.5 + 0.5 * flap)      -- 俯視時拍翅 = 翼展伸縮
	for _, s in ipairs({ -1, 1 }) do
		-- 五根飛羽從肩部呈扇形向後展開，填滿翼面
		for f = 0, 4 do
			local back = math.rad(8 + f * 13 + (1 - flap) * 6)
			local len = 2.9 - f * 0.32
			for j = 1, 10 do
				local d = j / 10 * len
				local curl = 0.18 * (j / 10) ^ 2         -- 羽尖微微上翹
				local x = 0.15 - math.sin(back) * d - curl
				local y = s * (0.15 + math.cos(back) * d * span)
				pts[#pts + 1] = { x, y, (0.5 - j * 0.025) * (1 - f * 0.08), f == 0 and "edge" or "wing" }
			end
		end
	end
	for k = 1, 3 do
		local spread = (k - 2) * 0.09
		for m = 1, 13 do
			local wave = math.sin(time * 9 - m * 0.45 + k) * 0.035 * m
			pts[#pts + 1] = { -0.75 - m * 0.19, spread * m * 0.7 + wave, 0.42 - m * 0.022, "tail" }
		end
	end
	return pts
end

function VFX:Fx_Phoenix(getC, getT, onHit)
	if not self:Init() then
		return
	end
	local cx, cy, cz = getC()
	local z = self:FxZ(cz)
	local riseT, flyT = 0.75, 1.35
	local impactT = riseT + flyT

	-- 起勢：雙股火焰螺旋升起
	self:Every(0.016, riseT, function(el)
		local k = el / riseT
		for strand = 0, 1 do
			local a = el * 14 + strand * math.pi
			local r = 0.9 * (1 - k) + 0.2
			self:Emit("fire", { x = cx + math.cos(a) * r, y = cy + k * 2.2 + math.sin(a) * r * 0.35, z = z,
				vx = R(-0.2, 0.2), vy = R(0.4, 0.9), size = R(0.5, 0.8), life = R(0.35, 0.55) })
		end
		if math.random() < 0.5 then
			local a = R(0, math.pi * 2)
			self:Emit("fire", { x = cx + math.cos(a) * 0.9, y = cy + math.sin(a) * 0.4, z = z,
				vy = R(0.5, 1.0), size = R(0.3, 0.5), life = R(0.3, 0.5) })
		end
	end)
	self:Spawn({ tex = "glow", x = cx, y = cy, z = z, s0 = 1, s1 = 2.6, life = riseT + 0.2, col = ORANGE, a = 0.7,
		fin = 0.3, fout = 0.4, order = 170 })

	-- 飛行：二次貝茲曲線，往上拱起後俯衝
	local sx, sy = cx, cy + 2.2
	local halo, core
	self:After(riseT, function()
		halo = self:Spawn({ tex = "glow", x = sx, y = sy, z = z, s0 = 3.0, life = flyT, col = ORANGE, a = 0.6,
			fin = 0.1, fout = 0.05, order = 175 })
		core = self:Spawn({ tex = "core", x = sx, y = sy, z = z, s0 = 1.3, life = flyT, col = GOLD, a = 0.9,
			fin = 0.1, fout = 0.05, order = 240 })
		-- 啼鳴：一圈金環
		self:Spawn({ tex = "ring", x = sx, y = sy, z = z, s0 = 0.4, s1 = 3.5, life = 0.5, col = GOLD, a = 0.8,
			ease = VFX.E.outQuad, fin = 0.02, fout = 0.8, order = 176 })
	end)
	self:Every(0.016, flyT, function(el)
		local tx, ty = getT()
		local u = VFX.E.inOut(math.min(1, el / flyT))
		local mx, my = (sx + tx) / 2, math.max(sy, ty) + 3.5
		local a1, b1 = 1 - u, u
		local bx = a1 * a1 * sx + 2 * a1 * b1 * mx + b1 * b1 * tx
		local by = a1 * a1 * sy + 2 * a1 * b1 * my + b1 * b1 * ty
		-- 切線方向 = 朝向
		local dx = 2 * a1 * (mx - sx) + 2 * b1 * (tx - mx)
		local dy = 2 * a1 * (my - sy) + 2 * b1 * (ty - my)
		local ang = atan2(dy, dx)
		local ca, sa = math.cos(ang), math.sin(ang)
		local scale = 2.4 * self.S
		local speed = math.sqrt(dx * dx + dy * dy) / flyT
		for _, p in ipairs(birdPoints(self.clock)) do
			if p[4] ~= "wing" or math.random() < 0.6 then
			local lx, ly = p[1] * scale, p[2] * scale
			local wx, wy = bx + lx * ca - ly * sa, by + lx * sa + ly * ca
			local back = p[4] == "tail" and 0.8 or 0.35
			self:Emit("fire", { x = wx + R(-0.05, 0.05), y = wy + R(-0.05, 0.05), z = z,
				vx = -ca * speed * back * 0.25 + R(-0.3, 0.3), vy = -sa * speed * back * 0.25 + R(-0.3, 0.3),
				size = p[3] * R(1.2, 1.6), life = p[4] == "tail" and R(0.25, 0.4) or R(0.15, 0.25),
				col = PART_COL[p[4]] })
			end
		end
		-- 柔光骨架：讓輪廓在遠景也看得出是一隻鳥
		for _, p in ipairs(birdPoints(self.clock)) do
			local lx, ly = p[1] * scale, p[2] * scale
			self:Emit("glow", { x = bx + lx * ca - ly * sa, y = by + lx * sa + ly * ca, z = z,
				size = p[3] * 2.2, life = 0.1, col = { 1, 0.45, 0.1, 0.55 } })
		end
		-- 翼尖灑落羽火
		if math.random() < 0.6 then
			local s = math.random() < 0.5 and -1 or 1
			local lx, ly = -0.5 * scale, s * 2.6 * scale
			self:Emit("ember", { x = bx + lx * ca - ly * sa, y = by + lx * sa + ly * ca, z = z,
				vx = -ca * 2 + R(-1, 1), vy = -sa * 2 + R(-1, 1), size = R(0.12, 0.2), life = R(0.6, 1.0),
				col = { 1, 0.6, 0.2, 1 } })
		end
		if halo then
			halo.x, halo.y = bx, by
		end
		if core then
			core.x, core.y = bx, by
		end
	end, riseT)

	-- 撞擊
	self:After(impactT, function()
		local tx, ty = getT()
		self:Spawn({ tex = "glow", x = tx, y = ty, z = z, s0 = 3, s1 = 7, life = 0.5, col = ORANGE, a = 1,
			ease = VFX.E.outQuad, fin = 0.02, fout = 0.85, order = 172 })
		self:Spawn({ tex = "core", x = tx, y = ty, z = z, s0 = 2.6, s1 = 0.6, life = 0.35, col = { 1, 1, 0.9 }, a = 1,
			fin = 0, fout = 0.9, order = 245 })
		self:Spawn({ tex = "ring", x = tx, y = ty, z = z, s0 = 0.5, s1 = 6.0, life = 0.6, col = GOLD, a = 0.9,
			ease = VFX.E.outQuad, fin = 0.02, fout = 0.8, order = 176 })
		self:Spawn({ tex = "ring", x = tx, y = ty, z = z, s0 = 0.3, s1 = 3.6, life = 0.45, col = ORANGE, a = 0.8,
			ease = VFX.E.outQuad, fin = 0.02, fout = 0.8, order = 177 })
		-- 火球
		for _ = 1, 80 do
			local a = R(0, math.pi * 2)
			local v = R(1.5, 7)
			self:Emit("fire", { x = tx, y = ty, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
				size = R(0.8, 1.7), life = R(0.55, 1.1) })
		end
		-- 火環：沿圓周向外推
		for i = 1, 40 do
			local a = i / 40 * math.pi * 2
			self:Emit("fire", { x = tx + math.cos(a) * 0.6, y = ty + math.sin(a) * 0.6, z = z,
				vx = math.cos(a) * 7, vy = math.sin(a) * 7, size = R(0.5, 0.8), life = R(0.4, 0.6) })
		end
		-- 帶拖尾的火星
		for _ = 1, 55 do
			local a = R(0, math.pi * 2)
			local v = R(4, 11)
			self:Emit("ember", { x = tx, y = ty, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v + 2,
				size = R(0.1, 0.22), life = R(1.0, 1.9), col = { 1, R(0.45, 0.75), 0.15, 1 } })
		end
		-- 高速亮紋
		for _ = 1, 40 do
			local a = R(0, math.pi * 2)
			local v = R(9, 16)
			self:Emit("spark", { x = tx, y = ty, z = z, vx = math.cos(a) * v, vy = math.sin(a) * v,
				size = R(0.12, 0.2), life = R(0.25, 0.45), col = { 1, 0.9, 0.6, 1 } })
		end
		-- 焦痕
		self:Spawn({ tex = "glow", x = tx, y = ty, z = z, s0 = 3.5, s1 = 4.5, life = 3.2, col = SCORCH, a = 0.55,
			fin = 0.05, fout = 0.7, order = 160 })
		if onHit then
			onHit()
		end
	end)

	-- 濃煙升騰
	self:Every(0.035, 1.5, function()
		local tx, ty = getT()
		local a = R(0, math.pi * 2)
		local r = R(0, 1.4)
		self:Emit("smoke", { x = tx + math.cos(a) * r, y = ty + math.sin(a) * r * 0.6, z = z,
			vx = R(-0.3, 0.3), vy = R(0.6, 1.4), size = R(2.2, 3.6), life = R(2.2, 3.2),
			col = { 0.16, 0.13, 0.12, 1 } })
	end, impactT + 0.12)

	-- 地面餘火
	self:Every(0.05, 1.9, function(el)
		local tx, ty = getT()
		local a = R(0, math.pi * 2)
		local r = R(0.3, 1.9)
		local fade = 1 - el / 1.9
		self:Emit("fire", { x = tx + math.cos(a) * r, y = ty + math.sin(a) * r * 0.6, z = z,
			vx = R(-0.1, 0.1), vy = R(0.5, 1.0), size = R(0.4, 0.85) * (0.4 + 0.6 * fade), life = R(0.4, 0.75) })
	end, impactT + 0.2)
end

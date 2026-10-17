-- 九霄流光訣：開發橋接（只有 Mod 資料夾裡存在 Dev/ 目錄時才啟用）
-- 每 0.3 秒檢查 Dev/cmd.lua；有就執行後刪除，結果寫進日誌。
-- 讓外部可以不重開遊戲就熱重載腳本、播放特效、截圖。

local Dev = GameMain:GetMod("JXLG_Dev")
local VFX = GameMain:GetMod("JXLG_VFX")
local U = CS.UnityEngine
local File = CS.System.IO.File
local Directory = CS.System.IO.Directory

Dev.acc = 0

function Dev:DevDir()
	return VFX:ModDir() .. "Dev/"
end

function Dev:OnRender(dt)
	self.acc = self.acc + U.Time.unscaledDeltaTime
	if self.acc < 0.3 then
		return
	end
	self.acc = 0
	local dir = self:DevDir()
	if not Directory.Exists(dir) then
		return
	end
	local path = dir .. "cmd.lua"
	if not File.Exists(path) then
		return
	end
	local code = File.ReadAllText(path)
	File.Delete(path)
	local f, err = load(code, "=jxlg_cmd")
	if f == nil then
		VFX.log("cmd compile error: " .. tostring(err))
		return
	end
	local ok, res = pcall(f)
	VFX.log("cmd " .. (ok and "ok" or "ERROR") .. ": " .. tostring(res))
end

-- 重新載入本 Mod 的所有腳本（不含 Dev 本身，避免重設計時器）
function Dev:Reload()
	VFX:Clear()
	local dir = VFX:ModDir() .. "Scripts/"
	local files = Directory.GetFiles(dir, "*.lua")
	local done = {}
	for i = 0, files.Length - 1 do
		local p = files[i]
		if not string.find(p, "JXLG_Dev") then
			local f, err = load(File.ReadAllText(p), "=" .. p)
			if f == nil then
				error("reload compile " .. p .. ": " .. tostring(err))
			end
			f()
			done[#done + 1] = string.match(p, "[^/\\]+$")
		end
	end
	VFX:ResetSystems()
	VFX.ready = false
	VFX.failed = false
	VFX:Init()
	return "reloaded " .. table.concat(done, ",")
end

-- 依序在指定秒數截圖：Shots("sword", {0.3, 0.8, 1.2})
function Dev:Shots(prefix, times)
	local dir = self:DevDir() .. "shots/"
	if not Directory.Exists(dir) then
		Directory.CreateDirectory(dir)
	end
	for i, t in ipairs(times) do
		VFX:After(t, function()
			U.ScreenCapture.CaptureScreenshot(dir .. string.format("%s_%02d.png", prefix, i))
		end)
	end
	VFX:After(times[#times] + 0.5, function()
		VFX.log("shots done " .. prefix)
	end)
end

-- 目前畫面中央的世界座標
function Dev:Center()
	local cam = VFX:FindCamera()
	local p = cam.transform.position
	return p.x, p.y, 0
end

-- 把選中的角色（或畫面中央）當目標；施法者放在左下方
function Dev:Targets(dx, dy)
	local sel = WorldLua:GetSelectThing()
	local x, y, z
	if sel ~= nil and sel.Pos ~= nil then
		local p = sel.Pos
		x, y, z = p.x, p.y, p.z
	else
		x, y, z = self:Center()
	end
	dx, dy = dx or -3, dy or -1.5
	return function() return x + dx, y + dy, z end, function() return x, y, z end
end

function Dev:Info()
	local cam = VFX:FindCamera()
	local sel = WorldLua:GetSelectThing()
	return string.format("cam=(%.1f,%.1f,%.1f) ortho=%s size=%.2f screen=%dx%d sel=%s",
		cam.transform.position.x, cam.transform.position.y, cam.transform.position.z,
		tostring(cam.orthographic), cam.orthographicSize, U.Screen.width, U.Screen.height,
		sel ~= nil and tostring(sel:GetName()) or "none")
end

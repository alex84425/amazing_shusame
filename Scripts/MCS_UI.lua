-- 覓長生·離火傳承：出招設定視窗
-- 選中修習離火傳承的弟子後按 LeftShift+4 開啟。
-- 用官方 SimpleWindow 框架以程式碼排版（不需要 FairyGUI 介面包）。

local MCS = GameMain:GetMod("MCS_LiHuo")
local SimpleWindow = GameMain:GetMod("SimpleWindow")

local WIN_NAME = "MCS_OrderWindow"
local ROW_Y0, ROW_H = 150, 27
local MAX_ROWS = 19
local EN = { Jin = "金", Mu = "木", Shui = "水", Huo = "火", Tu = "土" }

local function costText(cost)
	local parts = {}
	for _, e in ipairs({ "Jin", "Mu", "Shui", "Huo", "Tu" }) do
		if cost[e] then parts[#parts + 1] = EN[e] .. "×" .. cost[e] end
	end
	if cost.any then parts[#parts + 1] = "同×" .. cost.any end
	return table.concat(parts, " ")
end

local win = SimpleWindow:GetWindow(WIN_NAME) or SimpleWindow:CreateWindow(WIN_NAME)
MCS.OrderWindow = win

-- 由遊戲在第一次 Show() 時呼叫
function win:OnInit()
	self:SetTitle("覓長生·出招設定")
	self:SetSize(560, ROW_Y0 + MAX_ROWS * ROW_H + 70)
	self.modeLabel = self:AddLable("mode", "", 24, 76, 260, 28)
	self.btnAI = self:AddButton("ai", "交給 AI", 290, 72)
	self.btnManual = self:AddButton("manual", "照我的順序", 410, 72)
	pcall(function() self.btnAI:SetSize(110, 30) end)
	pcall(function() self.btnManual:SetSize(130, 30) end)
	self.hint = self:AddLable("hint", "", 24, 112, 520, 28)
	self.rows = {}
	for i = 1, MAX_ROWS do
		local y = ROW_Y0 + (i - 1) * ROW_H
		local row = {
			label = self:AddLable("row" .. i, "", 24, y, 300, ROW_H),
			up = self:AddButton("up" .. i, "↑", 330, y - 2),
			dn = self:AddButton("dn" .. i, "↓", 390, y - 2),
			tg = self:AddButton("tg" .. i, "", 450, y - 2),
		}
		for _, b in ipairs({ row.up, row.dn }) do pcall(function() b:SetSize(52, 25) end) end
		pcall(function() row.tg:SetSize(80, 25) end)
		self.rows[i] = row
	end
	local yb = ROW_Y0 + MAX_ROWS * ROW_H + 18
	self:AddButton("reset", "恢復預設", 140, yb)
	self:AddButton("close", "關閉", 330, yb)
end

function win:Open(npc)
	self.npcId = npc.ID
	self.npcName = npc:GetName()
	self.order = MCS:GetOrder(npc.ID)
	self:Show()
	pcall(function() self:Center() end)
	self:Refresh()
end

-- 只顯示已學會的技能，順序照 order.list
function win:VisibleIds()
	local npc = ThingMgr:FindThingByID(self.npcId)
	local learned = {}
	if npc ~= nil then
		for _, id in ipairs(MCS:Learned(npc)) do learned[id] = true end
	end
	local ids = {}
	for _, id in ipairs(self.order.list) do
		if learned[id] then ids[#ids + 1] = id end
	end
	return ids
end

function win:Refresh()
	if self.rows == nil or self.order == nil then return end
	pcall(function() self:SetTitle("覓長生·出招設定 — " .. (self.npcName or "")) end)
	local manual = self.order.manual
	self.modeLabel.title = "模式：" .. (manual and "[color=#C0501E]照我的順序[/color]" or "[color=#3C78B4]交給 AI[/color]")
	self.hint.title = manual and "每回合從上往下，施放第一個付得起且已啟用的招式，放完再從頭找。"
		or "AI 依當下靈氣與局勢評分出招；切到「照我的順序」才會套用下方排序。"
	self.ids = self:VisibleIds()
	for i, row in ipairs(self.rows) do
		local id = self.ids[i]
		local show = id ~= nil
		for _, o in pairs(row) do o.visible = show end
		if show then
			local d = MCS.SKILLS[id]
			local off = self.order.off[id]
			local name = string.format("%d. %s", i, d.name)
			local text = string.format("%-12s %s%s", name, costText(d.cost), d.hou and "（後繼無力）" or "")
			row.label.title = off and ("[color=#999999]" .. text .. "[/color]") or text
			row.tg.title = off and "已停用" or "啟用中"
		end
	end
end

-- 把可見清單中的第 i 個和第 j 個互換（同步回完整清單）
function win:Swap(i, j)
	local ids = self.ids
	if ids[i] == nil or ids[j] == nil then return end
	local a, b = ids[i], ids[j]
	local list = self.order.list
	local ia, ib
	for k, id in ipairs(list) do
		if id == a then ia = k end
		if id == b then ib = k end
	end
	list[ia], list[ib] = list[ib], list[ia]
end

function win:OnObjectEvent(t, obj, context)
	if t ~= "onClick" or self.order == nil then return end
	local name = obj.name
	if name == "close" then
		self:Hide()
		return
	elseif name == "ai" then
		self.order.manual = false
	elseif name == "manual" then
		self.order.manual = true
	elseif name == "reset" then
		self.order.list = MCS:DefaultOrder()
		self.order.off = {}
	else
		local kind, idx = string.match(name, "^(%a+)(%d+)$")
		idx = tonumber(idx)
		if kind == "up" and idx > 1 then
			self:Swap(idx, idx - 1)
		elseif kind == "dn" then
			self:Swap(idx, idx + 1)
		elseif kind == "tg" and self.ids[idx] then
			local id = self.ids[idx]
			self.order.off[id] = (not self.order.off[id]) or nil
		end
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- 存檔：每位弟子的出招設定跟著存檔走
---------------------------------------------------------------------------
function MCS:OnSave()
	local data = {}
	for id, o in pairs(self.orders) do
		local off = {}
		for k, v in pairs(o.off) do if v then off[#off + 1] = k end end
		data[#data + 1] = { id = id, manual = o.manual, list = o.list, off = off }
	end
	return { orders = data }
end

function MCS:OnLoad(tbData)
	self.orders = {}
	if tbData == nil or tbData.orders == nil then return end
	for _, o in ipairs(tbData.orders) do
		local off = {}
		for _, k in ipairs(o.off or {}) do off[k] = true end
		self.orders[o.id] = { manual = o.manual, list = o.list or self:DefaultOrder(), off = off }
	end
end

-- 開啟視窗（LeftShift+4），由 MCS_Host.lua 的 OnHotKey 轉呼叫
function MCS:OpenOrderWindow()
	local sel = WorldLua:GetSelectThing()
	if sel == nil or sel.ThingType ~= g_emThingType.Npc then
		print("[MCS] 請先選中一名弟子")
		return
	end
	local any = false
	for _, sc in pairs(MCS.SCHOOLS or {}) do
		if sel.PropertyMgr:HasModifier(sc.rootMod) then any = true end
	end
	if not any then
		pcall(function() sel.LuaHelper:AddMsg(XT("[NAME]尚未修習離火傳承，無法設定出招。")) end)
		return
	end
	win:Open(sel)
end

-- 覓長生·竹山宗：神通與功法資料（木系：中毒、纏繞、吸血）
-- 數值依覓長生 Wiki 的 煉氣/築基/金丹 三欄（索引 1/2/3）。
-- 連擊條件：竹山宗的木系技能多半是「上一招為水系」才觸發。

local MCS = GameMain:GetMod("MCS_LiHuo")
local SCHOOL = "ZhuShan"

local SKILLS = {
	---------------------------------------------------------------- 煉氣
	MuCi = { name = "木刺", tier = "人階中", elems = { "Mu" }, cost = { Mu = 2 }, fx = "wbolt",
		dmg = { 2, 3, 6 }, combo = { elem = "Shui", dmg = { 1, 2, 4 } },
		desc = "基礎木系技能，造成傷害。【連擊】上一招為水系時傷害提升。" },
	FuDu = { name = "腐毒咒", tier = "人階中", elems = { "Mu" }, cost = { Mu = 1, any = 1 }, fx = "wcurse",
		dmg = { 1, 2, 3 }, poison = { 1, 1, 1 }, desc = "造成傷害，敵方獲得【中毒】。" },
	JiSheng = { name = "寄生引血術", tier = "人階中", elems = { "Mu" }, cost = { Mu = 1, any = 1 }, fx = "wbolt",
		dmg = { 2, 3, 4 }, lifestealIfEntangled = true, desc = "造成傷害，若目標被【纏繞】，此擊【吸血】。" },
	HuaWu = { name = "花舞術", tier = "人階中", elems = { "Mu" }, cost = { Mu = 2, any = 1 }, fx = "wbolt",
		dmg = { 2, 3, 6 }, combo = { elem = "Shui", randomDebuff = 2 },
		desc = "造成傷害。【連擊】上一招為水系時，敵方獲得 2 個隨機負面狀態。" },
	HuiChunYin = { name = "回春印", tier = "人階中", elems = { "Mu", "Shui" }, cost = { Shui = 1, Mu = 1 }, fx = "wself",
		boostMu = 1, desc = "本場戰鬥提升吸收到木系靈氣的機率。" },
	QuTeng = { name = "驅藤術", tier = "人階下", elems = { "Mu", "Shui" }, cost = { Mu = 1, Shui = 1 }, fx = "wself",
		hou = true, mark = { chanrao = { 2, 3, 4 } },
		desc = "【後繼無力】本回合下一次受到傷害時，對手獲得【纏繞】。" },

	---------------------------------------------------------------- 築基
	ShuLao = { name = "樹牢術", tier = "人階上", elems = { "Mu" }, cost = { Mu = 3, any = 1 }, fx = "wbolt",
		dmg = { 9, 10, 14 }, combo = { elem = "Shui", chanrao = { 1, 2, 3 } },
		desc = "造成傷害。【連擊】上一招為水系時，敵方獲得【纏繞】。" },
	YinDu = { name = "引毒咒", tier = "人階上", elems = { "Mu" }, cost = { Mu = 1, any = 1 }, fx = "wcurse",
		triggerPoison = true, costRamp = "Mu",
		desc = "觸發一次敵方的【中毒】；同一回合每多用一次，額外消耗一點木系靈氣。" },
	ChunSi = { name = "春絲印", tier = "人階上", elems = { "Mu", "Shui" }, cost = { Mu = 2, Shui = 1 }, fx = "wself",
		hou = true, nextWood = { 5, 7, 11 }, desc = "【後繼無力】下一次木系技能傷害提升。" },
	ZhuShanJian = { name = "竹山劍法", tier = "地階下", elems = { "Mu" }, cost = { Mu = 2, any = 2 }, fx = "wbolt",
		dmg = { 2, 4, 6 }, lifesteal = true, combo = { elem = "Shui", dmg = { 1, 2, 3 } },
		desc = "【吸血】造成傷害；【連擊】上一招為水系時傷害提升。" },

	---------------------------------------------------------------- 金丹
	ChanMu = { name = "纏木", tier = "地階上", elems = { "Mu" }, cost = { Mu = 2, any = 2 }, fx = "wcurse",
		chanrao = { 3, 5, 7 }, desc = "敵方獲得【纏繞】。" },
	QingShe = { name = "青蛇勁", tier = "地階上", elems = { "Mu" }, cost = { Mu = 4 }, fx = "wcurse",
		poison = { 3, 5, 7 }, desc = "敵方獲得大量【中毒】。" },
	LuanTeng = { name = "亂藤術", tier = "地階上", elems = { "Mu" }, cost = { Mu = 3, any = 2 }, fx = "wbig",
		dmg = { 5, 7, 10 }, lifesteal = true, perEntangle = 1,
		desc = "【吸血】造成傷害；敵方每有一層【纏繞】，傷害提升 1 點。" },
	ZhangDu = { name = "障毒訣", tier = "地階中", elems = { "Mu" }, cost = { Mu = 2, any = 3 }, fx = "wbolt",
		dmg = { 6, 8, 12 }, vsPoisonDouble = true, same = { 3, 4, 6 },
		desc = "造成傷害，對【中毒】的目標傷害翻倍；【同】額外提升傷害。" },
	WuDuZhen = { name = "五毒攝魂陣·驅", tier = "地階中", elems = { "Mu" }, cost = { Mu = 1, any = 1 }, fx = "wcurse",
		hou = true, poison = { 2, 3, 4 }, desc = "【後繼無力】敵方獲得【中毒】。" },
	JiXueTeng = { name = "汲血藤", tier = "地階中", elems = { "Mu" }, cost = { Mu = 3, any = 3 }, fx = "wbig",
		dmg = { 9, 12, 18 }, lifesteal = true, same = { 4, 6, 8 },
		desc = "【吸血】造成傷害；【同】額外提升傷害。" },
}

-- 被動功法：煉氣=第一層、築基=第三層、金丹=第五層
local PASSIVES = {
	ChunCao = { name = "春草訣", tier = "人階中", root = true,
		desc = "竹山宗入門心法。戰鬥勝利後恢復生命。", winHeal = { 8, 30, 120 } },
	ZhenYu = { name = "鴆羽訣", tier = "人階中", desc = "戰鬥開始時，敵方獲得【中毒】。", startPoison = { 2, 5, 12 } },
	ShangQing = { name = "上青訣", tier = "人階中", desc = "使用木系傷害技能時，若上一招為水系，傷害提升。",
		comboDmg = { 1, 4, 16 } },
	ShengMu = { name = "生木訣", tier = "人階中", desc = "每回合第一次造成的木系技能傷害提升。", firstDmg = { 2, 6, 24 } },
	QingTeng = { name = "青藤訣", tier = "人階中", desc = "戰鬥開始時，敵方獲得【纏繞】。", startChanRao = { 2, 4, 12 } },
	WanMu = { name = "萬木訣", tier = "地階下", desc = "戰鬥開始時，木靈根權重提升。", muWeight = { 0.25, 0.5, 1.0 } },
	TaiYin = { name = "太陰玄毒功", tier = "地階下", desc = "對【中毒】的敵人，木系技能傷害提升。", vsPoison = { 2, 5, 10 } },
	HuiChunJue = { name = "回春訣", tier = "地階中", desc = "每消耗 5 點木系靈氣，恢復生命。", healPer5Mu = { 5, 15, 30 } },
	WuDuShiXin = { name = "五毒蝕心訣", tier = "地階中", desc = "回合結束時，敵方獲得【中毒】。", turnPoison = { 2, 7, 23 } },
	QingSheYao = { name = "青蛇要訣", tier = "地階上", desc = "每次使用【青蛇勁】，敵方額外獲得【中毒】。", qingSheExtra = { 2, 4, 8 } },
	WanXiang = { name = "萬象纏身訣", tier = "地階上", desc = "單次木系傷害足夠高時，敵方獲得【纏繞】。",
		bigHit = { 3, 7, 18 }, bigHitChanRao = { 1, 3, 6 } },
}

local TREE = {
	Qi = { "MuCi", "FuDu", "JiSheng", "HuaWu", "HuiChunYin", "QuTeng", "ZhenYu", "ShangQing", "ShengMu" },
	Dan1 = { "ShuLao", "YinDu", "ChunSi", "ZhuShanJian", "QingTeng", "WanMu", "TaiYin", "HuiChunJue" },
	Dan2 = { "ChanMu", "QingShe", "LuanTeng", "ZhangDu", "WuDuZhen", "JiXueTeng", "WuDuShiXin", "QingSheYao", "WanXiang" },
}

local META = { name = "竹山宗", gong = "Gong_MCS_ChunCao", root = "ChunCao", rootMod = "MCS_ZhuShan_Root", main = "Mu" }

MCS.SKILLS = MCS.SKILLS or {}
MCS.PASSIVES = MCS.PASSIVES or {}
MCS.TREES = MCS.TREES or {}
MCS.SCHOOLS = MCS.SCHOOLS or {}
for k, v in pairs(SKILLS) do v.school = SCHOOL; MCS.SKILLS[k] = v end
for k, v in pairs(PASSIVES) do v.school = SCHOOL; MCS.PASSIVES[k] = v end
MCS.TREES[SCHOOL] = TREE
MCS.SCHOOLS[SCHOOL] = META

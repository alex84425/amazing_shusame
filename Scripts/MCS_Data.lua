-- 覓長生·離火傳承：神通與功法資料
-- 數值依覓長生 Wiki 的 煉氣/築基/金丹 三欄（索引 1/2/3）。
-- 傷害單位是覓長生的「點」，實際傷害 = 點數 × MCS.K[施法者境界]。
-- 標記 est = true 的數值為推估（Wiki 只列出金丹欄或缺漏）。

local MCS = GameMain:GetMod("MCS_LiHuo")
local SCHOOL = "LiHuo"

-- cost：指定五行的消耗；any = 「同」（任意五行，優先用本系支付以觸發【同】）
-- hou：後繼無力（施放後本回合不再出手）
-- elems：技能屬性，用來判斷下一招的【連擊】
-- fx：視覺效果種類 bolt(飛彈) / self(自身) / curse(敵方身上) / big(大招)
local SKILLS = {
	---------------------------------------------------------------- 煉氣
	Huodan = { name = "火彈", tier = "人階中", elems = { "Huo" }, cost = { Huo = 3 }, fx = "bolt",
		dmg = { 4, 6, 10 }, combo = { elem = "Mu", dmg = { 2, 3, 5 } },
		desc = "基礎火系技能，造成傷害。【連擊】上一招為木系時傷害提升。" },
	RanHuo = { name = "燃火術", tier = "人階中", elems = { "Huo" }, cost = { Huo = 2, any = 1 }, fx = "bolt",
		dmg = { 3, 3, 3 }, combo = { elem = "Mu", selfYan = { 1, 2, 3 } },
		desc = "造成傷害。【連擊】上一招為木系時獲得【焰】。" },
	ZhiHuoYin = { name = "炙火印", tier = "人階下", elems = { "Huo", "Mu" }, cost = { Huo = 1, Mu = 1 }, fx = "self",
		hou = true, mark = { burn = { 2, 3, 4 } },
		desc = "【後繼無力】本回合下一次受到傷害時，使對手獲得【灼燒】。" },
	JuHuoYin = { name = "聚火印", tier = "人階中", elems = { "Mu", "Huo" }, cost = { Mu = 1, Huo = 1 }, fx = "self",
		juhuo = 1, desc = "本場戰鬥提升吸收到火系靈氣的機率。" },
	HuoQiang = { name = "火牆術", tier = "人階中", elems = { "Huo" }, cost = { Huo = 2, any = 1 }, fx = "self",
		shield = { 3, 4, 7 }, combo = { elem = "Mu", shieldMul = 2 },
		desc = "獲得【護罩】。【連擊】上一招為木系時效果翻倍。" },
	HuaYanShu = { name = "化焰術", tier = "人階上", elems = { "Huo" }, cost = { Huo = 1, any = 1 }, fx = "self",
		selfHuaYan = { 1, 2, 3 }, desc = "獲得【化焰】，使用任何非火系技能都會脫離此狀態。" },

	---------------------------------------------------------------- 築基
	TuYan = { name = "吐焰訣", tier = "人階上", elems = { "Huo" }, cost = { Huo = 3, any = 1 }, fx = "bolt",
		dmg = { 7, 8, 9 }, combo = { elem = "Mu", burn = { 1, 2, 3 } },
		desc = "造成傷害。【連擊】上一招為木系時敵方獲得【灼燒】。" },
	FenQi = { name = "焚氣術", tier = "人階上", elems = { "Huo" }, cost = { Huo = 1, any = 1 }, fx = "bolt",
		dmg = { 1, 2, 3 }, burnedDissipate = 1, desc = "造成傷害，若敵方被【灼燒】，消散其一點靈氣。" },
	DanYang = { name = "丹陽印", tier = "人階上", elems = { "Huo", "Mu" }, cost = { Huo = 1, Mu = 2 }, fx = "self",
		hou = true, selfYan = { 2, 3, 4 }, desc = "【後繼無力】獲得【焰】。" },
	TunYan = { name = "吞焰訣", tier = "人階上", elems = { "Huo" }, cost = { Huo = 1, any = 1 }, fx = "self",
		removeSelfBurn = 3, heal = { 1, 2, 3 }, nextFire = { 2, 3, 4 },
		desc = "移除自身【灼燒】×3，恢復生命，並使下一次火系技能傷害提升。" },
	SanMei = { name = "三昧真火", tier = "地階下", elems = { "Huo" }, cost = { Huo = 2, any = 2 }, fx = "bolt",
		dmg = { 5, 6, 7 }, burn = { 1, 2, 3 }, same = { 2, 3, 4 },
		desc = "造成傷害並使敵方獲得【灼燒】；【同】額外提升傷害。" },
	HuoShe = { name = "火蛇術", tier = "地階下", elems = { "Huo" }, cost = { Huo = 3, any = 2 }, fx = "bolt",
		dmg = { 9, 11, 15 }, burnedEntangle = { 1, 2, 3 }, same = { 3, 4, 5 },
		desc = "造成傷害，若目標被【灼燒】則獲得【纏繞】；【同】額外提升傷害。" },

	---------------------------------------------------------------- 金丹
	BaoRan = { name = "爆燃", tier = "地階中", elems = { "Huo" }, cost = { Huo = 3, any = 1 }, fx = "big", est = true,
		dmg = { 12, 18, 28 }, triggerYan = 1, combo = { elem = "Mu", triggerYan = 1 },
		desc = "造成傷害，額外觸發一次【焰】；【連擊】上一招為木系時再觸發一次。" },
	FenLing = { name = "焚靈訣", tier = "地階中", elems = { "Huo" }, cost = { Huo = 2, any = 1 }, fx = "curse", est = true,
		dissipate = 2, burnedDissipate = 2, desc = "隨機散去敵方 2 點靈氣；若敵方有【灼燒】，再散去 2 點。" },
	ChiYanZhen = { name = "赤炎靈陣·驅", tier = "地階中", elems = { "Huo" }, cost = { Huo = 1, any = 2 }, fx = "curse",
		hou = true, burn = { 2, 3, 4 }, desc = "【後繼無力】敵方獲得【灼燒】。" },
	LinHuo = { name = "麟火", tier = "天階上", elems = { "Huo" }, cost = { Huo = 4, any = 2 }, fx = "big", yihuo = true,
		burn = { 7, 11, 15 }, selfBurn = { 3, 5, 7 }, desc = "【異火】敵方獲得大量【灼燒】，自身也獲得【灼燒】。" },
	JiuTian = { name = "九天劫火", tier = "天階上", elems = { "Huo" }, cost = { Huo = 9 }, fx = "big", yihuo = true,
		dmg = { 85, 116, 184 }, selfBurn = { 10, 12, 16 }, desc = "【異火】造成巨額傷害，自身獲得【灼燒】。" },
	FanHuo = { name = "返火移景術", tier = "天階下", elems = { "Huo" }, cost = { Huo = 2, any = 2 }, fx = "curse",
		mirrorBurn = true, desc = "自身每有一層【灼燒】，敵方便獲得一層【灼燒】。" },
	DaTunYan = { name = "大吞焰術", tier = "天階中", elems = { "Huo" }, cost = { Huo = 1, any = 1 }, fx = "self",
		eatYan = { 2, 3, 4 }, desc = "消耗自身所有【焰】，每層恢復生命。" },
}

-- 被動功法：layer 依境界 煉氣=第一層、築基=第三層、金丹=第五層（索引 1/2/3）
local PASSIVES = {
	LieYan = { name = "烈焰訣", tier = "人階上", root = true,
		desc = "離火門入門心法。戰鬥開始時獲得火系靈氣。", startHuo = { 1, 2, 3 } },
	YinHuo = { name = "引火訣", tier = "人階中", desc = "使用火系傷害技能時，若上一招為木系，傷害提升。",
		comboDmg = { 1, 4, 16 } },
	NongYan = { name = "弄焰訣", tier = "人階中", desc = "每回合第一次造成的火系技能傷害提升。", firstDmg = { 2, 6, 24 } },
	HuaYanJue = { name = "化焰訣", tier = "人階中", desc = "回合結束時，若處於【化焰】，額外獲得【化焰】。",
		huayanGain = { 1, 2, 4 } },
	DieYan = { name = "疊焰訣", tier = "地階下", desc = "使用火系技能時，若上一招為木系，獲得【焰】。", comboYan = { 3, 5, 7 } },
	RongDun = { name = "熔盾訣", tier = "地階下", desc = "回合結束時，若處於【化焰】，獲得【護罩】。", huayanShield = { 5, 20, 80 } },
	FenXin = { name = "焚心訣", tier = "地階中", desc = "回合開始時，敵方獲得【灼燒】。", turnBurn = { 2, 7, 22 } },
	RanYan = { name = "燃焰訣", tier = "地階上", desc = "單次火系傷害足夠高時，敵方獲得【灼燒】。",
		bigHit = { 10, 30, 60 }, bigHitBurn = { 2, 4, 9 } },
	ZhenYang = { name = "真陽功", tier = "地階下", desc = "戰鬥開始時，火靈根權重提升。", huoWeight = { 0.25, 0.5, 1.0 } },
	FenTian = { name = "焚天功", tier = "天階中", desc = "自身每有一層【灼燒】，火系技能傷害提升。", perSelfBurn = { 1, 2, 3 } },
	XuanYang = { name = "玄陽哺焰訣", tier = "天階中", desc = "脫離【化焰】時，對手獲得等同化焰層數倍數的【灼燒】。",
		leaveHuaYanMul = { 1, 2, 3 } },
}

-- 技能樹排列（XML 產生器與引擎共用同一份順序）
local TREE = {
	Qi = { "Huodan", "RanHuo", "ZhiHuoYin", "JuHuoYin", "HuoQiang", "HuaYanShu", "YinHuo", "NongYan" },
	Dan1 = { "TuYan", "FenQi", "DanYang", "TunYan", "SanMei", "HuoShe", "HuaYanJue", "DieYan", "RongDun" },
	Dan2 = { "BaoRan", "FenLing", "ChiYanZhen", "FenXin", "RanYan", "ZhenYang", "LinHuo", "JiuTian", "FanHuo",
		"DaTunYan", "FenTian", "XuanYang" },
}

-- 門派資訊：功法、根節點（被動）、根節點 modifier、主屬性（【同】優先用它付）
local META = { name = "離火門", gong = "Gong_MCS_LieYan", root = "LieYan", rootMod = "MCS_LiHuo_Root", main = "Huo" }

-- 合併進共用表（每個門派一個資料檔，載入順序不固定，所以都用合併的方式）
MCS.SKILLS = MCS.SKILLS or {}
MCS.PASSIVES = MCS.PASSIVES or {}
MCS.TREES = MCS.TREES or {}
MCS.SCHOOLS = MCS.SCHOOLS or {}
for k, v in pairs(SKILLS) do v.school = SCHOOL; MCS.SKILLS[k] = v end
for k, v in pairs(PASSIVES) do v.school = SCHOOL; MCS.PASSIVES[k] = v end
MCS.TREES[SCHOOL] = TREE
MCS.SCHOOLS[SCHOOL] = META

function MCS:EsoName(id)
	return "MCS_Eso_" .. id
end

"""Generates every XML definition of 覓長生傳承 from the per-school Lua data files.

Each school lives in its own Scripts/MCS_Data*.lua (SKILLS / PASSIVES / TREE /
META).  Names, descriptions, costs and per-realm numbers live only there; this
script reads them so the in-game tooltips never drift from the mechanics.
Run:  python gen_xml.py
"""
import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GAME = os.path.abspath(os.path.join(ROOT, "..", ".."))
SCHOOL_FILES = [("LiHuo", "MCS_Data.lua"), ("ZhuShan", "MCS_Data_ZhuShan.lua")]

EN = {"Jin": "金", "Mu": "木", "Shui": "水", "Huo": "火", "Tu": "土", "any": "同"}

# 每個門派的功法外觀（境界與瓶頸統一沿用原版太和十六洞天）
GONG_TEXT = {
    "LiHuo": {
        "display": "烈焰訣",
        "desc": "離火門入門心法。修習者於戰鬥中依五行根基吸收五行靈氣，以火系神通疊加灼燒，焚盡來敵。境界劃分與太和十六洞天相同。",
        "select": "此功法擅長火系灼燒，戰鬥時以五行靈氣施展離火神通。是否要選擇修習此功法？",
        "five": "-1, -1, -1, 4, -1", "elem": "Huo",
        "exp": ("離火門弟子", "你出身寧州離火門，自幼修習《烈焰訣》，對火系靈氣格外親近。"),
    },
    "ZhuShan": {
        "display": "春草訣",
        "desc": "竹山宗入門心法。修習者於戰鬥中依五行根基吸收五行靈氣，以木系神通疊毒纏身、吸血續命。境界劃分與太和十六洞天相同。",
        "select": "此功法擅長木系中毒與纏繞，戰鬥時以五行靈氣施展竹山神通。是否要選擇修習此功法？",
        "five": "-1, 4, -1, -1, -1", "elem": "Mu",
        "exp": ("竹山宗弟子", "你自幼在寧州竹山宗長大，熟讀《春草訣》，與草木靈氣心意相通。"),
    },
}


def block(data, name):
    start = data.index("local %s = {" % name)
    depth, i = 0, data.index("{", start)
    for j in range(i, len(data)):
        depth += {"{": 1, "}": -1}.get(data[j], 0)
        if depth == 0:
            return data[i + 1:j]


def entries(data, name):
    body = block(data, name)
    out = {}
    for m in re.finditer(r"^\t(\w+) = \{(.*?)\n(?=\t\w+ = \{|\t-|$)", body + "\n", re.S | re.M):
        out[m.group(1)] = m.group(2)
    return out


def field(text, key):
    m = re.search(r'\b%s = "([^"]*)"' % key, text)
    return m.group(1) if m else None


def triple(text, key):
    m = re.search(r"\b%s = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}" % key, text)
    return m.groups() if m else None


def cost(text):
    m = re.search(r"cost = \{([^}]*)\}", text)
    if not m:
        return ""
    parts = re.findall(r"(\w+) = (\d+)", m.group(1))
    return " ".join("%s×%s" % (EN[k], v) for k, v in parts)


NUM_LABEL = [("dmg", "傷害"), ("burn", "敵方灼燒"), ("selfBurn", "自身灼燒"), ("selfYan", "焰"),
             ("selfHuaYan", "化焰"), ("shield", "護罩"), ("heal", "恢復"), ("nextFire", "下次火傷+"),
             ("same", "【同】傷害+"), ("burnedEntangle", "纏繞"), ("eatYan", "每層焰恢復"),
             ("startHuo", "開戰火系靈氣"), ("comboDmg", "連擊傷害+"), ("firstDmg", "首次傷害+"),
             ("huayanGain", "化焰"), ("comboYan", "焰"), ("huayanShield", "護罩"), ("turnBurn", "敵方灼燒"),
             ("bigHitBurn", "敵方灼燒"), ("perSelfBurn", "每層灼燒火傷+"), ("leaveHuaYanMul", "灼燒倍數"),
             ("huoWeight", "火靈根權重+"),
             ("poison", "敵方中毒"), ("chanrao", "敵方纏繞"), ("nextWood", "下次木傷+"), ("winHeal", "戰後恢復"),
             ("startPoison", "開戰敵方中毒"), ("startChanRao", "開戰敵方纏繞"), ("muWeight", "木靈根權重+"),
             ("vsPoison", "對中毒傷害+"), ("healPer5Mu", "每5木恢復"), ("turnPoison", "敵方中毒"),
             ("qingSheExtra", "額外中毒"), ("bigHitChanRao", "敵方纏繞")]


def numbers(text):
    lines = []
    for key, label in NUM_LABEL:
        t = triple(text, key)
        if t:
            lines.append("%s %s" % (label, "／".join(t)))
    if not lines:
        return ""
    return "\\n[color=#A0A0A0]煉氣／築基／金丹：[/color]\\n" + "\\n".join(lines)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def write(rel, txt):
    p = os.path.join(ROOT, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8").write(txt)


src = open(os.path.join(GAME, "Settings", "Practice", "Gong", "Gong_1.xml"), encoding="utf-8-sig").read()
g1 = src[src.index('<Gong Name="Gong_1_Shui">'):]
STAGES = g1[g1.index("<Stages>"):g1.index("</Stages>") + len("</Stages>")]

all_esos, root_mods, experiences, summary = [], [], [], []

for school, fname in SCHOOL_FILES:
    data = open(os.path.join(ROOT, "Scripts", fname), encoding="utf-8").read()
    SK, PS = entries(data, "SKILLS"), entries(data, "PASSIVES")
    tree_body = block(data, "TREE")
    TREE = {lv: re.findall(r'"(\w+)"', re.search(r"\b%s = \{([^}]*)\}" % lv, tree_body).group(1))
            for lv in ("Qi", "Dan1", "Dan2")}
    meta_text = re.search(r"local META = \{(.*?)\}", data).group(1)
    META = dict(re.findall(r'(\w+) = "([^"]*)"', meta_text))
    G = GONG_TEXT[school]
    gong, root = META["gong"], META["root"]

    # 功法
    write("Settings/Practice/Gong/%s.xml" % gong, """<Gongs><List>
	<Gong Name="%s">
		<DisplayName>%s</DisplayName>
		<Desc>%s</Desc>
		<SelectDesc>%s</SelectDesc>
		<FiveBaseNeed>%s</FiveBaseNeed>
		<SkillSetName></SkillSetName>
		<ElementKind>%s</ElementKind>
		<Skill>
			<li>jiangdao</li>
			<li>ciqi</li>
			<li>guanding</li>
		</Skill>
		<Hide>2</Hide>
		%s
	</Gong>
</List></Gongs>
""" % (gong, G["display"], G["desc"], G["select"], G["five"], G["elem"], STAGES))

    # 技能樹
    root_node = "%s_n_%s" % (gong, root)

    def node(id_, level, index, is_root=False):
        pre = "" if is_root else "\n\t\t\t<li>%s</li>\n\t\t" % root_node
        disp = field((PS.get(id_) or SK.get(id_)), "name")
        return """	<Node Name="%s_n_%s" Gong="%s">
		<Esoterica>MCS_Eso_%s</Esoterica>
		<DisplayName>%s</DisplayName>
		<Level>%s</Level>
		<Index>%d</Index>
		<Line>0,0,0,0,0,0,0,0</Line>
		<PreUnit>%s</PreUnit>
		<MutexUnit></MutexUnit>
		<FiveBase>0,0,0,0,0</FiveBase>
		<Skills></Skills>
		<LingMax>0</LingMax>
		<GoldLevel>0</GoldLevel>
		<GodCount>0</GodCount>
	</Node>
""" % (gong, id_, gong, id_, disp, level, index, pre)

    nodes = [node(root, "Qi", 0, True)]
    for lv, ids in TREE.items():
        for i, id_ in enumerate(ids):
            nodes.append(node(id_, lv, i + (1 if lv == "Qi" else 0)))
    write("Settings/Practice/Tree/%s.xml" % gong, "<SkillTree><List>\n" + "".join(nodes) + "</List></SkillTree>\n")

    # 秘術
    def eso(id_, text, is_skill, level):
        name, tier, desc = field(text, "name"), field(text, "tier"), field(text, "desc")
        kind = "神通" if is_skill else "功法"
        head = "[color=#D06508]%s·%s（%s·%s）[/color]" % (kind, name, META["name"], tier)
        c = cost(text) if is_skill else ""
        flags = []
        if is_skill and re.search(r"\bhou = true", text):
            flags.append("後繼無力")
        if re.search(r"\best = true", text):
            flags.append("部分數值為推估")
        body = "%s\\n%s%s%s%s" % (head, ("靈氣消耗：" + c + "\\n") if c else "", esc(desc), numbers(text),
                                  ("\\n[color=#A0A0A0]" + "、".join(flags) + "[/color]") if flags else "")
        extra = "\n\t\t<Modifier>%s</Modifier>" % META["rootMod"] if id_ == root else ""
        return """	<Esoterica Name="MCS_Eso_%s">
		<DisplayName>%s</DisplayName>
		<Hide>1</Hide>
		<Icon>res/Sprs/ui/icon_zhandoufashu</Icon>
		<StarLevel>0</StarLevel>
		<Difficulty>1</Difficulty>
		<Desc>%s</Desc>
		<GLevel>%s</GLevel>
		<Element>%s</Element>
		<EffectDesc>[size=10]%s[/size]</EffectDesc>%s
	</Esoterica>
""" % (id_, name, esc(desc), level, G["elem"], body, extra)

    all_esos.append(eso(root, PS[root], False, "Qi"))
    for lv, ids in TREE.items():
        for id_ in ids:
            is_skill = id_ in SK
            all_esos.append(eso(id_, SK[id_] if is_skill else PS[id_], is_skill, lv))

    root_mods.append((META["rootMod"], META["name"].replace("門", "").replace("宗", "") + "心法",
                      "修習%s心法，戰鬥時依五行根基吸收五行靈氣。" % META["name"]))
    exp_name, exp_desc = G["exp"]
    experiences.append("""	<Experience Name="Experience_MCS_%s">
		<DisplayName>%s</DisplayName>
		<Desc>%s\\n\\n\\n[size=10]解鎖功法：[color=#D06508]《%s》[/color][/size]</Desc>
		<Point>3</Point>
		<Gongs>
			<li>%s</li>
		</Gongs>
	</Experience>
""" % (school, exp_name, exp_desc, G["display"], gong))
    summary.append("%s: skills %d passives %d tree %s" % (school, len(SK), len(PS), {k: len(v) for k, v in TREE.items()}))

write("Settings/Esoterica/MCS_Esoterica.xml", "<Esotericas><List>\n" + "".join(all_esos) + "</List></Esotericas>\n")
write("Settings/Npc/Experience/MCS_Experience.xml", "<Experiences><List>\n" + "".join(experiences) + "</List></Experiences>\n")


# --- 狀態 --------------------------------------------------------------------
def mod(name, disp, desc, extra="", stack=999):
    return """	<Modifier Name="%s" Type="Normal">
		<DisplayName>%s</DisplayName>
		<Desc>%s</Desc>
		<MaxStack>%d</MaxStack>
		<Duration>-1</Duration>
		<Display>1</Display>%s
	</Modifier>
""" % (name, disp, desc, stack, extra)


mods = "".join(mod(n, d, desc, "\n\t\t<LuaClassName>MCS_Root</LuaClassName>", 1) for n, d, desc in root_mods)
write("Settings/Modifiers/MCS_Modifiers.xml", "<ModifierDefs><List>\n" + mods +
      mod("MCS_St_Burn", "灼燒", "回合開始時受到等同層數的火系傷害，之後移除一層。") +
      mod("MCS_St_Yan", "焰", "每層使火系技能傷害提升。") +
      mod("MCS_St_HuaYan", "化焰", "受到傷害時反震火傷；回合結束獲得灼燒×1；施展非火系技能便會脫離。") +
      mod("MCS_St_Poison", "中毒", "回合結束時受到等同層數的木系傷害，層數不會自然減少。") +
      mod("MCS_St_ChanRao", "纏繞", "行動與法寶飛行變慢；回合結束時清除。", """
		<Properties>
			<li Name="MoveSpeed" AddP="-0.3"/>
			<li Name="NpcFight_FabaoFlySpeedAddP" AddV="-0.2"/>
		</Properties>""") +
      "</List></ModifierDefs>\n")

write("Settings/Npc/Damages/MCS_Damages.xml", """<DamageDefs><List>
	<Damage Name="Damage_MCS_Fire">
		<DisplayName>離火灼傷</DisplayName>
		<Lable>Huo</Lable>
		<TreatConstant>0</TreatConstant>
		<ValueMin>0.1</ValueMin>
		<ValueMax>0.3</ValueMax>
		<Pain>0.2</Pain>
		<Trend>0.2</Trend>
		<Previous></Previous>
		<Next></Next>
	</Damage>
</List></DamageDefs>
""")

# --- Info.json ---------------------------------------------------------------
write("Info.json", json.dumps({
    "Name": "MiChangSheng_LiHuo", "DisplayName": "覓長生·離火傳承",
    "Desc": "把《覓長生》寧州門派的功法與神通搬進修仙模擬器，範圍至金丹期。目前收錄：離火門（火·灼燒）、竹山宗（木·中毒纏繞）。\n"
            "戰鬥中每 3 秒為一回合：依五行根基吸收五行靈氣，自動或照自訂順序出手（含連擊、【同】、後繼無力），"
            "並結算灼燒、中毒、焰、化焰、纏繞等狀態。\n\n"
            "取得：開局經歷「離火門弟子」「竹山宗弟子」；測試用一鍵習得：離火 LeftShift+5、竹山 LeftShift+3。\n"
            "出招設定：選中弟子按 LeftShift+4。\n"
            "視覺效果需要同時啟用《九霄流光訣（自製特效）》。\n\n機制參考自《覓長生》，僅供個人遊玩。",
    "GameVersion": 0.95, "Version": 2, "Author": "Alex"}, ensure_ascii=False, indent=1))

# --- 離火試煉木樁 ---------------------------------------------------------------
write("Settings/ThingDef/Building/MCS_MuZhuang.xml", """<ThingDefs><List>
	<ThingDef Type="Building" Name="Building_MCS_MuZhuang" Parent="ProductionBase">
		<TexPath>Spr/Building/mcs_muzhuang.png</TexPath>
		<TexScale>1</TexScale>
		<SelectAble>1</SelectAble>
		<BlockLight>0</BlockLight>
		<CastShadow>1</CastShadow>
		<ThingName>離火試煉木樁</ThingName>
		<Desc>離火門弟子練功用的木樁，經陣法加持，無論如何都打不壞。\\n讓修習覓長生傳承的弟子攻擊它，傷害統計會定期顯示在訊息欄。</Desc>
		<Beauty>0</Beauty>
		<UseHitPoints>1</UseHitPoints>
		<MaxHitPoints>99999999</MaxHitPoints>
		<Flammability>
			<Flammability>0</Flammability>
		</Flammability>
		<Collider>
			<Data>
			[3],
			</Data>
		</Collider>
		<Building>
			<NoFengshui>1</NoFengshui>
			<TerrainAffordanceNeeded>Ground</TerrainAffordanceNeeded>
			<CanMakeRoom>0</CanMakeRoom>
			<BeMade>
				<WorkToMake>1</WorkToMake>
				<Quality>0</Quality>
			</BeMade>
		</Building>
	</ThingDef>
</List></ThingDefs>
""")
write("Settings/Ui/MainList/MCS_MainList.xml", """<MainList><List>
	<Data Kind="Builds" Unlock="1" Type="工作" CMDType="Build" Name="Building_MCS_MuZhuang"/>
</List></MainList>
""")
print("\n".join(summary))

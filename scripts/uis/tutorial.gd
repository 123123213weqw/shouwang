class_name Tutorial extends Control
## 新手教程（原工程没有，新加的）。
##
## 三层：
##   1. 第一次进游戏，关卡载入以后先弹一张"玩法"卡片，把目标和最要紧的规则讲一遍，点"知道了"才开始；
##      卡片开着的时候整局暂停，不会误跳。
##   2. 之后在该用到的时候各提示一次：第一次踩到空格子、技能第一次充满、水车第一次开；难度里这一档多出来的规矩
##      （手里的灯、步数带过关、风向、夜巡）在开头各提示一次。提示是一行字，出现在关卡名下面，几秒后自己消失，不打断游戏。
##      上一条还没看完的排着队，一条看完了才弹下一条；弹着的时侯夜巡的蜡烛不烧（见 main._candle_burning）。
##   3. 暂停菜单里的"玩法"按钮随时能把卡片再调出来（这时按钮写的是"返回"）。
## 每一条只出现一次，看没看过记在存档里（Game.tutorial_seen）。
## 界面是用代码搭的，用的是游戏自己的按钮场景、手写字体和九宫格边框，和别的界面一个样子。
##
## "玩法"卡片分两栏：左栏写规则，文字按选中的难度变（Game.ruleset）；右栏是道具图鉴。
## 标题页的难度选择面板（RulesetPicker）用的是同一张卡片的画法，底、边框、字体和量边框余量的办法都是这里的。

signal closed

const BUTTON := preload("res://scenes/uis/button.tscn")
const FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const BORDER := preload("res://assets/sprites/ui/nine-patch-border.png")
const PANEL := preload("res://assets/sprites/ui/nine-patch.png")
const CARD_SIZE := Vector2(940, 580)      # 画面是 1152×720（掌机）到 1280×720，卡片放在正中
const HINT_TIME := 7.0                    # 一条提示停几秒

# 边框线里沿离卡片四边的距离，和四个角的弧，都是从边框贴图上量的。卡片多大都按这个算哪里还能放东西
const EDGE_L := 53.0                      # 里沿离左缘
const EDGE_R := 51.0                      # 离右缘
const EDGE_T := 54.0                      # 离上缘
const EDGE_B := 57.0                      # 离下缘
const CORNER := 111.0                     # 角上内弧的圆心，离上下、左右各这么远
const CORNER_R := 56.0                    # 内弧的半径（量出来是 56 到 57，取小的）

# ---- "玩法"卡片的版面（都是卡片里的坐标）----
# 左栏只要放得下规则里最长的一行（"有的沟只有靠道具才过得了，看准了再跳。"，字号 23 时 402 像素）；
# 操作那一句更长，放不下就断行。省下的宽度都给右栏：道具说明最长的一条有 276 像素
const TITLE_Y := 62.0                     # 标题。原来在 44，字顶是贴着上边框线的
const LEFT_X := 70.0                      # 左栏。离左边框线 17 像素：往下让它躲开左下角那段弧
const LEFT_W := 445.0
const LEFT_Y := 96.0                      # 左栏的第一行不在标题底下（标题在正中），可以从这儿就开始
const PARAGRAPH_GAP := 10                 # 左栏三段话之间的空，要一眼看出是三段（行距只有 3）。原先是 14，字缩了一号以后跟着收一点
const RULES_SIZE := 23                    # 左栏字号。原先是 25：难度四档以后规矩多的档要多写四五行，23 号一行还是放得下 19 个字，
                                         # 左栏从上到下也多放得下两行，底下还躲得开左下角那段弧
const RULES_SPACING := 3                  # 左栏行距（这个字体的行高只有字号的 1.04 倍，所以行距要给到）
const DIVIDER_X := 527.0                  # 两栏中间的竖线
const RIGHT_X := 549.0                    # 右栏：离竖线 20，到 880 为止（离右边框线 9 个像素）
const RIGHT_W := 331.0
const ROWS_Y := 102.0                     # 右栏第一行
const ROW_H := 36.0                       # 一行的高，行和行之间再空 ROW_GAP
const ROW_GAP := 2
const ICON := 34.0                        # 道具图标的大小
const ITEM_SIZE := 25                     # 道具说明的字号
const BUTTON_Y := 452.0                   # "知道了 / 返回"在右栏底下。字底离下边框线 24 个像素
const BUTTON_W := 220.0

const INK := Color(0.94, 0.96, 0.92)      # 正文
const MINT := Color(0.56, 0.86, 0.77)     # 边框的颜色；小标题、竖线也用它
const ITEM_COLOUR := Color(1.0, 0.84, 0.55)   # 道具贴图是纯白的剪影，染成烛火的颜色才看得清

const OPS_KEYBOARD := "操作：WASD 跳一格，或用鼠标点亮着的格子。空格放技能，Esc 呼出菜单。"
const OPS_PAD := "操作：左摇杆或十字键跳。A 放技能，Start 呼出菜单。"

## 道具图鉴：[资源, 说明]。说明用资源里的 description。只能放九行：再多一行，最后一行就压到右下角的"知道了"上。
## 蒸笼不在这儿：它只在步数带过关的档里出现，那种档下在左栏的规则里说一句（见 _rule_paragraphs）
const ITEMS := [
	["res://resources/upgrades/combooo.tres", "莲蓬：连击 +3"],
	["res://resources/upgrades/umbrella.tres", "纸伞：下一跳跳得特别远"],
	["res://resources/upgrades/shoe.tres", "草鞋：这一关每一跳都更远"],
	["res://resources/upgrades/hat.tres", "斗笠：挡一次踩空"],
	["res://resources/upgrades/cane.tres", "钓竿：收走最远的两盏灯"],
	["res://resources/upgrades/magnet.tres", "捞网：河灯都向你挪两格"],
	["res://resources/upgrades/portal.tres", "水车：卷走身边两格内的灯"],
	["res://resources/upgrades/chest.tres", "食盒：步数 +3"],
	["res://resources/upgrades/clover.tres", "铜钱：身边买来两件道具"],
]

var main: Node
var card: Control
var close_button: Button
var hint_label: Label
var _paused_by_me := false
var _hint_left := 0.0
var _pending: Array[String] = []      # 排着队还没弹的提示（上一条还没看完）
var _shown: Dictionary = {}               # 这一局里已经弹过的提示
static var fake_pad := false              # 排查用：测试机上没有手柄，想看手柄版的那段说明就把它设成 true

var _card_box: Control                    # 居中的那张卡片，下面的坐标都是它里面的
var _title: Label
var _column_head: Label                   # 右栏上面的小标题"道具"
var _rules: Array[Label] = []             # 左栏的三段话：操作、规则、收尾
var _items: VBoxContainer                 # 右栏的道具图鉴

func _ready() -> void:
	# 卡片开着的时候整局是暂停的，教程自己要能响应点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hint()
	_build_card()

func card_open() -> bool:
	return card.visible

## 正弹着提示条（夜巡的蜡烛这时不烧：人还在看提示）
func hinting() -> bool:
	return hint_label != null and hint_label.visible

## 排查用：每一层的矩形（位置、大小）和锚点
func debug_rects() -> String:
	var out := PackedStringArray()
	var node: Node = self
	while node != null and not node is CanvasLayer:
		if node is Control:
			var c: Control = node
			out.append("%s pos=%s size=%s anchors=(%s,%s,%s,%s) offsets=(%s,%s,%s,%s)" % [c.name, c.position, c.size, c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
				c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
		node = node.get_parent()
	return "\n".join(out)

## 排查用：把卡片上的东西逐个量一遍（卡片坐标），看有没有压到边框、出框、互相重叠。
## 每样报一个"余量"：离边框线还有几个像素，负数就是压上了。换过难度或输入设备以后隔一帧再量才是新的
##   call tutorial.gd debug_card_layout
func debug_card_layout() -> String:
	var items: Array = []
	_add_text(items, "标题", _title)
	_add_text(items, "道具", _column_head)
	for i in _rules.size():
		if _rules[i].visible:
			_add_text(items, ["操作", "规则", "收尾"][i], _rules[i])
	var n := 0
	for row in _items.get_children():
		n += 1
		items.append(["图标%d" % n, _rect_in_card(row.get_node("Icon")), false])
		_add_text(items, "说明%d" % n, row.get_node("Text"))
	# 关闭按钮的点按范围比字大：范围只要求不出框，看得见的那几个字才参与查重叠
	items.append(["按钮点按范围", _rect_in_card(close_button), true])
	var t := button_text_rect(close_button)
	items.append(["按钮上的字", Rect2(_to_card(t.position), t.size), false])
	return check_layout(CARD_SIZE, items)

## 排查用：左栏现在的三段话原样打出来（一段里的每一行各占一行），核对文字和标点用
##   call tutorial.gd debug_rules_text
func debug_rules_text() -> String:
	var out := PackedStringArray()
	for l in _rules:
		out.append(l.text)
	return "\n\n".join(out)

## 排查用：换一档难度，把卡片上的规则文字重填一遍（不用回标题页重开一局），拍各个档的卡片用。
## 它是真的在选难度（会写存档），拍完记得换回原来那档
##   call tutorial.gd debug_ruleset 3      换成 Game.rulesets 里的第 3 套（从 0 数）
func debug_ruleset(index: int) -> String:
	if index < 0 or index >= Game.rulesets.size():
		return "没有第 %d 档（一共 %d 档）" % [index, Game.rulesets.size()]
	Game.select_ruleset(Game.rulesets[index])
	_fill_rules()
	return "难度换成了%s，规则文字已重填" % Game.ruleset.title

func _add_text(items: Array, what: String, label: Label) -> void:
	var rect := text_rect(label)
	items.append([what, Rect2(_to_card(rect.position), rect.size), false])

func _rect_in_card(c: Control) -> Rect2:
	return Rect2(_to_card(c.global_position), c.size)

## 画面坐标 → 卡片坐标
func _to_card(p: Vector2) -> Vector2:
	return _card_box.get_global_transform().affine_inverse() * p

# ---------- 提示 ----------

## 弹一条提示。同一条只弹一次。上一条还没看完就排在这一条后面，看完了接着弹
func hint(id: String) -> void:
	if card.visible or _shown.has(id) or Game.tutorial_seen.has(id): return
	if hint_label.visible:
		if not _pending.has(id): _pending.append(id)
		return
	_shown[id] = true
	Game.tutorial_mark(id)
	hint_label.text = _hint_text(id)
	hint_label.visible = true
	hint_label.modulate.a = 0.0
	_hint_left = HINT_TIME
	create_tween().tween_property(hint_label, "modulate:a", 1.0, 0.3)

## 难度里的几条规矩，用到的那一关开头各提示一次：手里的灯、步数带过关、风向、夜巡。
## 每一帧都问一遍：这一关载入完了、没有别的提示挡着，才轮到它们（见 _process）
func rule_hints() -> void:
	if main == null or not is_instance_valid(main) or not main.level_ready: return
	var r: Ruleset = Game.ruleset
	if r == null: return
	if r.hold_lamps > 0: hint("held")
	if r.moves_carry: hint("carry")
	if r.wind: hint("wind")
	if r.night_watch: hint("night")

## 放灯的键：接了手柄是 X，没接是 E
func _place_key() -> String:
	return "X" if _has_pad() else "E"

func _hint_text(id: String) -> String:
	var r: Ruleset = Game.ruleset
	match id:
		"empty": return "踩到空格子了：扣一步，连击清零。尽量沿着有灯的格子跳。"
		"nomoves": return "步数用完了：只还能跳到有灯、有道具的格子上，再踩空格就走不动了。"
		"skill": return "技能充满了，按 %s 放技能。" % _skill_key()
		"held": return "手里有 %d 盏灯：指着够得着的空格按 %s 放一盏，花一步，是个落脚点。" % [r.hold_lamps, _place_key()]
		"carry": return "步数是从上一关带过来的，每过一关只补 %d 步。" % r.moves_bonus
		"wind": return "这一关有风（看左上角的旗子）：顺着风跳得远，逆着风跳得近。"
		"night": return "夜巡：左上角的蜡烛烧完，离你最远的一盏河灯就灭。每跳一下，蜡长回一点。"
		"portal":
			if r != null and r.portal_free:
				return "水车开了：现在踩空格也不扣步，走进去过关。"
			return "水车开了，走回水车还要花步数，看准了再走。"
	return ""

# ---------- 卡片 ----------

## 第一局开头调用：还没看过卡片就弹出来。
## 玩法整个换过一回（河灯改成开局摆好的一局），卡片也重写了：键名跟着换了一个，玩过旧版的人再弹一次新的
const RULES_SEEN := "rules2"

func maybe_show_rules() -> void:
	if not Game.tutorial_seen.has(RULES_SEEN):
		show_card(true)

func show_card(first_time: bool) -> void:
	hint_label.visible = false
	close_button.text = "知道了" if first_time else "返回"
	_fill_rules()
	# 弹卡片的时候让整局暂停（原版的暂停菜单并不真的暂停）。本来就是暂停的话，关卡片时也不去动它
	_paused_by_me = not get_tree().paused
	if _paused_by_me:
		get_tree().paused = true
	if first_time:
		Game.tutorial_mark(RULES_SEEN)
	card.visible = true
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.25)

func close() -> void:
	if not card.visible: return
	card.visible = false
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	closed.emit()

func _has_pad() -> bool:
	return fake_pad or Input.get_connected_joypads().size() > 0

func _skill_key() -> String:
	return "A" if _has_pad() else "空格"

## 每次弹出卡片都重填一遍：难度是回标题页才换的，手柄是随时可能插上的
func _fill_rules() -> void:
	var paragraphs := _rule_paragraphs()
	for i in _rules.size():
		# 规矩多的档放不下收尾那一段：整段收起来（技能那一句第一次充满的时侯另有提示）
		_rules[i].visible = i < paragraphs.size()
		if i < paragraphs.size():
			_rules[i].text = "\n".join(paragraphs[i])

## 左栏的三段话：操作、规则、收尾，每段又是一行一行的（规矩多的档放不下收尾那一段，就只有前两段）。
## 一行就是一整行（标签的自动折行是关着的），所以哪一行都得放得进左栏的宽（19 个字）。
## 左栏从上到下放得下几行是有数的：卡片左下角是一段弧，字越往下越要往右让，所以最后一样的底边不能低于 y=494。
## 键盘的操作是三行，规则最多十行（还留收尾那一段）或者十一行（不留）；手柄的操作只有两行，各多一行。
## 规则按选中的难度变：基本的打法六行每一档都一样；这一档多出来的规矩跟在后面——
## 步数带过关、手里的灯、风向、夜巡；"有的沟…"和"水车开了…"两句垫后。
## 真放不下的时侯按这个先后让：先去掉收尾那一段（技能第一次充满的时侯另有提示），
## 再把"步数带过关"压成一行（蒸笼那句并进去），最后才去掉"水车开了…"那一句（水车第一次开也有提示）
func _rule_paragraphs() -> Array:
	var r: Ruleset = Game.ruleset
	var mode: int = r.lamp_mode if r != null else Ruleset.LampMode.DEALT
	var portal_free: bool = r.portal_free if r != null else true
	var pad := _has_pad()

	var ops: PackedStringArray = _by_sentence(OPS_PAD if pad else OPS_KEYBOARD)

	# 基本的打法：每一档都一样
	var core: PackedStringArray = []
	if mode == Ruleset.LampMode.DEALT:
		core.append("河灯是摆好的一局：一盏挨一盏地收，")
		core.append("收齐了水车就开，走进去过关。")
	else:
		core.append("河灯边收边刷。收够灯，水车就开，")
		core.append("走进去过关。")
	core.append("落在灯上不扣步数，连击 +1；")
	core.append("连击越高，跳得越远。" if r == null or r.reach_add <= 0.0 else "连击越高，跳得越远（这一档格外远）。")
	if mode == Ruleset.LampMode.FLOW:
		core.append("新的灯多半刷在灯的旁边。")
	core.append("踩到空格子扣一步、连击清零。")
	core.append("头顶的数字是还能错几步。")

	# 这一档多出来的规矩。步数带过关有两种写法：两行的（说得多）和一行的（省地方）
	var extra: PackedStringArray = []
	var carry_long: PackedStringArray = []
	var carry_short: PackedStringArray = []
	if r != null and r.moves_carry:
		carry_long.append("步数是上一关带过来的，每关补 %d 步。" % r.moves_bonus)
		carry_long.append("没带满时有蒸笼，踩上去 +1 步。")
		carry_short.append("步数带过关，每关补 %d 步；没带满有蒸笼。" % r.moves_bonus)
	if r != null and r.hold_lamps > 0:
		extra.append("手里有 %d 盏灯：指着空格按 %s 放下，" % [r.hold_lamps, "X" if pad else "E"])
		extra.append("花一步，是个落脚点。")
	if r != null and r.wind:
		extra.append("有风向：顺风跳得远，逆风跳得近。")
	if r != null and r.night_watch:
		extra.append("夜巡：蜡烛烧完，最远的一盏灯就灭。")

	var ditch := "有的沟只有靠道具才过得了，看准了再跳。"
	var portal_line := "水车开了以后，踩空格不再扣步。" if portal_free else "水车开了以后，走回水车也要花步数。"
	var tail: PackedStringArray = ["收灯给技能充能，充满了按 %s 放技能。" % _skill_key()]
	var with_tail := 11 if pad else 10
	var without_tail := with_tail + 1

	# drop 是让到第几步：0 什么都留着，1 去掉收尾，2 步数带过关压成一行，3 去掉"水车开了…"那一句
	for drop in range(4):
		var body: PackedStringArray = []
		body.append_array(core)
		body.append_array(carry_short if drop >= 2 else carry_long)
		body.append_array(extra)
		if drop < 3: body.append(portal_line)
		body.append(ditch)
		if body.size() <= with_tail:
			return [ops, body, tail]
		if drop >= 1 and body.size() <= without_tail:
			return [ops, body]
	# 怎么都放不下（不该发生）：只留基本的打法、这一档的规矩和"有的沟…"，收尾不要
	var body: PackedStringArray = []
	body.append_array(core)
	body.append_array(carry_short)
	body.append_array(extra)
	body.append(ditch)
	return [ops, body]

## 一行放不下的话，在标点后面断开、分几行写（字不改）；放得下就还是一行。
## 先在句号后面断，一句自己就超过一行的宽，再在逗号后面断。
## 没接手柄时操作那一句有 800 像素宽，左栏放不下，就断成"操作：WASD 跳一格，/ 或用鼠标点亮着的格子。/ 空格放技能，Esc 呼出菜单。"
func _by_sentence(text: String) -> PackedStringArray:
	if _fits(text):
		return PackedStringArray([text])
	var lines := PackedStringArray()
	var line := ""
	for sentence in _cut_after(text, "。"):
		if _fits(line + sentence):
			line += sentence
			continue
		if _fits(sentence):                     # 这一句自己占一行
			if line != "":
				lines.append(line)
			line = sentence
			continue
		for clause in _cut_after(sentence, "，"):
			if line != "" and not _fits(line + clause):
				lines.append(line)
				line = ""
			line += clause
	if line != "":
		lines.append(line)
	return lines

func _fits(text: String) -> bool:
	return text_width(text, RULES_SIZE) <= LEFT_W

## 把一段话在 mark 后面切开（mark 留在前一段的末尾）
static func _cut_after(text: String, mark: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var start := 0
	for i in text.length():
		if text[i] == mark:
			parts.append(text.substr(start, i + 1 - start))
			start = i + 1
	if start < text.length():
		parts.append(text.substr(start))
	return parts

# ---------- 搭界面 ----------

## 搭一张卡片的底和边框，居中放到 parent 下，返回这张卡片（往上面放东西用的坐标都是卡片里的）
static func make_card(parent: Control, card_size: Vector2) -> Control:
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -card_size.x / 2
	box.offset_top = -card_size.y / 2
	box.offset_right = card_size.x / 2
	box.offset_bottom = card_size.y / 2
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)

	# 底：用现成的圆角底板贴图（和边框一样的九宫格画法），染成深色。不能用方块的色块：
	# 它的直角会从圆角的边框里露出来
	var face := NinePatchRect.new()
	face.name = "Face"
	face.texture = PANEL
	face.patch_margin_left = 90
	face.patch_margin_top = 90
	face.patch_margin_right = 90
	face.patch_margin_bottom = 90
	face.self_modulate = Color(0.03, 0.12, 0.11)
	face.size = card_size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(face)

	# 边框：九宫格。四个角的弧有七十多个像素，角块要切得比它大（115），拉伸的时候才不会把弧拉变形
	var frame := NinePatchRect.new()
	frame.name = "Frame"
	frame.texture = BORDER
	frame.patch_margin_left = 115
	frame.patch_margin_top = 115
	frame.patch_margin_right = 115
	frame.patch_margin_bottom = 115
	frame.self_modulate = MINT
	frame.size = card_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	return box

## 一个标签：手写字体，不挡鼠标
static func make_label(font_size: int, colour: Color) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = font_size
	settings.font_color = colour
	settings.line_spacing = 8
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static var _icon_cache: Dictionary = {}   # 贴图 → 裁好的图。每局都重新搭卡片，量过的不必再量

## 道具贴图是 156×136 的画布，东西画在正中，彼此大小差得很多（莲蓬只占三分之一）。
## 量出有笔画的范围裁出来，再缩放进图标框，每一行的图标才一样大
static func icon_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _icon_cache.has(tex):
		return _icon_cache[tex]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(Vector2.ZERO, tex.get_size())
	var img: Image = tex.get_image()
	if img != null:
		var used := ink_rect(img)
		if used.size.x > 0 and used.size.y > 0:
			atlas.region = Rect2(used).grow(2.0)
	_icon_cache[tex] = atlas
	return atlas

## 图上有笔画的部分。先用现成的办法量；量出来几乎占满整张画布的，多半是透明处带了压缩噪点
## （显存压缩的贴图会这样，返回箭头就是），那就缩小四倍、只认基本不透明的像素再量一遍
static func ink_rect(img: Image) -> Rect2i:
	if img.is_compressed():
		img.decompress()
	var size := img.get_size()
	var used: Rect2i = img.get_used_rect()
	if used.size.x * used.size.y < size.x * size.y * 9 / 10:
		return used
	var small: Image = img.duplicate()
	small.resize(maxi(size.x / 4, 1), maxi(size.y / 4, 1), Image.INTERPOLATE_BILINEAR)
	small.convert(Image.FORMAT_RGBA8)
	var lo := Vector2i(small.get_width(), small.get_height())
	var hi := Vector2i(-1, -1)
	for y in small.get_height():
		for x in small.get_width():
			if small.get_pixel(x, y).a < 0.2:
				continue
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return used
	return Rect2i(lo * 4, (hi - lo + Vector2i.ONE) * 4).intersection(Rect2i(Vector2i.ZERO, size))

func _build_card() -> void:
	card = Control.new()
	card.name = "TutorialCard"
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP      # 挡住落在卡片外面的点击
	add_child(card)

	# 背后压暗
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dim)

	_card_box = make_card(card, CARD_SIZE)

	_title = make_label(46, Color(1, 1, 1))
	_title.name = "Title"
	_title.text = "玩法"
	_title.position = Vector2(0, TITLE_Y)
	_title.size = Vector2(CARD_SIZE.x, 50)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_box.add_child(_title)

	# 右栏的小标题，在标题那一行上，顶和标题的字顶对齐
	_column_head = make_label(30, MINT)
	_column_head.name = "ItemsHead"
	_column_head.text = "道具"
	_column_head.position = Vector2(RIGHT_X, 66)
	_column_head.size = Vector2(RIGHT_W, 31)
	_card_box.add_child(_column_head)

	# 左栏：三段话竖着排
	var rules := VBoxContainer.new()
	rules.name = "Rules"
	rules.position = Vector2(LEFT_X, LEFT_Y)
	rules.size = Vector2(LEFT_W, 0)
	rules.add_theme_constant_override("separation", PARAGRAPH_GAP)
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(rules)
	for part in ["RulesOps", "RulesBody", "RulesTail"]:
		var l := make_label(RULES_SIZE, INK)
		l.name = part
		l.label_settings.line_spacing = RULES_SPACING
		rules.add_child(l)
		_rules.append(l)

	# 两栏中间的竖线：和左栏最长的时候（操作三行、规则十一行、中间一段空）一样高
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(MINT, 0.35)
	divider.position = Vector2(DIVIDER_X, LEFT_Y)
	divider.size = Vector2(2, 381)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(divider)

	# 右栏：道具图鉴，一行一个图标加一句话
	_items = VBoxContainer.new()
	_items.name = "Items"
	_items.position = Vector2(RIGHT_X, ROWS_Y)
	_items.size = Vector2(RIGHT_W, 0)
	_items.add_theme_constant_override("separation", ROW_GAP)
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(_items)
	for entry in ITEMS:
		_add_item(entry)

	close_button = BUTTON.instantiate()
	close_button.name = "TutorialCloseButton"
	close_button.custom_minimum_size = Vector2(BUTTON_W, 55)
	close_button.position = Vector2(RIGHT_X + (RIGHT_W - BUTTON_W) / 2.0, BUTTON_Y)
	close_button.pressed.connect(close)
	_card_box.add_child(close_button)
	card.visible = false

func _add_item(entry: Array) -> void:
	var res := load(entry[0]) as ObjectResource
	if res == null:
		return
	var row := HBoxContainer.new()
	row.name = "Item"
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.add_child(row)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = icon_texture(res.texture)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = ITEM_COLOUR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := make_label(ITEM_SIZE, INK)
	label.name = "Text"
	label.text = res.description if res.description != "" else entry[1]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

func _build_hint() -> void:
	hint_label = make_label(30, Color(1, 1, 1))
	hint_label.name = "TutorialHint"
	hint_label.label_settings.outline_size = 10
	hint_label.label_settings.outline_color = Color(0, 0, 0, 0.9)
	# 关卡名下面、棋盘上面那一带
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.offset_left = -470
	hint_label.offset_right = 470
	hint_label.offset_top = 112
	hint_label.offset_bottom = 184
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.visible = false
	add_child(hint_label)

# ---------- 量版面用的 ----------

## 一行字的宽（像素）
static func text_width(text: String, font_size: int) -> float:
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

## 一个点（卡片坐标）离边框线还有多远：正数是余量，负数是压上了。四个角是弧，角上的点还要看离弧心多远
static func frame_margin(card_size: Vector2, p: Vector2) -> float:
	var m := minf(minf(p.x - EDGE_L, card_size.x - EDGE_R - p.x), minf(p.y - EDGE_T, card_size.y - EDGE_B - p.y))
	var centres := [Vector2(CORNER, CORNER), Vector2(card_size.x - CORNER, CORNER),
		Vector2(CORNER, card_size.y - CORNER), Vector2(card_size.x - CORNER, card_size.y - CORNER)]
	for c: Vector2 in centres:
		# 朝角的方向算正
		var dx: float = c.x - p.x if c.x < card_size.x / 2.0 else p.x - c.x
		var dy: float = c.y - p.y if c.y < card_size.y / 2.0 else p.y - c.y
		if dx > 0.0 and dy > 0.0:
			m = minf(m, CORNER_R - Vector2(dx, dy).length())
	return m

## 一块矩形离边框线还有多远。能放东西的范围是凸的，所以四个角都在里面，整块就都在里面
static func rect_margin(card_size: Vector2, rect: Rect2) -> float:
	return minf(minf(frame_margin(card_size, rect.position), frame_margin(card_size, rect.end)),
		minf(frame_margin(card_size, Vector2(rect.end.x, rect.position.y)), frame_margin(card_size, Vector2(rect.position.x, rect.end.y))))

## 一段字真正占的那一小块（画面坐标；不是标签框）：量每一行的宽，再按对齐方式算它在标签里的位置
static func text_rect(label: Label) -> Rect2:
	var settings: LabelSettings = label.label_settings
	var font_size: int = settings.font_size
	var lines: PackedStringArray = label.text.split("\n")
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, text_width(line, font_size))
	var line_h: float = settings.font.get_height(font_size)
	var h := (lines.size() - 1) * (line_h + settings.line_spacing) + line_h
	var x := 0.0
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (label.size.x - widest) / 2.0
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = label.size.x - widest
	var y := 0.0
	if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y = (label.size.y - h) / 2.0
	elif label.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y = label.size.y - h
	return Rect2(label.global_position + Vector2(x, y), Vector2(widest, h))

## 按钮上看得见的字占的那一块（画面坐标，不是按钮框）。带图标的按钮按整个按钮框算
static func button_text_rect(b: Button) -> Rect2:
	if b.icon != null:
		return Rect2(b.global_position, b.size)
	var font: Font = b.get_theme_font("font")
	var size: int = b.get_theme_font_size("font_size")
	var w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := font.get_height(size)
	var x := (b.size.x - w) / 2.0
	if b.alignment == HORIZONTAL_ALIGNMENT_LEFT: x = 0.0
	elif b.alignment == HORIZONTAL_ALIGNMENT_RIGHT: x = b.size.x - w
	return Rect2(b.global_position + Vector2(x, (b.size.y - h) / 2.0), Vector2(w, h))

## 排查用：items 是 [名字, 矩形（卡片坐标）] 的列表（第三个是 true 的是看不见的点按范围，只要求不出框、不参与查重叠）。
## 逐个报离边框线还有多少余量（至少 need 这么多），再两两查一遍有没有重叠，最后一行是结论
static func check_layout(card_size: Vector2, items: Array, need: float = 8.0) -> String:
	var out := PackedStringArray()
	var bad := 0
	var least := 1e9
	for it in items:
		var rect: Rect2 = it[1]
		var m := rect_margin(card_size, rect)
		least = minf(least, m)
		var ok := m >= (2.0 if it[2] else need)
		if not ok:
			bad += 1
		out.append("%s %s  x %.0f..%.0f  y %.0f..%.0f  离边框线 %.1f" % ["  " if ok else "× ", it[0], rect.position.x, rect.end.x, rect.position.y, rect.end.y, m])
	for i in items.size():
		for j in range(i + 1, items.size()):
			if items[i][2] or items[j][2]:
				continue
			var a: Rect2 = items[i][1]
			var b: Rect2 = items[j][1]
			if a.grow(0.1).intersects(b):
				bad += 1
				out.append("× 重叠：%s 和 %s" % [items[i][0], items[j][0]])
	out.append("RESULT 卡片版面：%s（%d 项，离边框线最少 %.1f 像素）" % ["通过" if bad == 0 else "没过，%d 处" % bad, items.size(), least])
	return "\n".join(out)

func _process(delta: float) -> void:
	if card.visible or main == null or not is_instance_valid(main): return
	# 技能充满、水车开，都是可以直接读出来的状态，不用去改原版的代码
	if main.active_control != null and main.active_control.is_charged:
		hint("skill")
	if main.end_portal_instance != null and main.end_portal_instance.is_active:
		hint("portal")
	if hint_label.visible:
		_hint_left -= delta
		if _hint_left <= 0.0:
			hint_label.visible = false
			# 这一条看完了，接着弹排着队的下一条
			if not _pending.is_empty():
				hint(_pending.pop_front())
	# 难度里这一档多出来的规矩，开头各提示一次
	rule_hints()

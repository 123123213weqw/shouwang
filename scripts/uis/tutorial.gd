class_name Tutorial extends Control
## 新手教程（原工程没有，新加的）。
##
## 三层：
##   1. 第一次进游戏，关卡载入以后先弹一张"玩法"卡片，把目标和最要紧的规则讲一遍，点"知道了"才开始；
##      卡片开着的时候整局暂停，不会误跳。
##   2. 之后在该用到的时候各提示一次：第一次踩到空格子、技能第一次充满、水车第一次开。提示是一行字，
##      出现在关卡名下面，几秒后自己消失，不打断游戏。
##   3. 暂停菜单里的"玩法"按钮随时能把卡片再调出来（这时按钮写的是"返回"）。
## 每一条只出现一次，看没看过记在存档里（Game.tutorial_seen）。
## 界面是用代码搭的，用的是游戏自己的按钮场景、手写字体和九宫格边框，和别的界面一个样子。

signal closed

const BUTTON := preload("res://scenes/uis/button.tscn")
const FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const BORDER := preload("res://assets/sprites/ui/nine-patch-border.png")
const PANEL := preload("res://assets/sprites/ui/nine-patch.png")
const CARD_SIZE := Vector2(940, 580)      # 画面是 1152×720（掌机）到 1280×720，卡片放在正中
const BAND := 30.0                        # 边框一圈在画面上的粗细（贴图里是 21 到 24 像素，角块不缩放）
const HINT_TIME := 7.0                    # 一条提示停几秒

var main: Node
var card: Control
var close_button: Button
var hint_label: Label
var _paused_by_me := false
var _hint_left := 0.0
var _shown: Dictionary = {}               # 这一局里已经弹过的提示
static var fake_pad := false              # 排查用：测试机上没有手柄，想看手柄版的那段说明就把它设成 true

func _ready() -> void:
	# 卡片开着的时候整局是暂停的，教程自己要能响应点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hint()
	_build_card()

func card_open() -> bool:
	return card.visible

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

# ---------- 提示 ----------

func hint(id: String) -> void:
	"""弹一条提示。同一条只弹一次"""
	if card.visible or _shown.has(id) or Game.tutorial_seen.has(id): return
	_shown[id] = true
	Game.tutorial_mark(id)
	hint_label.text = _hint_text(id)
	hint_label.visible = true
	hint_label.modulate.a = 0.0
	_hint_left = HINT_TIME
	create_tween().tween_property(hint_label, "modulate:a", 1.0, 0.3)

func _hint_text(id: String) -> String:
	match id:
		"empty": return "踩到空格子了：扣一步，连击清零。尽量沿着有灯的格子跳。"
		"skill": return "技能充满了，按 %s 放技能。" % _skill_key()
		"portal": return "水车开了，跳进去就过关。"
	return ""

# ---------- 卡片 ----------

## 第一局开头调用：还没看过卡片就弹出来
func maybe_show_rules() -> void:
	if not Game.tutorial_seen.has("rules"):
		show_card(true)

func show_card(first_time: bool) -> void:
	hint_label.visible = false
	close_button.text = "知道了" if first_time else "返回"
	_body.text = _rules_text()
	# 弹卡片的时候让整局暂停（原版的暂停菜单并不真的暂停）。本来就是暂停的话，关卡片时也不去动它
	_paused_by_me = not get_tree().paused
	if _paused_by_me:
		get_tree().paused = true
	if first_time:
		Game.tutorial_mark("rules")
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

func _rules_text() -> String:
	var lines := PackedStringArray()
	if _has_pad():
		lines.append("操作：左摇杆或十字键跳。A 放技能（在菜单里是确认），Start 呼出菜单。")
	else:
		lines.append("操作：WASD 跳一格，或者用鼠标点亮着的格子。空格放技能，Esc 呼出菜单。")
	lines.append("")
	lines.append("收够河灯，水车就会开，跳进水车就过关。")
	lines.append("落在有灯的格子上不扣步数；踩到空格子扣一步，连击清零。")
	lines.append("连击越高跳得越远。头顶的数字是剩下的步数，水车头顶的是还差几盏灯。")
	lines.append("收灯会给技能充能，充满了按 %s 放技能。" % _skill_key())
	return "\n".join(lines)

var _body: Label

func _make_label(size: int, colour: Color) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = size
	settings.font_color = colour
	settings.line_spacing = 8
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

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

	# 卡片：放在画面正中
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -CARD_SIZE.x / 2
	box.offset_top = -CARD_SIZE.y / 2
	box.offset_right = CARD_SIZE.x / 2
	box.offset_bottom = CARD_SIZE.y / 2
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# 底：用现成的圆角底板贴图（和边框一样的九宫格画法），染成深色。不能用方块的色块：
	# 它的直角会从圆角的边框里露出来
	var face := NinePatchRect.new()
	face.texture = PANEL
	face.patch_margin_left = 90
	face.patch_margin_top = 90
	face.patch_margin_right = 90
	face.patch_margin_bottom = 90
	face.self_modulate = Color(0.03, 0.12, 0.11)
	face.size = CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(face)

	# 边框：九宫格。四个角的弧有七十多个像素，角块要切得比它大（115），拉伸的时候才不会把弧拉变形
	var frame := NinePatchRect.new()
	frame.texture = BORDER
	frame.patch_margin_left = 115
	frame.patch_margin_top = 115
	frame.patch_margin_right = 115
	frame.patch_margin_bottom = 115
	frame.self_modulate = Color(0.56, 0.86, 0.77)
	frame.size = CARD_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)

	var title := _make_label(46, Color(1, 1, 1))
	title.text = "玩法"
	title.position = Vector2(0, BAND + 14)         # 边框里面，别压在边框上
	title.size = Vector2(CARD_SIZE.x, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_body = _make_label(30, Color(0.94, 0.96, 0.92))
	_body.label_settings.line_spacing = 6
	_body.position = Vector2(60, 106)
	_body.size = Vector2(CARD_SIZE.x - 120, 350)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)

	close_button = BUTTON.instantiate()
	close_button.name = "TutorialCloseButton"
	close_button.custom_minimum_size = Vector2(314, 55)
	close_button.position = Vector2(CARD_SIZE.x / 2 - 157, CARD_SIZE.y - 106)
	close_button.pressed.connect(close)
	box.add_child(close_button)
	card.visible = false

func _build_hint() -> void:
	hint_label = _make_label(30, Color(1, 1, 1))
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

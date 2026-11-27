class_name RulesetPicker extends Control
## 标题页的"难度"选择面板（类名和节点名还是叫 Ruleset…：没改，省得测试的步骤文件跟着改）。
## 左边一列是四档难度（Game.rulesets，简单、中等、困难、非常困难），右边是鼠标停着的哪一档的说明，
## 没停时显示现在选中的：先是几句话（Ruleset.summary），再列出这一档打开了哪些规矩（Ruleset.rule_lines）。
## 点一档就选中它（Game.select_ruleset，会记进存档），按"返回"收起。
## 只在标题页上用：这儿地方大，写得下每一档的规矩。玩到一半想换走另一条路——暂停菜单里、没过的结算面板上的
## 加减器（DifficultyStepper），一行点一下就换。
## 面板由 TitleControl 创建，挂在 CanvasLayer/TitleControl 下；显示和收起都由 TitleControl 通知
## （show_rulesets() / return_to_title()），面板自己不去动标题页的别的控件。
## 卡片、字体、按钮场景都和"玩法"卡片（Tutorial）是同一套。

signal selected    ## 选了一档难度
signal closed      ## 按了"返回"

# ---- 版面（都是卡片里的坐标）----
const CARD_SIZE := Vector2(940, 530)
const TITLE := "难度"
const TITLE_Y := 62.0                    # 字顶离上边框线留出十来个像素
const LIST_X := 63.0                     # 左栏：难度列表
const LIST_W := 150.0
const LIST_Y := 112.0
const OPTION_H := 40.0                   # 一档一行
const OPTION_GAP := 6
const OPTION_SIZE := 34                  # 难度名字的字号
const DOT_X := 12.0                      # 选中标记（小圆点）
const DOT_D := 12.0
const TEXT_X := 34.0                     # 难度名字从这儿开始写（给圆点让地方；没选中的也一样，名字才对得齐）
const DIVIDER_X := 242.0                 # 两栏中间的竖线
const SUMMARY_X := 272.0                 # 右栏：说明
const SUMMARY_W := 590.0                 # 24 个字一行
const NAME_Y := 112.0                    # 右栏顶上：难度的名字
const NAME_SIZE := 40
const TAG_SIZE := 24
const SUMMARY_Y := 168.0
const SUMMARY_SIZE := 24
const SUMMARY_SPACING := 5               # 行距。说明加规矩最多 8 行（两行说明、一行空、五行规矩），行距 9 放不下
const RETURN_X := 73.0                   # "返回"：和别的页面一样在左下角，带一个返回的箭头
const RETURN_Y := 392.0
const RETURN_W := 190.0                  # 比别的页面的返回按钮窄 10 像素：它的右头原本挨着右栏的说明（x 272），
										##     难度四档以后说明长了，会和它报"重叠"。窄了这 10 像素，中间就空出 9 像素

const IDLE := Color(0.40234375, 0.40234375, 0.40234375)   # 按钮主题里平时的灰
const HOVER := Color(1, 1, 1)
const CHOSEN := Color(1.0, 0.84, 0.55)                     # 选中的那套：烛火的颜色，和道具图标一个色
const CHOSEN_HOVER := Color(1.0, 0.93, 0.78)
const BACK_ICON := preload("res://assets/sprites/ui/actions/back.png")

const BREAK_AFTER := "。，、：；！？"      # 说明折行时只在这些标点后面断
const NO_START := "。，、：；！？）」"       # 这些不能落在行首

var _card: Control
var _title: Label
var _options: VBoxContainer
var _divider: ColorRect
var _name_label: Label
var _tag: Label                          # 名字右边的"现在选的"
var _summary: Label
var _return_button: Button
var _buttons: Array[Button] = []         # 和 _rulesets 一一对应
var _rulesets: Array[Ruleset] = []
var _ids := PackedStringArray()          # 上次建列表时的难度 id：没变就不用重建

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # 挡住落在卡片外面的点击
	visible = false
	_build()

func is_open() -> bool:
	return visible

func open() -> void:
	_sync_options()
	_refresh()
	_show(Game.ruleset)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)

func close() -> void:
	visible = false

## 排查用：把面板上的东西逐个量一遍（卡片坐标），看有没有压到边框、出框、互相重叠。面板开着的时候调
##   call ruleset_picker.gd debug_picker_layout
func debug_picker_layout() -> String:
	if not visible:
		return "面板没开着"
	var items: Array = []
	_add_text(items, "标题", _title)
	for i in _buttons.size():
		var b := _buttons[i]
		var what := "难度%d" % i
		var h: float = Tutorial.FONT.get_height(OPTION_SIZE)
		var rect := Rect2(b.global_position + Vector2(TEXT_X, (b.size.y - h) / 2.0), Vector2(Tutorial.text_width(b.text, OPTION_SIZE), h))
		items.append([what, Rect2(_to_card(rect.position), rect.size), false])
		var dot := b.get_node("SelectedDot") as Control
		if dot.visible:
			items.append(["圆点%d" % i, _rect_in_card(dot), false])
		items.append(["按钮%d" % i, _rect_in_card(b), true])
	_add_text(items, "名字", _name_label)
	if _tag.visible:
		_add_text(items, "现在选的", _tag)
	_add_text(items, "说明", _summary)
	items.append(["返回", _rect_in_card(_return_button), true])
	# 返回按钮带着图标：看得见的部分按整个按钮框算，也要和别的字不重叠
	if _return_button.icon == null:
		var t: Rect2 = Tutorial.button_text_rect(_return_button)
		items.append(["返回上的字", Rect2(_to_card(t.position), t.size), false])
	else:
		items.append(["返回（带图标）", _rect_in_card(_return_button), false])
	return Tutorial.check_layout(CARD_SIZE, items)

func _add_text(items: Array, what: String, label: Label) -> void:
	var rect := Tutorial.text_rect(label)
	items.append([what, Rect2(_to_card(rect.position), rect.size), false])

func _rect_in_card(c: Control) -> Rect2:
	return Rect2(_to_card(c.global_position), c.size)

func _to_card(p: Vector2) -> Vector2:
	return _card.get_global_transform().affine_inverse() * p

# ---------- 选难度 ----------

## 难度列表跟着 Game.rulesets 走。难度没变就留着原来的按钮，只换一下标记
func _sync_options() -> void:
	var ids := PackedStringArray()
	for r in Game.rulesets:
		ids.append(r.id)
	if ids == _ids:
		return
	_ids = ids
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_rulesets.clear()
	for r in Game.rulesets:
		_options.add_child(_make_option(r))
		_rulesets.append(r)
	_options.custom_minimum_size = Vector2(LIST_W, _rulesets.size() * OPTION_H + maxi(_rulesets.size() - 1, 0) * OPTION_GAP)
	_divider.size = Vector2(2.0, _options.custom_minimum_size.y)

func _make_option(r: Ruleset) -> Button:
	var b := Tutorial.BUTTON.instantiate() as Button
	b.name = "RulesetOption_" + r.id.validate_node_name()
	b.custom_minimum_size = Vector2(LIST_W, OPTION_H)
	b.add_theme_font_size_override("font_size", OPTION_SIZE)
	b.text = r.title if r.title != "" else r.id
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = TEXT_X
		b.add_theme_stylebox_override(state, box)
	var dot := SelectedDot.new()
	dot.name = "SelectedDot"
	dot.colour = CHOSEN
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = DOT_X
	dot.offset_right = DOT_X + DOT_D
	dot.offset_top = -DOT_D / 2.0
	dot.offset_bottom = DOT_D / 2.0
	dot.visible = false
	b.add_child(dot)
	b.pressed.connect(_choose.bind(r))
	b.mouse_entered.connect(_show.bind(r))
	b.mouse_exited.connect(_show.bind(null))
	_buttons.append(b)
	return b

func _choose(r: Ruleset) -> void:
	Game.select_ruleset(r)
	_refresh()
	_show(r)              # 名字右边的"现在选的"要跟着出来
	selected.emit()

## 把选中标记和颜色按"现在选的是哪套"刷一遍
func _refresh() -> void:
	for i in _buttons.size():
		var chosen: bool = _rulesets[i] == Game.ruleset
		var b := _buttons[i]
		var idle := CHOSEN if chosen else IDLE
		# 点过的按钮会一直占着焦点，文字用的是"焦点"那个颜色：各种状态的颜色都写明白，别让它自己变白
		b.add_theme_color_override("font_color", idle)
		b.add_theme_color_override("font_focus_color", idle)
		b.add_theme_color_override("font_hover_color", CHOSEN_HOVER if chosen else HOVER)
		b.add_theme_color_override("font_pressed_color", CHOSEN_HOVER if chosen else HOVER)
		b.add_theme_color_override("font_hover_pressed_color", CHOSEN_HOVER if chosen else HOVER)
		b.get_node("SelectedDot").visible = chosen

## 右栏显示哪一档的说明。r 是空（鼠标没停在哪个档上）就显示现在选中的那档
func _show(r: Ruleset) -> void:
	if r == null:
		r = Game.ruleset
	var has: bool = r != null
	_name_label.visible = has
	_summary.visible = has
	_tag.visible = false
	if not has:
		return
	_name_label.text = r.title if r.title != "" else r.id
	_summary.text = _summary_text(r)
	# "现在选的"跟在名字右边；名字太长放不下就不显示
	_tag.text = "现在选的"
	var x := SUMMARY_X + Tutorial.text_width(_name_label.text, NAME_SIZE) + 16.0
	_tag.position.x = x
	_tag.visible = r == Game.ruleset and x + Tutorial.text_width(_tag.text, TAG_SIZE) <= SUMMARY_X + SUMMARY_W

## 右栏的说明：先是资源里写的几句话（一句一行，放不下再折行），空一行，然后一条一行列出这一档打开的规矩
func _summary_text(r: Ruleset) -> String:
	var parts: PackedStringArray = []
	var said: PackedStringArray = []
	for sentence in r.summary.strip_edges().split("\n"):
		sentence = sentence.strip_edges()
		if sentence != "":
			said.append("\n".join(_wrap(sentence)))
	if not said.is_empty():
		parts.append("\n".join(said))
	var rules: PackedStringArray = []
	for line in r.rule_lines():
		rules.append("· " + line)
	if not rules.is_empty():
		parts.append("\n".join(rules))
	return "\n\n".join(parts)

## 把一段话折成几行：先按宽度定下几行，再在标点后面找断点，让各行长短相近。每行都不会超过右栏的宽
func _wrap(text: String) -> PackedStringArray:
	if Tutorial.text_width(text, SUMMARY_SIZE) <= SUMMARY_W:
		return PackedStringArray([text])
	var lines := PackedStringArray()
	var rest := text
	var left := ceili(Tutorial.text_width(rest, SUMMARY_SIZE) / SUMMARY_W)
	while left > 1:
		var cut := _break_at(rest, Tutorial.text_width(rest, SUMMARY_SIZE) / left, left - 1)
		lines.append(rest.substr(0, cut))
		rest = rest.substr(cut)
		left -= 1
	lines.append(rest)
	return lines

## 在 rest 里挑断点：离 target 最近，并且剩下的字还放得进 lines_left 行。标点后面的断点优先；
## 一个标点都没有的话就在两个字中间断，不让标点落在行首
func _break_at(rest: String, target: float, lines_left: int) -> int:
	var rest_w := Tutorial.text_width(rest, SUMMARY_SIZE)
	var best := -1
	var best_score := INF
	for i in range(1, rest.length()):
		var w := Tutorial.text_width(rest.substr(0, i), SUMMARY_SIZE)
		if w > SUMMARY_W or rest_w - w > lines_left * SUMMARY_W:
			continue
		var score := absf(w - target)
		if BREAK_AFTER.contains(rest[i - 1]):
			score -= 1000.0
		elif NO_START.contains(rest[i]):
			continue
		if score < best_score:
			best_score = score
			best = i
	return maxi(best, 1)

# ---------- 搭界面 ----------

func _build() -> void:
	# 背后压暗
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.03, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_card = Tutorial.make_card(self, CARD_SIZE)
	_card.name = "RulesetCard"

	_title = Tutorial.make_label(46, Color(1, 1, 1))
	_title.name = "RulesetTitle"
	_title.text = TITLE
	_title.position = Vector2(0, TITLE_Y)
	_title.size = Vector2(CARD_SIZE.x, 50)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_title)

	_options = VBoxContainer.new()
	_options.name = "RulesetOptions"
	_options.position = Vector2(LIST_X, LIST_Y)
	_options.size = Vector2(LIST_W, 0)
	_options.add_theme_constant_override("separation", OPTION_GAP)
	_card.add_child(_options)

	_divider = ColorRect.new()
	_divider.name = "Divider"
	_divider.color = Color(Tutorial.MINT, 0.35)
	_divider.position = Vector2(DIVIDER_X, LIST_Y)
	_divider.size = Vector2(2, 0)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_divider)

	_name_label = Tutorial.make_label(NAME_SIZE, Color(1, 1, 1))
	_name_label.name = "RulesetName"
	_name_label.position = Vector2(SUMMARY_X, NAME_Y)
	_name_label.size = Vector2(SUMMARY_W, 41)
	_card.add_child(_name_label)

	_tag = Tutorial.make_label(TAG_SIZE, CHOSEN)
	_tag.name = "RulesetCurrentTag"
	_tag.text = "现在选的"
	_tag.position = Vector2(SUMMARY_X + 100, NAME_Y + 14)     # 横向位置跟着名字走，显示的时候再定
	_tag.size = Vector2(160, 25)
	_tag.visible = false
	_card.add_child(_tag)

	_summary = Tutorial.make_label(SUMMARY_SIZE, Tutorial.INK)
	_summary.name = "RulesetSummary"
	_summary.label_settings.line_spacing = SUMMARY_SPACING
	_summary.position = Vector2(SUMMARY_X, SUMMARY_Y)
	_summary.size = Vector2(SUMMARY_W, 0)
	_card.add_child(_summary)

	_return_button = Tutorial.BUTTON.instantiate() as Button
	_return_button.name = "RulesetReturnButton"
	_return_button.text = "返回"
	# 返回箭头和别的页面是同一张图。图上箭头只占中间一小块，裁出来再缩放，按钮不用像别的页面那样高
	_return_button.icon = Tutorial.icon_texture(BACK_ICON)
	_return_button.add_theme_constant_override("icon_max_width", 34)
	_return_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_return_button.custom_minimum_size = Vector2(RETURN_W, 55)
	_return_button.position = Vector2(RETURN_X, RETURN_Y)
	_return_button.pressed.connect(func(): closed.emit())
	_card.add_child(_return_button)

## 选中标记：难度名字左边的小圆点，自己画的（手写字体里没有"●"这个字形，写上去是个空框）
class SelectedDot extends Control:
	var colour := Color(1.0, 0.84, 0.55)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, colour, true, -1.0, true)

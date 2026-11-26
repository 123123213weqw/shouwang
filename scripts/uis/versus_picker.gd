class_name VersusPicker extends Control
## 标题页的"对战"选择面板。
## 左边一列是对战的五种玩法（scripts/versus/），右边是鼠标停着的那个的说明；
## 点"开战"就用现在看着的这个开局（记进 Game.versus），去选同伴；按"返回"收起。
## 面板由 TitleControl 建出来，挂在 CanvasLayer/TitleControl 下；显示和收起都由 TitleControl 通知。
## 卡片、字体、按钮和"玩法方案"那个面板（ruleset_picker.gd）是同一套。

signal chosen(id: String)      ## 按了"开战"
signal closed                  ## 按了"返回"

# ---- 版面（都是卡片里的坐标）----
const CARD_SIZE := Vector2(940, 530)
const TITLE := "对战"
const TITLE_Y := 62.0
const LIST_X := 63.0                     # 左栏：玩法列表
const LIST_W := 170.0
const LIST_Y := 112.0
const OPTION_H := 44.0                   # 一个玩法一行
const OPTION_GAP := 8
const OPTION_SIZE := 38
const TEXT_X := 12.0
const DIVIDER_X := 262.0                 # 两栏中间的竖线
const NAME_X := 292.0                    # 右栏：玩法名字
const NAME_Y := 112.0
const NAME_SIZE := 40
const SUMMARY_X := 292.0                 # 右栏：说明
const SUMMARY_W := 570.0
const SUMMARY_Y := 168.0
const SUMMARY_SIZE := 25
const SUMMARY_SPACING := 10
const BOTTOM_Y := 418.0                  # 底下两个按钮
const RETURN_X := 73.0                   # "返回"：和别的页面一样在左下角
const RETURN_W := 200.0
const GO_W := 240.0

const IDLE := Color(0.40234375, 0.40234375, 0.40234375)   # 按钮主题里平时的灰
const HOVER := Color(1, 1, 1)
const LOOKING := Color(1.0, 0.84, 0.55)                   # 右边正在看的那个：烛火的颜色
const BACK_ICON := preload("res://assets/sprites/ui/actions/back.png")

var _name_label: Label
var _summary: Label
var _go: Button
var _return_button: Button
var _buttons: Array[Button] = []         # 和 VersusBase.IDS 一一对应
var _looking := 0                        # 右边显示的是第几个

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # 挡住落在卡片外面的点击
	visible = false
	_build()

func open() -> void:
	_refresh()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)

func close() -> void:
	visible = false

## 右边改成看第 i 个（从 0 数起）。鼠标停在哪个玩法上、点了哪个，都是看哪个
func _look(i: int) -> void:
	_looking = clampi(i, 0, _buttons.size() - 1)
	_refresh()

## 排查用：让面板看着第 i 个（调试遥控调）
func debug_look(i: int) -> void:
	_look(i - 1)

func _make_option(i: int) -> Button:
	var id: String = VersusBase.IDS[i]
	var b := Tutorial.BUTTON.instantiate() as Button
	b.name = "VersusOption_" + id
	b.custom_minimum_size = Vector2(LIST_W, OPTION_H)
	b.add_theme_font_size_override("font_size", OPTION_SIZE)
	b.text = VersusBase.NAMES[id]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = TEXT_X
		b.add_theme_stylebox_override(state, box)
	b.pressed.connect(_look.bind(i))
	b.mouse_entered.connect(_look.bind(i))
	_buttons.append(b)
	return b

## 名字的颜色和右栏都按"现在看的是哪个"刷一遍
func _refresh() -> void:
	for i in _buttons.size():
		var b := _buttons[i]
		var idle: Color = LOOKING if i == _looking else IDLE
		# 点过的按钮会一直占着焦点，文字用的是"焦点"那个颜色：各种状态的颜色都写明白
		b.add_theme_color_override("font_color", idle)
		b.add_theme_color_override("font_focus_color", idle)
		b.add_theme_color_override("font_hover_color", HOVER)
		b.add_theme_color_override("font_pressed_color", HOVER)
		b.add_theme_color_override("font_hover_pressed_color", HOVER)
	var id: String = VersusBase.IDS[_looking]
	_name_label.text = VersusBase.NAMES[id]
	_summary.text = VersusBase.SUMMARIES[id]

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.03, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var card := Tutorial.make_card(self, CARD_SIZE)
	card.name = "VersusCard"

	var heading := Tutorial.make_label(46, Color(1, 1, 1))
	heading.name = "VersusTitle"
	heading.text = TITLE
	heading.position = Vector2(0, TITLE_Y)
	heading.size = Vector2(CARD_SIZE.x, 50)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(heading)

	var options := VBoxContainer.new()
	options.name = "VersusOptions"
	options.position = Vector2(LIST_X, LIST_Y)
	options.size = Vector2(LIST_W, 0)
	options.add_theme_constant_override("separation", OPTION_GAP)
	card.add_child(options)
	for i in VersusBase.IDS.size():
		options.add_child(_make_option(i))

	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(Tutorial.MINT, 0.35)
	divider.position = Vector2(DIVIDER_X, LIST_Y)
	divider.size = Vector2(2, OPTION_H * VersusBase.IDS.size() + OPTION_GAP * (VersusBase.IDS.size() - 1))
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(divider)

	_name_label = Tutorial.make_label(NAME_SIZE, Color(1, 1, 1))
	_name_label.name = "VersusName"
	_name_label.position = Vector2(NAME_X, NAME_Y)
	_name_label.size = Vector2(SUMMARY_W, 41)
	card.add_child(_name_label)

	_summary = Tutorial.make_label(SUMMARY_SIZE, Tutorial.INK)
	_summary.name = "VersusSummary"
	_summary.label_settings.line_spacing = SUMMARY_SPACING
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.position = Vector2(SUMMARY_X, SUMMARY_Y)
	_summary.size = Vector2(SUMMARY_W, 0)
	card.add_child(_summary)

	_return_button = Tutorial.BUTTON.instantiate() as Button
	_return_button.name = "VersusReturnButton"
	_return_button.text = "返回"
	_return_button.icon = Tutorial.icon_texture(BACK_ICON)
	_return_button.add_theme_constant_override("icon_max_width", 34)
	_return_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_return_button.custom_minimum_size = Vector2(RETURN_W, 55)
	_return_button.position = Vector2(RETURN_X, BOTTOM_Y)
	_return_button.pressed.connect(func() -> void: closed.emit())
	card.add_child(_return_button)

	_go = Tutorial.BUTTON.instantiate() as Button
	_go.name = "VersusGoButton"
	_go.text = "开战"
	_go.custom_minimum_size = Vector2(GO_W, 55)
	_go.position = Vector2(CARD_SIZE.x - RETURN_X - GO_W, BOTTOM_Y)
	_go.pressed.connect(func() -> void: chosen.emit(VersusBase.IDS[_looking]))
	card.add_child(_go)

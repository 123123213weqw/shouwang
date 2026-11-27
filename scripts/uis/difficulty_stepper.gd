class_name DifficultyStepper extends HBoxContainer
## 难度的加减器：一行，"难度 ‹ 中等 ›"。玩到一半觉得太难或太简单，点一下就换一档，不用退回标题页
##（标题页上另有带说明的选择页，RulesetPicker）。挂在两处：暂停菜单里一行、没过的结算面板上一行。
## 点 ‹ 是调低一档，点 › 是调高一档；到头的那一边不露面。换了以后怎么办由挂它的地方决定（见 main.gd）：
## 暂停菜单里是这一关按新难度从头来；结算面板上点 ‹ 是调低以后马上重来这一关，点 › 只换过去、面板刷新。
## 字、按钮、箭头都是游戏自己的：手写字体、按钮场景，箭头是 tools/art/chevron.py 画的剪影（字体里没有箭头的字形）。
## 它只管显示和发信号：现在是哪一档读 Game.ruleset，换档、记存档都在 main.change_difficulty。

signal stepped(delta: int)     ## 有人点了箭头：-1 是调低一档，+1 是调高一档

const BUTTON := preload("res://scenes/uis/button.tscn")
const BUTTON_MATERIAL := preload("res://materials/button_material.tres")
const CHEVRON := preload("res://assets/sprites/ui/rules/chevron.png")
const IDLE := Color(0.40234375, 0.40234375, 0.40234375)   # 按钮主题里平时的灰：这一行不跟别的按钮抢眼

static var _chevron_left: Texture2D    # 朝左的那张（把朝右的图左右翻过来）。这个引擎的按钮不能翻转图标，只能另做一张

var _name_size := 54
var _show_title := true
var _centered := true
var _title_size := 0              # "难度"两个字的字号；0 是和档名一样大
var _arrow_w := 58.0              # 箭头按钮多宽
var _gap := 16                    # 一样东西和另一样之间隔多少
var _title: Label
var _name: Label
var _down: Button
var _up: Button

## name_size：档名的字号，跟着旁边按钮的字走。show_title：要不要"难度"两个字。
## centered：这一行的东西居中（暂停菜单里，别的按钮的字也是居中的）还是靠左（结算面板上，别的按钮的字靠左）。
## title_size："难度"两个字的字号（0 是和档名一样大）；arrow_w：箭头按钮多宽；gap：每样东西之间隔多少。
## 结算面板上左下那一栏只有三百来像素宽、右边紧挨着纪录列表，所以那一行字小一号、挤一挤；暂停菜单里宽得多，字跟着按钮一样大
func _init(name_size := 54, show_title := true, centered := true, title_size := 0, arrow_w := 58.0, gap := 16) -> void:
	_name_size = name_size
	_show_title = show_title
	_centered = centered
	_title_size = title_size if title_size > 0 else name_size
	_arrow_w = arrow_w
	_gap = gap

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", _gap)
	alignment = BoxContainer.ALIGNMENT_CENTER if _centered else BoxContainer.ALIGNMENT_BEGIN
	if _show_title:
		_title = _make_label("难度", _title_size)
		_title.name = "Title"
		add_child(_title)
	_down = _make_arrow("DiffDown", false)
	add_child(_down)
	_name = _make_label("", _name_size)
	_name.name = "TierName"
	add_child(_name)
	_up = _make_arrow("DiffUp", true)
	add_child(_up)
	_down.pressed.connect(func() -> void: stepped.emit(-1))
	_up.pressed.connect(func() -> void: stepped.emit(1))
	refresh()

## 按现在选的难度（Game.ruleset）刷一遍：档名、两头露不露面
func refresh() -> void:
	var i := _index()
	_name.text = Game.ruleset.title if Game.ruleset != null and Game.ruleset.title != "" else "—"
	_down.visible = i > 0
	_up.visible = i >= 0 and i < Game.rulesets.size() - 1

## 现在是 Game.rulesets 里的第几档（它们是按文件名排的，也就是由易到难）；认不出返回 -1
func _index() -> int:
	return Game.rulesets.find(Game.ruleset) if Game.ruleset != null else -1

func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font = Tutorial.FONT
	settings.font_size = size
	settings.font_color = IDLE
	l.label_settings = settings
	# 和设置页的行名一样，套按钮的那个材质：字会跟着别的按钮一起轻轻抖，是一套的
	l.material = BUTTON_MATERIAL
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 一个箭头按钮：只有图标，没有字。pointing_right 为假是朝左的 ‹（用左右翻过来的那张图）
func _make_arrow(node_name: String, pointing_right: bool) -> Button:
	var b := BUTTON.instantiate() as Button
	b.name = node_name
	b.text = ""
	# 图的四周留白很大（画布 311×316，箭头只占中间一块）：裁到有笔画的地方再缩放，和"返回"按钮的做法一样
	b.icon = Tutorial.icon_texture(_chevron(pointing_right))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(_arrow_w, _name_size + 8)
	b.add_theme_constant_override("icon_max_width", 30)
	return b

## 箭头的图：朝右的是画出来的那张，朝左的是它左右翻过来的（只翻一次，记下来）
static func _chevron(pointing_right: bool) -> Texture2D:
	if pointing_right: return CHEVRON
	if _chevron_left == null:
		var img: Image = CHEVRON.get_image()
		if img.is_compressed(): img.decompress()
		img.flip_x()
		_chevron_left = ImageTexture.create_from_image(img)
	return _chevron_left

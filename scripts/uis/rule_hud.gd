class_name RuleHud extends Control
## 游戏画面左上角的两个小东西。难度里打开了哪条规矩，哪个才露面（它们只读游戏里的状态，玩法不依赖它们）：
##   风向  一面小旗，飘向哪边风就往哪边吹；旁边写着风的名字。名字照老说法记的是"从哪边来"：
##         北风从画面顶上往近处刮，西风从左边往右边刮。顺风跳得远、逆风跳得近。
##   夜巡  插在灯盏里的一支蜡烛。蜡从头上往下烧，烧完离你最远的那盏河灯就灭；每跳一下蜡长回一点。
##         蜡只剩三成的时候火苗变红、跳得急。
## 旗子、蜡烛、灯盏都是 tools/art/ 里的脚本画的白色剪影（wind_flag.py、candle.py），颜色在这里乘上去。
## 火苗太小，画不成剪影，是这里用代码画的（和难度选择页的小圆点一样）。
## 蜡烛的图只露出下半截：烧掉的部分拿裁切藏起来，蜡的粗细不变；火苗跟在露出来的那一头上。

const FLAG := preload("res://assets/sprites/ui/rules/wind_flag.png")
const CANDLE := preload("res://assets/sprites/ui/rules/candle.png")
const HOLDER := preload("res://assets/sprites/ui/rules/candle_holder.png")

const FLAG_W := 68.0                   # 旗子的图有留白，旗面在这块框里约 30×33 像素
const LABEL_SIZE := 28
const LABEL_W := 64.0
const LABEL_H := 36.0
const GAP := 10.0                      # 风和蜡烛之间

const CANDLE_H := 66.0                 # 蜡烛没烧的时侯有多高
const CANDLE_W := 23.0                 # 蜡烛多粗（图里蜡烛宽 63、高 181，等比）
const HOLDER_W := 44.0                 # 灯盏多宽
const RIM_Y := 84.0                    # 灯盏的口离这一块的顶多远（蜡烛插在这儿，火苗、蜡烛都在它上面）
const SINK := 13.0                     # 蜡烛脚插进灯盏里多深（这一截被盏挡着，看不见）

# 两张图里图形各占哪一块（和 candle.py 里量出来的一致）
const CANDLE_TEX := 256.0
const CANDLE_BOX := Rect2(96.0, 40.0, 63.0, 181.0)
const HOLDER_SCALE := HOLDER_W / 95.0          # 灯盏的图 311×316，盏占 x 108..203、y 122..192
const NIGHT_HEIGHT := RIM_Y + 70.0 * HOLDER_SCALE
const NIGHT_SCALE := 0.45

const WIND_NAMES := {
	Vector2i(0, 1): "北风",       # 从画面顶上往近处刮
	Vector2i(0, -1): "南风",
	Vector2i(-1, 0): "东风",      # 从左往右刮
	Vector2i(1, 0): "西风",
}

const INK := Color(0.94, 0.96, 0.92)            # 旗子：和卡片上的正文一个颜色
const WAX := Color(0.98, 0.93, 0.80)            # 蜡：暖白
const MINT := Color(0.56, 0.86, 0.77)           # 灯盏：和卡片的边框一个颜色

var _wind: Control
var _flag: TextureRect
var _label: Label
var _night: Control
var _clip: Control                             # 裁蜡烛的框：只露出框里那部分
var _candle: TextureRect
var _flame: Flame
var _frac := 1.0                               # 蜡还剩几成
var _wind_dir := Vector2i.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 按这一档搭出旗子和蜡烛，以这一行的中线为 y = 0。
func setup(ruleset: Ruleset) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_wind = null
	_night = null
	_flame = null
	if ruleset == null: return
	var next_x := 0.0
	if ruleset.wind:
		_build_wind()
		next_x = FLAG_W + LABEL_W + GAP
	if ruleset.night_watch:
		_build_night(next_x + HOLDER_W * NIGHT_SCALE / 2.0)

func _build_wind() -> void:
	_wind = Control.new()
	_wind.name = "Wind"
	_wind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wind)
	_flag = TextureRect.new()
	_flag.name = "Flag"
	_flag.texture = FLAG
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag.size = Vector2(FLAG_W, FLAG_W)
	_flag.position.y = -FLAG_W / 2.0
	_flag.pivot_offset = _flag.size / 2.0
	_flag.self_modulate = INK
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind.add_child(_flag)
	_label = Tutorial.make_label(LABEL_SIZE, INK)
	_label.name = "WindName"
	_label.position = Vector2(FLAG_W, -LABEL_H / 2.0)
	_label.size = Vector2(LABEL_W, LABEL_H)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.label_settings.outline_size = 8
	_label.label_settings.outline_color = Color(0.0, 0.03, 0.03, 0.8)
	_wind.add_child(_label)

func _build_night(x: float) -> void:
	_night = Control.new()
	_night.name = "Night"
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night.position = Vector2(x, -NIGHT_HEIGHT * NIGHT_SCALE / 2.0)
	_night.scale = Vector2.ONE * NIGHT_SCALE
	add_child(_night)
	# 裁蜡烛的框：底边钉在蜡烛脚底下，高度跟着蜡走。它在灯盏的前面加进来，所以画在灯盏后面：插进盏里的那一截被盏挡着
	_clip = Control.new()
	_clip.name = "CandleClip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_clip.size = Vector2(CANDLE_W + 16.0, CANDLE_H + SINK + 2.0)
	_night.add_child(_clip)
	_candle = TextureRect.new()
	_candle.name = "Candle"
	_candle.texture = CANDLE
	_candle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_candle.stretch_mode = TextureRect.STRETCH_SCALE
	_candle.self_modulate = WAX
	_candle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_candle)
	# 灯盏：整张图等比缩到 44 像素宽的盏，再按图里盏的位置把盏的口摆在 RIM_Y 那条线上
	var holder := TextureRect.new()
	holder.name = "Holder"
	holder.texture = HOLDER
	holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.stretch_mode = TextureRect.STRETCH_SCALE
	holder.self_modulate = MINT
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(311.0, 316.0) * HOLDER_SCALE
	holder.position = Vector2(-HOLDER_W / 2.0 - 108.0 * HOLDER_SCALE, RIM_Y - 122.0 * HOLDER_SCALE)
	_night.add_child(holder)
	_flame = Flame.new()
	_flame.name = "Flame"
	_flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night.add_child(_flame)
	set_night(1.0)

## 这一关的风往哪边吹。没有风（dir 是零）旗子收起来
func show_wind(dir: Vector2i) -> void:
	_wind_dir = dir
	if _wind == null: return
	_wind.visible = dir != Vector2i.ZERO
	if dir == Vector2i.ZERO: return
	_flag.flip_h = false
	_flag.rotation_degrees = 0.0
	if dir.x < 0:
		_flag.flip_h = true               # 东风：旗子往左飘
	elif dir.y > 0:
		_flag.rotation_degrees = 90.0     # 北风：往近处飘，旗子转成朝下
	elif dir.y < 0:
		_flag.rotation_degrees = -90.0    # 南风：往远处飘
	_label.text = WIND_NAMES.get(dir, "风")

## 蜡还剩几成（0 到 1）：露出从脚往上这么长的一截，火苗跟在头上
func set_night(frac: float) -> void:
	_frac = clampf(frac, 0.0, 1.0)
	if _night == null: return
	var shown: float = maxf(_frac * CANDLE_H, 1.5)
	var foot: float = RIM_Y + SINK                 # 蜡烛脚（在灯盏里）
	_clip.size = Vector2(_clip.size.x, shown + SINK + 2.0)
	_clip.position = Vector2(-_clip.size.x / 2.0, foot + 2.0 - _clip.size.y)
	var s: float = CANDLE_H / CANDLE_BOX.size.y
	_candle.size = Vector2(CANDLE_TEX, CANDLE_TEX) * s
	_candle.position = Vector2(_clip.size.x / 2.0 - CANDLE_BOX.get_center().x * s, _clip.size.y - 2.0 - SINK - CANDLE_BOX.end.y * s)
	_flame.position = Vector2(-Flame.W / 2.0, foot - shown - Flame.H + 5.0)
	_flame.low = _frac < 0.3

func has_wind() -> bool:
	return _wind != null and _wind.visible

func has_night() -> bool:
	return _night != null and _night.visible

## 旗子旁边写的风的名字（旗子没露面是空字符串）
func wind_name() -> String:
	return _label.text if _wind != null and _wind.visible else ""

## 排查用：现在显示着什么（测试里核对风向和蜡烛的位置用）
func debug_state() -> String:
	var wind_txt := "没有旗子"
	if _wind != null:
		wind_txt = "旗子收着" if not _wind.visible else "%s，旗子转了 %.0f 度%s" % [_label.text, _flag.rotation_degrees, "、左右翻过来" if _flag.flip_h else ""]
	var night_txt := "没有蜡烛"
	if _night != null:
		night_txt = "蜡还剩 %.0f%%，裁切框高 %.0f 像素，火苗在 (%.0f, %.0f)" % [_frac * 100.0, _clip.size.y, _flame.position.x, _flame.position.y]
	return "风向 %s | %s | 夜巡：%s" % [str(_wind_dir), wind_txt, night_txt]

## 火苗：下头圆、上头尖的一小簇，自己会跳。蜡快烧完的时侯变红、跳得急
class Flame extends Control:
	const W := 22.0
	const H := 30.0
	var low := false
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta * (9.0 if low else 5.0)
		queue_redraw()

	func _draw() -> void:
		# 跳动：高矮和左右都有一点来回，几个快慢不一样的摆动叠在一起，看着才不像钟摆
		var sway: float = sin(_t * 0.7) * 1.6 + sin(_t * 1.9) * 0.7
		var h: float = H * (0.80 + 0.14 * sin(_t * 1.3) + 0.05 * sin(_t * 3.1))
		var cx: float = W / 2.0
		var base: float = H - 2.0
		var core := Color(1.0, 0.62, 0.36, 1.0) if low else Color(1.0, 0.86, 0.52, 1.0)
		var halo := Color(1.0, 0.42, 0.22, 0.20) if low else Color(1.0, 0.72, 0.30, 0.16)
		draw_circle(Vector2(cx, base - 7.0), 13.0 + 1.5 * sin(_t * 2.3), halo)      # 一团暖光
		var body := PackedVector2Array([
			Vector2(cx - 6.5, base), Vector2(cx - 7.0 + sway * 0.3, base - 10.0), Vector2(cx - 3.0 + sway, base - h * 0.72),
			Vector2(cx + sway * 1.4, base - h), Vector2(cx + 3.5 + sway, base - h * 0.70), Vector2(cx + 7.2 + sway * 0.3, base - 10.0),
			Vector2(cx + 6.5, base),
		])
		draw_colored_polygon(body, core)
		# 心里更亮的一小簇
		var inner := PackedVector2Array([
			Vector2(cx - 3.0, base), Vector2(cx - 2.6 + sway * 0.5, base - 5.0), Vector2(cx + sway * 0.6, base - h * 0.45),
			Vector2(cx + 2.8 + sway * 0.5, base - 5.0), Vector2(cx + 3.0, base),
		])
		draw_colored_polygon(inner, Color(1.0, 0.98, 0.90, 0.9))

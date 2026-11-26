class_name RiverLamps extends Control
## 河上的灯：一盏一盏从画面上面（远处）往下面（近处）漂的小图，底下带一团暖光和一道倒影，火苗会晃。
## 用的是游戏里现成的那张涂鸦（开场动画"一灯破夜"里飞进标志的也是它）。
## 大厅的河（lobby_river.gd）和游戏里的背景（stage_backdrop.gd）用的都是这一份。
##
## 这个节点摆在画面左上角，灯在整个画面里漂，漂出下边就没了。外面只管说三件事：
##   set_target(n)                    河上该有几盏：少了会从上游补上来，多了等它们自己漂走
##   prepopulate(n)                   一开始在画面里散着摆几盏（不用等第一批从上游漂过来）
##   avoid(item) / avoid_rect(rect)   河灯别抢它们的风头：漂到菜单、标志、棋盘后面时看不见，过去了再亮回来

const SH_SPRITE := preload("res://shaders/opening_sprite.gdshader")
const SH_GLOW := preload("res://shaders/opening_glow.gdshader")
const SH_MIRROR := preload("res://shaders/lobby_reflection.gdshader")
const FLOW: Texture2D = preload("res://assets/sprites/FlowMap.png")
const TEX_LAMP: Texture2D = preload("res://assets/sprites/upgrades/fish.png")

const SIZE_FAR := 46.0             # 最远的那盏灯有多大（贴图的高，按 720 高的画面算）
const SIZE_NEAR := 112.0           # 最近的那盏
const SPEED_FAR := 16.0            # 每秒往近处漂几个像素（同样按 720 高算）
const SPEED_NEAR := 40.0
const SPAWN_GAP := 0.6             # 从上游补灯，两盏之间至少隔几秒
const LAMP_CENTRE := Vector2(0.49, 0.743)    # 那张涂鸦里图形的中心在贴图的什么地方（图形只占贴图的下半截）

## 一盏河灯
class Lamp:
	var root: Control         # 整盏灯：位置就是灯的中心，左右晃、转都是动它
	var body: TextureRect     # 涂鸦
	var glow: ColorRect       # 暖光
	var mirror: ColorRect     # 水里的倒影
	var depth := 1.0          # 0 远，1 近
	var x := 0.0              # 在河上的横向位置（左右晃是围着它晃）
	var y := 0.0
	var speed := 30.0
	var phase := 0.0
	var born := 0.0
	var glow_strength := 0.5
	var mirror_strength := 0.2
	var height := 60.0        # 贴图的高
	var alpha := 1.0          # 平常有多实（远的淡一点）
	var dim := 1.0            # 让不让：1 不让，越小越淡

var target := 0                      # 河上该有几盏
var _lamps: Array[Lamp] = []
var _avoid: Array[CanvasItem] = []   # 河灯别抢它们的风头：漂到它们后面时淡下去
var _avoid_rect := Rect2()           # 同上，按一块范围说（游戏里是棋盘在画面上的那块）
var _time := 0.0
var _spawned_at := -10.0
var _forced := 0                     # 调试：硬性规定河上有几盏

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_time += delta
	_update_lamps(delta)
	if _lamps.size() < target and _time - _spawned_at > SPAWN_GAP:
		spawn()

func count() -> int:
	return _lamps.size()

## 河上该有几盏
func set_target(n: int) -> void:
	target = maxi(n, 0)

## 一开始在画面里散着摆 n 盏（从上往下 from_y 到 to_y 这一段里）
func prepopulate(n: int, from_y := 0.18, to_y := 0.92) -> void:
	for i in n:
		var l := spawn(randf_range(from_y, to_y) * _screen().y)
		l.born = _time - randf_range(0.0, 20.0)       # 火苗晃的相位各自错开

## 有东西压在河面上（菜单、标志）：河灯漂到它后面的时侯淡下去
func avoid(item: CanvasItem) -> void:
	if item != null and not _avoid.has(item): _avoid.append(item)

## 同上，按一块范围说（画面坐标）
func avoid_rect(rect: Rect2) -> void:
	_avoid_rect = rect

func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size

## 往河里放一盏灯。at_y 大于 0 是摆在画面里的那个高度上（prepopulate 用）；不给就是从画面上面的上游漂进来
func spawn(at_y := -1.0) -> Lamp:
	var screen := _screen()
	var k := screen.y / 720.0                     # 画面比 720 高多少倍，灯、速度都跟着放大
	var l := Lamp.new()
	l.depth = randf_range(0.4, 1.0)
	l.phase = randf() * TAU
	l.born = _time
	l.x = randf_range(0.06, 0.94) * screen.x
	l.y = at_y if at_y >= 0.0 else -screen.y * 0.12
	l.speed = lerpf(SPEED_FAR, SPEED_NEAR, l.depth) * k
	l.height = lerpf(SIZE_FAR, SIZE_NEAR, l.depth) * k
	l.glow_strength = lerpf(0.30, 0.62, l.depth)
	l.mirror_strength = lerpf(0.28, 0.66, l.depth)

	l.root = Control.new()
	l.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.root.size = Vector2.ZERO
	l.root.z_index = int(l.depth * 20.0)          # 远的画在底下，近的画在上面
	l.alpha = lerpf(0.62, 1.0, l.depth)           # 远的淡一点
	l.root.position = Vector2(l.x, l.y)
	add_child(l.root)

	l.glow = _glow(l.height * 4.6, Color(1.0, 0.70, 0.36), l.glow_strength)
	l.glow.position = -l.glow.size / 2.0 + Vector2(0.0, -l.height * 0.06)
	l.root.add_child(l.glow)

	# 倒影：贴着灯的底下往下一道，越往下越淡越散，还会左右摆
	l.mirror = ColorRect.new()
	l.mirror.size = Vector2(l.height * 1.6, l.height * 3.6)
	l.mirror.position = Vector2(-l.mirror.size.x / 2.0, l.height * 0.2)
	l.mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mm := ShaderMaterial.new()
	mm.shader = SH_MIRROR
	mm.set_shader_parameter("color", Color(1.0, 0.60, 0.30))
	mm.set_shader_parameter("strength", l.mirror_strength)
	l.mirror.material = mm
	l.root.add_child(l.mirror)

	l.body = TextureRect.new()
	var body: TextureRect = l.body
	body.texture = TEX_LAMP
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_SCALE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = Vector2(TEX_LAMP.get_width(), TEX_LAMP.get_height()) * (l.height / float(TEX_LAMP.get_height()))
	body.position = -body.size * LAMP_CENTRE        # 让涂鸦里那盏灯的中心落在 (0, 0) 上
	var m := ShaderMaterial.new()
	m.shader = SH_SPRITE
	m.set_shader_parameter("texture_albedo", TEX_LAMP)
	m.set_shader_parameter("texture_flow_map", FLOW)
	m.set_shader_parameter("color", Color(1.0, 0.91, 0.70))
	m.set_shader_parameter("wobble", 2.0)
	m.set_shader_parameter("alpha", l.alpha)
	body.material = m
	l.root.add_child(body)

	_lamps.append(l)
	_spawned_at = _time
	return l

## 一团光（方块的边长是 glow_size）。只加不减，叠在河面上
func _glow(glow_size: float, colour: Color, strength: float) -> ColorRect:
	var g := ColorRect.new()
	g.size = Vector2(glow_size, glow_size)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_GLOW
	m.set_shader_parameter("color", colour)
	m.set_shader_parameter("strength", strength)
	g.material = m
	return g

func _update_lamps(delta: float) -> void:
	var screen := _screen()
	var k := screen.y / 720.0
	for i in range(_lamps.size() - 1, -1, -1):
		var l := _lamps[i]
		l.y += l.speed * delta
		var age := _time - l.born
		# 顺着水往下漂，左右轻轻地晃，自己也微微地转
		l.root.position = Vector2(l.x + sin(age * 0.35 + l.phase) * 9.0 * k, l.y + sin(age * 0.9 + l.phase * 1.7) * 1.5 * k)
		l.root.rotation = sin(age * 0.5 + l.phase) * 0.07
		# 火苗的亮度：一快一慢两种晃叠在一起
		var flicker := 0.86 + 0.10 * sin(age * 6.3 + l.phase) + 0.06 * sin(age * 11.7 + l.phase * 2.3)
		# 从菜单、标志、棋盘后面漂过去的时侯淡下去，过去了再亮回来（不要一下子变，看着像灯被吹暗了）。
		# 淡下去要调着色器里的亮度：这几个着色器都是自己算最终颜色的，节点的 modulate 管不到它们
		l.dim = move_toward(l.dim, _clearance(l), delta * 1.6)
		var how_much := l.alpha * l.dim
		_spset(l.body, "alpha", how_much)
		_spset(l.glow, "strength", l.glow_strength * flicker * how_much)
		_spset(l.mirror, "strength", l.mirror_strength * flicker * flicker * how_much)
		if l.y > screen.y + l.height:                # 漂出画面了
			l.root.queue_free()
			_lamps.remove_at(i)

## 这盏灯离菜单、标志这些地方有多“让”：漂到它们后面就看不见了（0），离开一盏灯远近以后完全亮回来（1）。
## 留 20% 的时侯它是个发暗的橄榄色团，比看不见还难看；游戏里它还会压在棋盘的格子上
func _clearance(l: Lamp) -> float:
	var best := 1.0
	for item in _avoid:
		if not is_instance_valid(item) or not item.is_visible_in_tree(): continue
		best = minf(best, _clearance_in(l, (item as Control).get_global_rect()))
	if _avoid_rect.size.x > 0.0 and _avoid_rect.size.y > 0.0:
		best = minf(best, _clearance_in(l, _avoid_rect))
	return best

func _clearance_in(l: Lamp, box: Rect2) -> float:
	box = box.grow(l.height * 0.15)
	var q := l.root.global_position.clamp(box.position, box.end)        # 那块范围里离这盏灯最近的那个点
	return clampf(q.distance_to(l.root.global_position) / (l.height * 1.3), 0.0, 1.0)

func _spset(node: CanvasItem, param: String, value) -> void:
	(node.material as ShaderMaterial).set_shader_parameter(param, value)

# ================================================================ 给调试遥控用（PadAdapter.debug_lobby / debug_stage）

## 硬性规定河上有几盏灯（马上就补齐）；给 0 回到由外面说了算
func debug_lamps(n: int) -> void:
	_forced = maxi(n, 0)
	if _forced > 0:
		target = _forced
		for i in range(_lamps.size(), _forced):
			spawn(randf_range(0.12, 0.9) * _screen().y)

func debug_forced() -> int:
	return _forced

## 排查用：每盏灯在哪、有多淡、离菜单和标志多远
func debug_detail() -> String:
	var out := ""
	for l in _lamps:
		out += "[%d,%d 高%.0f 淡%.2f 让%.2f 身%.2f 光%.2f]" % [int(l.root.global_position.x), int(l.root.global_position.y), l.height, l.dim, _clearance(l), (l.body.material as ShaderMaterial).get_shader_parameter("alpha"), (l.glow.material as ShaderMaterial).get_shader_parameter("strength")]
	for item in _avoid:
		if is_instance_valid(item): out += " 避让:%s=%s" % [item.name, (item as Control).get_global_rect()]
	if _avoid_rect.size.x > 0.0: out += " 避让范围:" + str(_avoid_rect)
	return out

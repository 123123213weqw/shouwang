class_name LobbyRiver extends Control
## 标题页的背景：一条夜里的河。
## 水面（水纹、月影和月光、涟漪）在着色器里算，见 shaders/lobby_river.gdshader。
## 河上的灯是 river_lamps.gd 那一份（游戏里的背景也用它）：从远处（画面上面）往近处漂，底下一团暖光、一道倒影。
##
## 和玩家的互动：
##   鼠标、手指划过水面：划过的地方起涟漪，附近的水纹亮一点（像提着灯照在河面上）
##   菜单的焦点挪到哪个按钮上，那个按钮底下就荡开一圈；点一下是一圈大的
##   没人动的时候，河上的灯过一阵多一盏（最多 LAMPS_MAX 盏）；一动就回到 LAMPS_IDLE 盏上下
##
## 这个节点自己把水面和河灯建出来（场景里只有一个挂着这个脚本的空节点，铺满整个画面）。
## 标题页只在 scripts/uis/title_control.gd 里跟它说两句话：菜单在哪（follow_menu）、标题页露出来了（wake）

const SH_WATER := preload("res://shaders/lobby_river.gdshader")

const LAMPS_IDLE := 6              # 刚回到标题页（或者刚动过）的时候河上有几盏
const LAMPS_MAX := 14              # 最多几盏
const LAMP_EVERY := 8.0            # 没人动的时候，每隔几秒多一盏
const RIPPLES := 6                 # 同时能荡几圈涟漪（和着色器里的 ripple0 到 ripple5 对应）
const RIPPLE_LIFE := 1.6           # 一圈荡多久

var _water: ColorRect
var _lamps: RiverLamps

var _time := 0.0
var _idle := 0.0                     # 有多久没人动了
var _forced := 0                     # 调试：硬性规定河上有几盏（0 是平时那样，看等了多久）

var _ripple_at: Array[Vector2] = []  # 在画面的什么地方（宽、高各是几分之几）
var _ripple_age: Array[float] = []   # 已经荡了多久
var _ripple_amp: Array[float] = []
var _ripple_next := 0                # 下一圈写在哪个槽里（几个槽轮着用）

var _pointer := Vector2.ZERO
var _pointer_age := 99.0
var _pointer_strength := 0.0
var _last_ripple_at := Vector2(-9999.0, -9999.0)
var _last_ripple_time := -10.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water = ColorRect.new()
	_water.name = "Water"
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_WATER
	_water.material = m
	add_child(_water)
	_lamps = RiverLamps.new()
	_lamps.name = "Lamps"
	add_child(_lamps)
	_ripple_at.resize(RIPPLES)
	_ripple_age.resize(RIPPLES)
	_ripple_amp.resize(RIPPLES)
	for i in RIPPLES:
		_ripple_age[i] = RIPPLE_LIFE + 1.0            # 一开始一圈都没有
	resized.connect(_fit)
	_fit()
	# 河上先摆几盏（散在画面里），标题页一露出来河上就已经有灯了，不用等第一批从上游漂过来
	_lamps.prepopulate(LAMPS_IDLE + 1)
	_fit.call_deferred()                                # 这个节点自己的大小要等 _ready() 过完才定下来

## 画面的大小变了（换分辨率、换比例）：告诉着色器画面多宽多高，它算线的粗细和涟漪的圆不圆要用
func _fit() -> void:
	if _water == null or _water.material == null: return
	_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := _water.material as ShaderMaterial
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	mat.set_shader_parameter("view_h", size.y)

func _process(delta: float) -> void:
	_time += delta
	_idle += delta
	_update_ripples(delta)
	_update_pointer(delta)
	# 河上该有几盏（少了 RiverLamps 自己会从上游补）
	_lamps.set_target(_forced if _forced > 0 else mini(LAMPS_MAX, LAMPS_IDLE + int(_idle / LAMP_EVERY)))

# ================================================================ 水面

## 画面上的某一点（屏幕坐标）换算成"宽、高各是几分之几"
func _uv(at: Vector2) -> Vector2:
	return (get_global_transform().affine_inverse() * at) / size

## 在画面上的某一点荡开一圈。amp 是力度：0 到 1
func ripple(at: Vector2, amp := 1.0) -> void:
	var i := _ripple_next
	_ripple_next = (_ripple_next + 1) % RIPPLES
	_ripple_at[i] = _uv(at)
	_ripple_age[i] = 0.0
	_ripple_amp[i] = clampf(amp, 0.0, 1.0)

func _update_ripples(delta: float) -> void:
	var mat := _water.material as ShaderMaterial
	for i in RIPPLES:
		if _ripple_age[i] > RIPPLE_LIFE: continue     # 已经荡完了的那一圈不用再管（着色器里它已经是透明的）
		_ripple_age[i] += delta
		mat.set_shader_parameter("ripple%d" % i, Vector4(_ripple_at[i].x, _ripple_at[i].y, _ripple_age[i], _ripple_amp[i]))

func _update_pointer(delta: float) -> void:
	_pointer_age += delta
	# 指针停下两秒以后，照在河面上的那点光慢慢收掉
	var want := 1.0 if _pointer_age < 2.0 else 0.0
	if is_equal_approx(_pointer_strength, want): return
	_pointer_strength = move_toward(_pointer_strength, want, delta / 0.7)
	var mat := _water.material as ShaderMaterial
	mat.set_shader_parameter("pointer", _pointer if _pointer_strength > 0.0 else Vector2(-1.0, -1.0))
	mat.set_shader_parameter("pointer_strength", _pointer_strength)

# ================================================================ 互动

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_to((event as InputEventMouseMotion).position)
	elif event is InputEventScreenDrag:
		_pointer_to((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton and event.is_pressed():
		var b := event as InputEventMouseButton
		_pointer_to(b.position)
		ripple(b.position, 0.9)
	elif event is InputEventScreenTouch and event.is_pressed():
		var s := event as InputEventScreenTouch
		_pointer_to(s.position)
		ripple(s.position, 0.9)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# 摇杆、按键：只是说明有人在，河上的灯不用再往多了长
		if event.is_pressed() or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
			_idle = 0.0

## 指针挪到了 pos（屏幕坐标）：附近的水纹亮起来；挪够一小段，或者隔了一小会儿，就起一圈小的
func _pointer_to(pos: Vector2) -> void:
	_pointer = _uv(pos)
	_pointer_age = 0.0
	_idle = 0.0
	if pos.distance_to(_last_ripple_at) > size.y * 0.055 or _time - _last_ripple_time > 0.26:
		ripple(pos, 0.22)
		_last_ripple_at = pos
		_last_ripple_time = _time

## 有东西压在河面上（菜单、标志）：河灯漂到它后面的时侯淡下去
func avoid(item: CanvasItem) -> void:
	_lamps.avoid(item)

## 菜单在 menu 底下：哪个按钮得了焦点，它底下就荡开一圈；鼠标悬上去也有一圈小的。
## 以后才加进来的按钮（"方案"那个是标题页 _ready() 里才建的）也算
func follow_menu(menu: Node) -> void:
	avoid(menu as CanvasItem)
	for b in menu.find_children("*", "BaseButton", true, false):
		_watch(b)
	menu.child_entered_tree.connect(func(n: Node) -> void:
		if n is BaseButton:
			_watch(n)
	)

func _watch(b: BaseButton) -> void:
	b.focus_entered.connect(func() -> void: ripple(b.get_global_rect().get_center(), 0.55))
	b.mouse_entered.connect(func() -> void: ripple(b.get_global_rect().get_center(), 0.3))

## 标题页露出来了（开场动画收完）：从 at 荡开一圈大的，像那盏灯刚落回河里
func wake(at: Vector2) -> void:
	ripple(at, 1.0)

# ================================================================ 给调试遥控用（PadAdapter.debug_lobby）

## 在画面上的某一点（屏幕坐标）荡开一圈
func debug_ripple(at: Vector2, amp: float) -> void:
	ripple(at, amp)

## 排查用：每一盏河灯在哪、有多淡、在避让什么
func debug_lamps_detail() -> String:
	return _lamps.debug_detail()

## 硬性规定河上有几盏灯（马上就补齐）；给 0 回到平时那样
func debug_lamps(n: int) -> void:
	_forced = maxi(n, 0)
	if _forced <= 0: _idle = 0.0
	else: _lamps.debug_lamps(_forced)

func debug_state() -> String:
	var young := 0
	for a in _ripple_age:
		if a <= RIPPLE_LIFE: young += 1
	var target := _forced if _forced > 0 else mini(LAMPS_MAX, LAMPS_IDLE + int(_idle / LAMP_EVERY))
	return "河：画面 %d×%d，灯 %d 盏（该有 %d 盏，等了 %.0f 秒），正荡着的涟漪 %d 圈，指针 %.2f,%0.2f 强度 %.2f" % [
		int(size.x), int(size.y), _lamps.count(), target, _idle, young, _pointer.x, _pointer.y, _pointer_strength]

class_name StageBackdrop extends CanvasLayer
## 游戏里的背景：棋盘底下那条河（水面）、河上的灯、远岸的天空，和它跟玩家的互动。
## 大厅的标题页是同一条河（lobby_river.gd），两边是同一种画法：暗底、细水纹、暖色的河灯。
##
## 三种布局（光从哪来、装饰放在哪）。平时用「月下」；环境变量 SW_STAGE 临时换（1 长河、2 远岸、3 月下，
## 给 0 是原来那块铺满网纹的水，什么都不动），录预览、对比的时候用：
##   1 长河   整个画面都是水；月影在左边一侧的河面上，月光贴着那一侧往近处流；河灯从远处漂过来
##   2 远岸   水到远处就到头了，顶上让出一条天空：一轮月亮、三层远山、山脚下的雾
##   3 月下   棋盘底下一汪月光（很大、很淡的一轮月影压在棋盘下面）；水纹在那一汪里让开，边上才亮
## 和玩家的互动：主角落到哪个格子，哪个格子底下就荡开一圈涟漪。
##
## 这个节点挂在 main.tscn 里、界面那一层的前面。它只读游戏里的四样东西（水面、主角、棋盘、镜头），玩法不依赖它：
## 把这个节点从场景里拿掉，游戏照常能玩，只是背景变回原来那样

const SH_WATER := preload("res://shaders/stage_water.gdshader")
const SH_SKY := preload("res://shaders/stage_sky.gdshader")
const SH_RING := preload("res://shaders/opening_disc.gdshader")     # 圆环（开场动画的涟漪用的也是它）

const RIPPLES := 6                 # 同时能荡几圈涟漪（和着色器里的 ripple0 到 ripple5 对应）
const RIPPLE_LIFE := 1.6           # 一圈荡多久
const LAMPS := 7                   # 河上几盏灯
const SHORE_GAP := 8.0             # 远岸：水从棋盘最远那一行再往外伸这么远才到头（一格是 1.3）
const MOON_AT := Vector2(0.13, 0.57)   # 长河：月影在画面的什么地方（宽、高各是几分之几）。左侧空着的那一带
const RING_SQUASH := 0.72              # 落地的那圈环：俯着看，地上的圆在画面上是扁的

@onready var _main: Main = get_parent() as Main
@onready var _water: MeshInstance3D = $"../Water"
@onready var _character: Character = $"../Character"

var _layout := 0
var _lamps: RiverLamps
var _sky: ColorRect                 # 远岸的天空（在另一个 CanvasLayer 上，画在三维的后面）
var _far_z := -11.5                 # 远岸：水到哪儿到头（世界的 z）
var _fitted_at := -10.0             # 上一次量棋盘是什么时候
var _tile_px := 80.0                 # 一格在画面上有多宽（像素）
var _last_ring: ColorRect             # 最近荡开的那圈环（排查用：看它画在哪、多大）

var _ripple_at: Array[Vector2] = [] # 在河面的什么地方（世界的 x、z）
var _ripple_age: Array[float] = []  # 已经荡了多久
var _ripple_amp: Array[float] = []
var _ripple_next := 0               # 下一圈写在哪个槽里（几个槽轮着用）

func _ready() -> void:
	_layout = _layout_from_env()
	if _layout <= 0:
		set_process(false)
		return
	layer = 1
	_ripple_at.resize(RIPPLES)
	_ripple_age.resize(RIPPLES)
	_ripple_amp.resize(RIPPLES)
	for i in RIPPLES:
		_ripple_age[i] = RIPPLE_LIFE + 1.0            # 一开始一圈都没有
	var m := ShaderMaterial.new()
	m.shader = SH_WATER
	m.set_shader_parameter("layout", _layout)
	# 原来那块水面是 400×400 个小格的（给波浪用）。这里的水是平的，一大块就够
	var plane := PlaneMesh.new()
	plane.size = Vector2(100.0, 100.0)
	_water.mesh = plane
	_water.material_override = m          # 三个颜色的参数名字没换，colors.gd 照旧按章节、连击的颜色改它们
	_character.moved.connect(_landed)
	_lamps = RiverLamps.new()
	_lamps.name = "Lamps"
	add_child(_lamps)
	_lamps.prepopulate(LAMPS)
	_lamps.set_target(LAMPS)
	# 界面上的几块（关卡名、灯火、连击、底下的道具框）：河灯别漂到它们前面
	for hud in [_main.level_label, _main.score_label, _main.combo_control, _main.active_control]:
		_lamps.avoid(hud)
	if _layout == 2:
		var behind := CanvasLayer.new()
		behind.layer = -1                  # 编号是负数的那几层画在三维场景的后面
		add_child(behind)
		_sky = ColorRect.new()
		_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = SH_SKY
		_sky.material = sm
		behind.add_child(_sky)

const DEFAULT_LAYOUT := 3              # 月下

func _layout_from_env() -> int:
	var s := OS.get_environment("SW_STAGE")
	return int(s) if s.is_valid_int() else DEFAULT_LAYOUT

func _process(delta: float) -> void:
	_update_ripples(delta)
	_fit_board(delta)
	_fit_sky()
	if _layout == 1: _fit_moon()

## 主角落地了：它落的那个格子底下荡开一圈。
## 水面上那一圈落在棋盘中间时会被四周的格子挡住，所以再在格子面上补一圈淡的环（画在最上层），站在哪儿都看得见
func _landed() -> void:
	var tile := _character.target_tile
	if tile == null: return
	ripple(Vector2(tile.global_position.x, tile.global_position.z), 1.0)
	_ring(_main.camera_3d.unproject_position(tile.global_position))

## 落地的那圈环：从格子那么大荡到快两圈那么大，同时淡下去
func _ring(at: Vector2) -> void:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := _tile_px * 3.6
	r.size = Vector2(side, side)
	r.position = at - Vector2(side * 0.5, side * 0.5 * RING_SQUASH)
	r.scale = Vector2(1.0, RING_SQUASH)
	var m := ShaderMaterial.new()
	m.shader = SH_RING
	m.set_shader_parameter("color", Color(0.86, 0.94, 0.90))
	m.set_shader_parameter("radius", 0.0)
	m.set_shader_parameter("width", 0.05)       # 环有多粗（0 到 1 是从中心到方块的边）
	m.set_shader_parameter("strength", 0.0)
	r.material = m
	add_child(r)
	_last_ring = r
	var t := create_tween()
	t.tween_property(r, "material:shader_parameter/strength", 0.45, 0.05)
	t.tween_property(r, "material:shader_parameter/radius", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(r, "material:shader_parameter/strength", 0.0, 0.6)
	t.tween_callback(r.queue_free)

## 在河面上的某一点（世界的 x、z）荡开一圈。amp 是力度：0 到 1
func ripple(xz: Vector2, amp := 1.0) -> void:
	var i := _ripple_next
	_ripple_next = (_ripple_next + 1) % RIPPLES
	_ripple_at[i] = xz
	_ripple_age[i] = 0.0
	_ripple_amp[i] = clampf(amp, 0.0, 1.0)

func _update_ripples(delta: float) -> void:
	var mat := _water.material_override as ShaderMaterial
	for i in _ripple_age.size():
		if _ripple_age[i] > RIPPLE_LIFE: continue     # 已经荡完了的那一圈不用再管（着色器里它已经是透明的）
		_ripple_age[i] += delta
		mat.set_shader_parameter("ripple%d" % i, Vector4(_ripple_at[i].x, _ripple_at[i].y, _ripple_age[i], _ripple_amp[i]))

## 量棋盘：它在河面上占多大一块（月下的那一汪月光、远岸的水到哪儿到头都按它算），在画面上占哪一块（河灯别漂到它前面）。
## 镜头会跟着主角左右走，所以画面上的那一块要常常量；换了关棋盘变了，也跟着变
func _fit_board(delta: float) -> void:
	_fitted_at += delta
	if _fitted_at < 0.2: return
	_fitted_at = 0.0
	var tiles := _main.grid.tiles.values()
	if tiles.is_empty(): return
	var half: float = _main.grid.tile_size.x * 0.5
	var lo := Vector3(1e9, 0.0, 1e9)
	var hi := Vector3(-1e9, 0.0, -1e9)
	var lo_s := Vector2(1e9, 1e9)
	var hi_s := Vector2(-1e9, -1e9)
	var cam := _main.camera_3d
	for tile in tiles:
		var p: Vector3 = tile.global_position
		lo = Vector3(minf(lo.x, p.x), 0.0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0.0, maxf(hi.z, p.z))
		for corner in [Vector3(-half, 0.3, -half), Vector3(half, 0.3, -half), Vector3(-half, 0.3, half), Vector3(half, 0.3, half)]:
			var q: Vector2 = cam.unproject_position(p + corner)
			lo_s = Vector2(minf(lo_s.x, q.x), minf(lo_s.y, q.y))
			hi_s = Vector2(maxf(hi_s.x, q.x), maxf(hi_s.y, q.y))
	_lamps.avoid_rect(Rect2(lo_s, hi_s - lo_s))
	var first: Vector3 = (tiles[0] as Node3D).global_position
	_tile_px = cam.unproject_position(first + Vector3(_main.grid.tile_size.x, 0.0, 0.0)).distance_to(cam.unproject_position(first))
	var mat := _water.material_override as ShaderMaterial
	var centre := Vector2(lo.x + hi.x, lo.z + hi.z) * 0.5
	var extent := Vector2(hi.x - lo.x, hi.z - lo.z) * 0.5 + Vector2.ONE * half
	mat.set_shader_parameter("pool_xz", centre)
	mat.set_shader_parameter("pool_size", extent + Vector2(3.2, 2.4))
	_far_z = lo.z - half - SHORE_GAP
	mat.set_shader_parameter("far_z", _far_z)

## 长河：月影钉在画面左侧的空处，所以镜头远近、左右怎么动，它都得换个世界里的位置。
## 从画面上那个点顺着镜头的视线打下去，落在水面的地方就是月影的位置
func _fit_moon() -> void:
	var cam := _main.camera_3d
	var view := cam.get_viewport().get_visible_rect().size
	var at := Vector2(view.x * MOON_AT.x, view.y * MOON_AT.y)
	var origin := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	if absf(dir.y) < 0.01: return
	var k := (_water.global_position.y - origin.y) / dir.y
	(_water.material_override as ShaderMaterial).set_shader_parameter("moon_xz", Vector2(origin.x + dir.x * k, origin.z + dir.z * k))

## 远岸：水到头的那条线在画面上多高，这一条天空就多高（镜头远近会变，所以每一帧都要对）
func _fit_sky() -> void:
	if _sky == null: return
	var view := _sky.get_viewport().get_visible_rect().size
	var cam := _main.camera_3d
	var horizon := cam.unproject_position(Vector3(cam.global_position.x, _water.global_position.y, _far_z)).y
	horizon = clampf(horizon, 0.0, view.y)
	if absf(horizon - _sky.size.y) < 0.5: return
	_sky.size = Vector2(view.x, horizon)
	(_sky.material as ShaderMaterial).set_shader_parameter("aspect", view.x / maxf(horizon, 1.0))

# ================================================================ 给调试遥控用（PadAdapter.debug_stage）

## 在主角站的那个格子底下荡开一圈
func debug_ripple() -> void:
	_landed()

func debug_state() -> String:
	var young := 0
	for a in _ripple_age:
		if a <= RIPPLE_LIFE: young += 1
	var sky := 0.0 if _sky == null else _sky.size.y
	var ring := "（还没荡过）"
	if is_instance_valid(_last_ring):
		var rm := _last_ring.material as ShaderMaterial
		ring = "在 %s、大小 %s、缩放 %s；半径 %.2f 强度 %.2f；一格 %.0f 像素" % [_last_ring.global_position, _last_ring.size, _last_ring.scale, rm.get_shader_parameter("radius"), rm.get_shader_parameter("strength"), _tile_px]
	return "布局 %d：水到 z=%.1f 到头，天空高 %.0f 像素，河灯 %d 盏，正荡着的涟漪 %d 圈；最近那圈环%s" % [
		_layout, _far_z, sky, 0 if _lamps == null else _lamps.count(), young, ring]

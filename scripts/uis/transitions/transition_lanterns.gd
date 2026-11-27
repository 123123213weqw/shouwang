extends TransitionStyle
## 「河灯涌来」（docs/transitions.md 五种样式里的第二种）。
## 盖住：画面上方外面有个消失点，一大片河灯从那儿涌出来——光团从消失点涨开、越涌越近越密，淹到四角，整屏盖严。
## 掀开：从主角落脚的地方让开一个洞，洞边的灯被推着往四周散，新的关卡从灯底下露出来。
##
## 两层东西，都在 build() 里建一次、每趟过渡反复用：
##   光海  shaders/transition_lanterns.gdshader，铺满画面的一个节点。夜色的底、远处密密麻麻的光点、近处那些灯的烛光，
##         都在这一个着色器里算。近处只放几十盏真的灯，密度靠光海撑，帧时间才压得住；"盖严"也归它管
##   灯河  River（下面的内部类）：最多 River.LAMPS 盏真的灯，照着 river_lamps.gd 的样子搭（涂鸦的小图、水里的倒影；
##         光晕交给光海画）。那一份是按标题页那条河的慢速度漂的，这边的灯要在一秒里从远处涌到眼前，所以自己驱动
## 光海里的光点和灯河里的灯用的是同一个"缩放场"（见 River 顶上的说明）、同一条 flow：远处的光点涌到近处、大到看得清了，
## 中间就有真的灯接上，看不出是两样东西

const INK := Color(0.016, 0.022, 0.028)   # 夜里河水的墨色：关卡的底色往它里面压
const COVER_S := 0.56          # 平时的局盖住多久
const COVER_FAST_S := 0.27     # 换关换得快的局（长夜、轮战）
const REVEAL_S := 0.72         # 掀开多久
const REVEAL_FAST_S := 0.30
const COVER_EASE := 1.5        # 盖住的前锋按时间的几次方涨：1 是匀速，比 1 大是开头慢、后头急（涌过来的那一下）
const STREAM_S := 6.0          # 水流多快（u 每秒涨多少）：盖住的时候、盖严了以后都是它
const OUT_S := 8.0             # 掀开的时侯流得更急：灯涌出画面

const FRONT_REST := -0.12      # 还没开始：灯河的前锋在消失点后面这么多，画面上一点光也不显（着色器和灯河都用它）

var _sea: TextureRect
var _mat: ShaderMaterial
var _river: River

var _night_from := INK
var _night_to := INK
var _front_far := 2.0          # 前锋到这儿才算盖严：从消失点到最远的一角，再加上柔边
var _hole := Vector2(0.8, 0.55)   # 掀开的洞从哪儿开（等比坐标）
var _hole_far := 1.0
var _covered := false          # 现在是不是盖严的。开机掀幕没盖过，要直接摆成盖严的样子再掀

func build() -> void:
	_sea = full_rect(shader("lanterns"))
	_mat = _sea.material as ShaderMaterial
	add(_sea, true)             # 着色器头一回画要编译，趁着开机的黑幕先花掉
	_sea.visible = false        # 预热是外面帮着做的；平时藏着，盖的时侯自己设回可见
	_river = River.new()
	_river.name = "Lamps"
	add(_river)
	_river.build(_mat)

func cover(ctx: Dictionary) -> void:
	_fit()
	_night_from = _night(ctx.get("color_from"))
	_night_to = _night(ctx.get("color"))
	_mat.set_shader_parameter("night_from", _night_from)
	_mat.set_shader_parameter("night_to", _night_to)
	_mat.set_shader_parameter("hole_r", 0.0)
	_sea.visible = true
	_covered = false
	_river.speed = STREAM_S
	_river.begin(false)
	await _run(duration(ctx, COVER_S, COVER_FAST_S), _covering)
	_covered = true

func reveal(ctx: Dictionary) -> void:
	_fit()
	_sea.visible = true
	if not _covered:
		# 没盖过就掀（开机掀幕）：先摆成盖严的样子。标题页是从一整条灯河里露出来的
		_night_from = _night(ctx.get("color_from"))
		_night_to = _night(ctx.get("color"))
		_mat.set_shader_parameter("night_from", _night_from)
		_mat.set_shader_parameter("night_to", _night_to)
		_river.speed = STREAM_S
		_river.begin(true)
		_covering(1.0)
	# 前锋已经在画面外面了，盖严靠它；把"整张盖实"那道保险撤掉，洞才开得了
	_mat.set_shader_parameter("cover", 0.0)
	_night_to = _night(ctx.get("color"))
	_mat.set_shader_parameter("night_to", _night_to)
	var uv := screen_uv(ctx.get("to"), Vector2(0.5, 0.52))
	# 别太靠边：洞从这儿往四周开，贴着边的话有一侧要开很久
	uv = uv.clamp(Vector2(0.22, 0.28), Vector2(0.78, 0.8))
	var aspect := _aspect()
	_hole = Vector2(uv.x * aspect, uv.y)
	_hole_far = _far_corner(_hole, aspect)
	_mat.set_shader_parameter("hole_at", _hole)
	_mat.set_shader_parameter("hole_far", _hole_far)
	_river.speed = OUT_S
	_river.open(_hole, _hole_far)
	await _run(duration(ctx, REVEAL_S, REVEAL_FAST_S), _revealing)
	_finish()

## 盖住进行到几分之几（0 到 1）：前锋从消失点后面涨到最远的一角外头；柔边越近越宽（近处的灯大，边也该粗）；
## 夜色在半路上从离开的那一关换成要去的那一关；最后一成多的时间把整张压实
func _covering(k: float) -> void:
	var e := pow(k, COVER_EASE)
	var front := lerpf(FRONT_REST, _front_far, e)
	var soft := lerpf(0.07, 0.34, e)
	_mat.set_shader_parameter("front", front)
	_mat.set_shader_parameter("front_soft", soft)
	_mat.set_shader_parameter("night_mix", smoothstep(0.25, 1.0, k))
	_mat.set_shader_parameter("cover", smoothstep(0.8, 1.0, k))
	_river.front = front
	_river.front_soft = soft

## 掀开进行到几分之几：洞从落脚的地方开到最远的一角外头，边越开越柔
func _revealing(k: float) -> void:
	var e := smoothstep(0.0, 1.0, k)
	var r := e * 1.6
	_mat.set_shader_parameter("hole_r", r)
	_mat.set_shader_parameter("hole_soft", lerpf(0.05, 0.30, e))
	_river.hole_r = r

## 掀开做完：什么都归零。着色器整张透明，灯收起来，光海藏起来（ctl 那一层也会跟着藏）
func _finish() -> void:
	_mat.set_shader_parameter("cover", 0.0)
	_mat.set_shader_parameter("front", FRONT_REST)
	_mat.set_shader_parameter("hole_r", 0.0)
	_sea.visible = false
	_river.stop()

## 一段动画跑 seconds 秒，每帧把进行到几分之几告诉 tick。做完才返回
func _run(seconds: float, tick: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	while true:
		var k := clampf(float(Time.get_ticks_usec() - t0) / (1000000.0 * seconds), 0.0, 1.0)
		tick.call(k)
		if k >= 1.0:
			break
		await ctl.get_tree().process_frame

## 画面有多大、多宽；从消失点到最远的一角有多远（前锋得到那儿外头才算盖严）
func _fit() -> void:
	var size := ctl.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	_mat.set_shader_parameter("aspect", aspect)
	_mat.set_shader_parameter("view_h", size.y)
	_front_far = _far_corner(Vector2(River.VP_X * aspect, River.VP_Y), aspect) + 0.34 + 0.30
	_river.fit(aspect, size.y)

func _aspect() -> float:
	var size := ctl.get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)

## 从 at 到画面四个角最远有多远（等比坐标：画面的高是 1）
static func _far_corner(at: Vector2, aspect: float) -> float:
	var far := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(aspect, 0.0), Vector2(0.0, 1.0), Vector2(aspect, 1.0)]:
		far = maxf(far, corner.distance_to(at))
	return far

## 关卡的底色 → 夜色：压暗，再往墨色里掺一半。石绿的关卡是墨绿，朱砂的关卡是暗赭，看得出是哪一关的夜
static func _night(base: Color) -> Color:
	return (base * 0.17).lerp(INK, 0.5)


## 河面上的灯（换关这一下用的一份，照 river_lamps.gd 抄的：那边是标题页的慢河，这边的灯要在一秒里涌到眼前）。
##
## 河面不是真的三维投影，是个"缩放场"：画面上方外面有个消失点，河上的每一点由两个数定——
##   dy     离消失点多高（画面高的几分之几）。这一点画在 消失点 + (斜率 × dy, dy)，灯的大小和 dy 成正比
##   u      log(dy)。灯顺流而下就是 u 随时间匀速地涨（flow）：远处的看着慢慢挪，近处的越涌越快（指数的），"涌来"打这儿来
## 光海（transition_lanterns.gdshader 的 dots）里的光点画在 (斜率, u) 平面的方格子上，用的是同一个消失点和同一条 flow。
##
## 每盏灯的小图和倒影是现成的节点；光晕不是——每帧写进光海的两个数组里，由它一起画
class River extends Control:
	const SH_SPRITE := preload("res://shaders/opening_sprite.gdshader")
	const SH_MIRROR := preload("res://shaders/lobby_reflection.gdshader")
	const FLOW: Texture2D = preload("res://assets/sprites/FlowMap.png")
	const TEX_LAMP: Texture2D = preload("res://assets/sprites/upgrades/fish.png")
	const LAMP_CENTRE := Vector2(0.49, 0.743)    # 那张涂鸦里图形的中心在贴图的什么地方（图形只占贴图的下半截）

	const LAMPS := 36              # 最多几盏灯。节点建一次，轮着用
	const PRIME := 30              # 开机掀幕的时侯河上先摆几盏（那会儿河上已经满是灯了）
	const FRONT_REST := -0.12      # 还没开始：灯河的前锋在消失点后面这么多，画面上一点光也不显
	const VP_X := 0.5              # 消失点横着在画面的正中
	const VP_Y := -0.08            # 竖着在画面上方外面这么多（画面高的几分之几）
	const U_IN := -3.2             # 灯出生在 u 是多少的地方（dy ≈ 0.04：画面顶的外面）
	const DY_GONE := 1.7           # 涌过这么远就算出了画面，收回来再用
	const SPAWN_DU := 0.14         # 水每流这么远（u）来一盏灯
	const LAMP_PX := 100.0         # dy 是 1 的那盏灯，贴图有多高（按 720 高的画面算）
	const Z_TOP := 30              # 最近的灯 z_index 有多大：近的压着远的
	const PUSH := 2.2              # 掀开的时侯，洞边的灯被推开多快（画面高 / 秒）

	## 一盏灯
	class Lamp:
		var root: Control         # 整盏灯：位置就是灯的中心。左右晃、转、放大缩小都是动它
		var body: TextureRect     # 涂鸦
		var mirror: ColorRect     # 水里的倒影
		var mat_body: ShaderMaterial
		var mat_mirror: ShaderMaterial
		var live := false         # 在不在河上
		var u0 := 0.0             # 出生那一刻的 u（加上以后的 flow 就是现在的）
		var slope := 0.0          # 在哪一条从消失点出来的线上：dy 是 1 的时侯离正中多远
		var slant := 1.0          # sqrt(1 + slope²)：离消失点多远 = dy × 它
		var stature := 1.0        # 这盏灯自己的大小（0.8 到 1.2）
		var phase := 0.0          # 火苗晃、左右摆的相位
		var push := Vector2.ZERO  # 掀开的时侯被洞推开了多远（画面上的位移，等比坐标）

	var _sea: ShaderMaterial                 # 光海的材质：灯的光晕写给它
	var _lamps: Array[Lamp] = []
	var _pos := PackedVector2Array()         # 给光海的：每盏看得见的灯在哪儿
	var _lit := PackedVector4Array()         # 给光海的：光晕的半径、亮度
	var _aspect := 1.6
	var _view_h := 720.0
	var _time := 0.0
	var _flow := 0.0                         # 水已经流了多远（u）
	var _next_u := 0.0                       # 水流到这儿来下一盏灯
	var speed := 6.0                         # 这一刻水流多快（u 每秒涨多少）：样式给
	var front := FRONT_REST                  # 盖住：灯河的前锋离消失点多远。它以内的灯才看得见
	var front_soft := 0.07
	var _hole := Vector2.ZERO                # 掀开的洞在哪儿；半径拿 _hole_far 当 1。hole_r 是 0 就是没开
	var _hole_far := 1.0
	var hole_r := 0.0

	func build(sea: ShaderMaterial) -> void:
		_sea = sea
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pos.resize(LAMPS)
		_lit.resize(LAMPS)
		set_process(false)
		for i in LAMPS:
			var l := Lamp.new()
			l.root = Control.new()
			l.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.root.size = Vector2.ZERO
			l.root.visible = false
			add_child(l.root)

			# 倒影：贴着灯的底下往下一道，越往下越淡越散，还会左右摆。先画它，灯身压在上面
			l.mirror = ColorRect.new()
			l.mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.mirror.size = Vector2(LAMP_PX * 1.6, LAMP_PX * 3.6)
			l.mirror.position = Vector2(-LAMP_PX * 0.8, LAMP_PX * 0.2)
			l.mat_mirror = ShaderMaterial.new()
			l.mat_mirror.shader = SH_MIRROR
			l.mat_mirror.set_shader_parameter("color", Color(1.0, 0.60, 0.30))
			l.mirror.material = l.mat_mirror
			l.root.add_child(l.mirror)

			# 灯身：那张涂鸦，和界面上的精灵一样会轻轻地抖（FlowMap）
			l.body = TextureRect.new()
			l.body.texture = TEX_LAMP
			l.body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			l.body.stretch_mode = TextureRect.STRETCH_SCALE
			l.body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.body.size = Vector2(TEX_LAMP.get_width(), TEX_LAMP.get_height()) * (LAMP_PX / float(TEX_LAMP.get_height()))
			l.body.position = -l.body.size * LAMP_CENTRE     # 让涂鸦里那盏灯的中心落在 (0, 0) 上
			l.mat_body = ShaderMaterial.new()
			l.mat_body.shader = SH_SPRITE
			l.mat_body.set_shader_parameter("texture_albedo", TEX_LAMP)
			l.mat_body.set_shader_parameter("texture_flow_map", FLOW)
			l.mat_body.set_shader_parameter("color", Color(1.0, 0.91, 0.70))
			l.mat_body.set_shader_parameter("wobble", 2.0)
			l.mat_body.set_shader_parameter("alpha", 0.0)
			l.body.material = l.mat_body
			l.root.add_child(l.body)
			_lamps.append(l)

	func fit(aspect: float, view_h: float) -> void:
		_aspect = aspect
		_view_h = view_h

	## 一趟过渡开始。full = true 是没盖过就要掀（开机掀幕）：河上已经满是灯了，远近先摆上
	func begin(full: bool) -> void:
		_time = 0.0
		_flow = 0.0
		_next_u = 0.0
		front = FRONT_REST
		hole_r = 0.0
		for l in _lamps:
			l.live = false
			l.root.visible = false
		_sea.set_shader_parameter("flow", 0.0)
		if full:
			for i in PRIME:
				var l := _spawn()
				if l == null: break
				l.u0 = randf_range(U_IN, log(DY_GONE * 0.9))
		set_process(true)

	## 掀开的洞从哪儿开（at，等比坐标；far 是到最远一角的距离）
	func open(at: Vector2, far: float) -> void:
		_hole = at
		_hole_far = far
		hole_r = 0.0

	## 过渡做完：灯都收起来，不再跟着水流走
	func stop() -> void:
		set_process(false)
		for l in _lamps:
			l.live = false
			l.root.visible = false
		_sea.set_shader_parameter("lamp_n", 0)

	## 往上游放一盏灯。河上满了（LAMPS 盏都在）就先不放，水再流远一点自然有空出来的
	func _spawn() -> Lamp:
		for l in _lamps:
			if l.live: continue
			l.live = true
			l.u0 = U_IN - _flow           # 出生在上游（画面顶的外面）。记的是出生那一刻的 flow，以后跟着水走
			l.slope = randf_range(-1.05, 1.05)
			l.slant = sqrt(1.0 + l.slope * l.slope)
			l.stature = randf_range(0.8, 1.2)
			l.phase = randf() * TAU
			l.push = Vector2.ZERO
			l.root.visible = false
			return l
		return null

	func _process(delta: float) -> void:
		_time += delta
		_flow += speed * delta
		_sea.set_shader_parameter("flow", _flow)
		# 上游来灯：按水流过的远近算，每流 SPAWN_DU 来一盏——所以水流得再急，河上的疏密也不变。间隔有长有短，
		# 灯是一簇一簇地来的，不是排着队匀速来
		while _flow >= _next_u:
			_spawn()
			_next_u += SPAWN_DU * randf_range(0.45, 1.55)
		var vp := Vector2(VP_X * _aspect, VP_Y)
		var k := _view_h / 720.0
		var n := 0
		for l in _lamps:
			if not l.live: continue
			var dy := exp(l.u0 + _flow)
			if dy > DY_GONE:
				l.live = false
				l.root.visible = false
				continue
			var lamp_h := dy * LAMP_PX * l.stature * k
			if lamp_h < 10.0:
				# 才几个像素：这一段由光海的光点代表它
				if l.root.visible: l.root.visible = false
				continue
			# 左右轻轻地晃（两种快慢叠在一起，近处按比例晃得大一点），自己也微微地转
			var sway := (sin(_time * 0.9 + l.phase) * 0.010 + sin(_time * 0.37 + l.phase * 1.7) * 0.016) * dy
			var at := Vector2(vp.x + (l.slope + sway) * dy, vp.y + dy) + l.push
			# 出了画面的不画。倒影拖在灯底下三倍多长，留够边
			var margin := lamp_h * 3.8 / _view_h + 0.02
			if at.x < -margin or at.x > _aspect + margin or at.y < -margin or at.y > 1.0 + margin:
				if l.root.visible: l.root.visible = false
				continue
			# 灯河的前锋还没到的地方，灯不显：前锋就是最前排的灯
			var seen := 1.0 - smoothstep(front - front_soft * 0.3, front + front_soft * 1.2, dy * l.slant)
			if hole_r > 0.0:
				# 掀开：洞里的灯淡出去，洞边的被推着往四周散
				var hq := at - _hole
				var hd := hq.length() / _hole_far
				seen *= smoothstep(hole_r - 0.02, hole_r + 0.14, hd)
				if hd < hole_r + 0.45:
					l.push += hq.normalized() * (delta * PUSH * (1.0 - smoothstep(hole_r, hole_r + 0.45, hd)))
			if seen <= 0.004:
				if l.root.visible: l.root.visible = false
				continue
			# 火苗的亮度：一快一慢两种晃叠在一起
			var flick := 0.86 + 0.10 * sin(_time * 6.3 + l.phase) + 0.06 * sin(_time * 11.7 + l.phase * 2.3)
			var nearness := smoothstep(0.15, 1.0, dy)             # 0 远，1 近
			l.root.visible = true
			l.root.position = at * _view_h
			l.root.scale = Vector2.ONE * (lamp_h / LAMP_PX)
			l.root.rotation = sin(_time * 0.5 + l.phase) * 0.06
			l.root.z_index = clampi(int(dy * 24.0), 0, Z_TOP)
			# 远处的灯身才几个像素，看不清是什么：小的时候不着痕迹地淡进来
			l.mat_body.set_shader_parameter("alpha", smoothstep(16.0, 40.0, lamp_h) * seen)
			l.mat_mirror.set_shader_parameter("strength", lerpf(0.28, 0.66, nearness) * flick * flick * seen)
			_pos[n] = at
			_lit[n] = Vector4(lamp_h * 2.3 / _view_h, lerpf(0.30, 0.62, nearness) * flick * seen, 0.0, 0.0)
			n += 1
		_sea.set_shader_parameter("lamp_n", n)
		if n > 0:
			_sea.set_shader_parameter("lamp_pos", _pos)
			_sea.set_shader_parameter("lamp_lit", _lit)

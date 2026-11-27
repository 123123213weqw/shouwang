extends TransitionStyle
## 「河灯涌来」（docs/transitions.md 五种样式里的第二种）。
## 盖住：一条漂满河灯的河从上游压过来——最前面一排灯先扫下来，水跟着漫上来，越涌越近、越密，淹到画面底下，整屏盖严。
## 掀开：从主角落脚的地方让开一个洞，洞边的灯被推着往四周散，新的关卡从灯底下露出来。
##
## 两层东西，都在 build() 里建一次、每趟过渡反复用：
##   光海  shaders/transition_lanterns.gdshader，铺满画面的一个节点。夜色的底和水纹、远处密密麻麻的灯、近处那些灯的烛光，
##         都在这一个着色器里算。近处只放几十盏真的灯，密度靠光海撑，帧时间才压得住；"盖严"也归它管
##   灯河  River（下面的内部类）：最多 River.LAMPS 盏真的灯，照着 river_lamps.gd 的样子搭（涂鸦的小图、水里的倒影；
##         光晕交给光海画）。那一份是按标题页那条河的慢速度漂的，这边的灯要在一秒里从远处涌到眼前，所以自己驱动
## 两边用的是同一个消失点（见着色器顶上的说明）：光海里的灯和真的灯在同一个透视里，远近、大小对得上，
## 光海里的灯涌到近处、大到看得清船身了，中间就有真的灯接上。只是真的灯在河面上不匀速流（见 River 顶上的说明）
##
## 两段加起来别超过 1.3 秒（docs/transitions.md 对每种样式的要求）。这里平时是盖住 0.46、掀开 0.56，快局 0.25、0.27

const INK := Color(0.016, 0.022, 0.028)   # 夜里河水的墨色：关卡的底色往它里面压
const COVER_S := 0.46          # 平时的局盖住多久
const COVER_FAST_S := 0.25     # 换关换得快的局（长夜、轮战）
const REVEAL_S := 0.56         # 掀开多久
const REVEAL_FAST_S := 0.27
const COVER_EASE := 1.4        # 盖住的前锋按时间的几次方扫下来：1 是匀速，比 1 大是远处慢、近处急（涌过来的那一下）
const STREAM_S := 1.2          # 水流多快（河面上的距离每秒）：盖住的时候、盖严了以后都是它
const OUT_S := 2.0             # 掀开的时侯流得更急：灯涌出画面
const DIM := 0.6               # 盖住的时侯，还没淹到的旧画面最多先暗下去多少
const BOOT_HOLD := 0.35        # 开机掀幕：先给人看这么久的一整条灯河，再让开（开机的黑幕等掀幕开始了才撤，这一会儿看得见）

var _sea: TextureRect
var _mat: ShaderMaterial
var _river: River

var _night_from := INK
var _night_to := INK
var _front_end := 1.75         # 前锋到这儿才算盖严：画面底再往下一截
var _hole := Vector2(0.8, 0.55)   # 掀开的洞从哪儿开（等比坐标）
var _hole_far := 1.0
var _covered := false          # 现在是不是盖严的。开机掀幕没盖过，要直接摆成盖严的样子再掀

func build() -> void:
	_sea = full_rect(shader("lanterns"))
	_mat = _sea.material as ShaderMaterial
	add(_sea, true)             # 着色器头一回画要编译，白画两帧先花掉（预热是外面帮着做的）。它还没开始的时侯整张透明
	_sea.visible = false        # 平时藏着，盖、掀的时侯自己设回可见
	_river = River.new()
	_river.name = "Lamps"
	# 新手教程弹出卡片的时侯会把场景树暂停。灯河是背景，暂停时也照常流，不然掀开的半路上灯会冻住
	_river.process_mode = Node.PROCESS_MODE_ALWAYS
	# 先加光海、后加灯河：同一层里先加的画在底下，灯才压在光海上头
	add(_river)
	_river.build(_mat)

func cover(ctx: Dictionary) -> void:
	# 测试的时侯（SW_TRANSITION 设了）把这一层下面的节点数打进日志：换多少次关它都不该涨（节点都在 build() 里建了一次）
	if OS.get_environment("SW_TRANSITION") != "":
		print("河灯涌来：过渡这一层下面有 %d 个节点" % _count_nodes(ctl))
	_fit()
	_night_from = _night(ctx.get("color_from"))
	_night_to = _night(ctx.get("color"))
	_mat.set_shader_parameter("night_from", _night_from)
	_mat.set_shader_parameter("night_to", _night_to)
	_mat.set_shader_parameter("hole_r", 0.0)
	_sea.visible = true
	_covered = false
	_river.speed = STREAM_S
	_river.begin()
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
		_river.begin()
		_covering(1.0)
	# 前锋已经在画面外面了，盖严靠它；把"整张盖实"和"先暗下去"那两道撤掉，洞才开得了
	_mat.set_shader_parameter("cover", 0.0)
	_mat.set_shader_parameter("dim", 0.0)
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
	# 开机掀幕：先让人看一眼整条灯河，再让开（别的时侯盖严到掀开之间本来就隔着换棋盘的那一段）
	if str(ctx.get("mode", "level")) == "boot":
		await ctl.get_tree().create_timer(BOOT_HOLD).timeout
	await _run(duration(ctx, REVEAL_S, REVEAL_FAST_S), _revealing)
	_finish()

## 盖住进行到几分之几（0 到 1）：前锋从画面顶的外面扫到画面底的外面；柔边越近越宽（近处的灯大，边也该粗）；
## 夜色在半路上从离开的那一关换成要去的那一关；还没淹到的旧画面一路暗下去；最后两成多的时间把整张压实
func _covering(k: float) -> void:
	var e := pow(k, COVER_EASE)
	var front := lerpf(River.FRONT_REST, _front_end, e)
	var soft := lerpf(0.05, 0.30, e)
	_mat.set_shader_parameter("front", front)
	_mat.set_shader_parameter("front_soft", soft)
	_mat.set_shader_parameter("night_mix", smoothstep(0.2, 0.9, k))
	# 旧画面先沉进夜里：技能图标、连击这些在画面底下和角上，是最后才淹到的，等水漫到它们早就不显了
	_mat.set_shader_parameter("dim", DIM * smoothstep(0.1, 0.8, k))
	_mat.set_shader_parameter("cover", smoothstep(0.76, 1.0, k))
	_river.front = front
	_river.front_soft = soft

## 掀开进行到几分之几：洞从落脚的地方开到最远的一角外头，边越开越柔。
## 过了三成，洞外剩下的灯开始散尽、夜色跟着变薄：远处的小灯挪得慢，等不到它们自己漂走
func _revealing(k: float) -> void:
	var e := smoothstep(0.0, 1.0, k)
	var r := e * 1.6
	_mat.set_shader_parameter("hole_r", r)
	_mat.set_shader_parameter("hole_soft", lerpf(0.05, 0.30, e))
	_mat.set_shader_parameter("ebb", smoothstep(0.3, 0.85, k))
	_river.hole_r = r
	_river.ebb = smoothstep(0.3, 0.8, k)

## 掀开做完：什么都归零。着色器整张透明，灯收起来，光海藏起来（ctl 那一层也会跟着藏）
func _finish() -> void:
	_mat.set_shader_parameter("cover", 0.0)
	_mat.set_shader_parameter("dim", 0.0)
	_mat.set_shader_parameter("front", River.FRONT_REST)
	_mat.set_shader_parameter("hole_r", 0.0)
	_mat.set_shader_parameter("ebb", 0.0)
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

## 画面有多大、多宽；前锋得到画面底外面多远
func _fit() -> void:
	var size := ctl.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	_mat.set_shader_parameter("aspect", aspect)
	_mat.set_shader_parameter("view_h", size.y)
	_front_end = (1.0 - River.VP_Y) + 0.4
	_river.fit(aspect, size.y)

func _aspect() -> float:
	var size := ctl.get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)

## 一个节点连它底下所有的子孙一共几个
static func _count_nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count_nodes(child)
	return n

## 从 at 到画面四个角最远有多远（等比坐标：画面的高是 1）
static func _far_corner(at: Vector2, aspect: float) -> float:
	var far := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(aspect, 0.0), Vector2(0.0, 1.0), Vector2(aspect, 1.0)]:
		far = maxf(far, corner.distance_to(at))
	return far

## 关卡的底色 → 夜色：压暗，再往墨色里掺一半。石绿的关卡是墨绿，朱砂的关卡是暗赭，看得出是哪一关的夜
static func _night(base: Color) -> Color:
	return (base * 0.17).lerp(INK, 0.5)


## 河面上那些真的灯（换关这一下用的一份，照 river_lamps.gd 抄的：那边是标题页的慢河，这边的灯要在一秒里涌到眼前）。
##
## 和光海用的是同一个透视（见 shaders/transition_lanterns.gdshader 顶上的说明）：画面上方外面很远有个消失点，
## 每盏灯记着它这会儿在河面上的位置（x0 横着，z 顺着河），每帧往近处走一点；深度 dy = 1 / z，
## 画在 消失点 + (x0 × dy, dy)，大小和 dy 成正比。所以远处的灯又小又慢，越往近处越大越快，横着也散开。
## 只是这些灯在河面上不是匀速流的（FLOW_EXP）：匀速的话近处那一截在河面上只占很小一段，画面底下平均只轮得到一两盏灯
##
## 每盏灯的小图和倒影是现成的节点；光晕不是——每帧写进光海的两个数组里，由它一起画
class River extends Control:
	const SH_SPRITE := preload("res://shaders/opening_sprite.gdshader")
	const SH_MIRROR := preload("res://shaders/lobby_reflection.gdshader")
	const FLOW: Texture2D = preload("res://assets/sprites/FlowMap.png")
	const TEX_LAMP: Texture2D = preload("res://assets/sprites/upgrades/fish.png")
	const LAMP_CENTRE := Vector2(0.49, 0.743)    # 那张涂鸦里图形的中心在贴图的什么地方（图形只占贴图的下半截）

	const LAMPS := 48              # 最多几盏灯。节点建一次，轮着用（要和着色器里 lamp_pos、lamp_lit 的长度一样）
	const VP_X := 0.5              # 消失点横着在画面的正中
	const VP_Y := -0.35            # 竖着在画面上方外面这么远（画面高的几分之几）。要和着色器里的 VP_Y 一样
	const Z_IN := 5.4              # 灯从多远出生（dy ≈ 0.19：画面顶的外面）
	const Z_OUT := 0.62            # 涌到这么近就算出了画面（dy ≈ 1.6），收回来再用
	const FLOW_EXP := 0.6           # 这些灯在河面上流得多快，和 z 的几次方成正比：离得越远流得越快、换得越勤，近处的留得住。
	                               # 换到画面上还是越近越快（和 dy 的 1.4 次方成正比），只是远近差得没那么狠
	const SPAWN_RATE := 17.4        # 水流速度是 1 的时侯，每秒从上游来几盏灯。从 Z_IN 流到 Z_OUT 一趟，河上正好是 LAMPS 盏上下
	const LAMP_PX := 110.0         # dy 是 1 的那盏灯，贴图有多高（按 720 高的画面算；标题页最近的那盏是 112）
	const Z_TOP := 30              # 最近的灯 z_index 有多大：近的压着远的
	const PUSH := 1.6              # 掀开的时侯，洞边的灯被推开多快（画面高 / 秒）
	const FRONT_REST := 0.2       # 还没开始：灯河的前锋停在这个深度（画面顶还在它前面一点点，一点光也不显；
	                             # 离得近，一开头远处就亮起来，不空半拍）

	## 一盏灯
	class Lamp:
		var root: Control         # 整盏灯：位置就是灯的中心。左右晃、转、放大缩小都是动它
		var body: TextureRect     # 涂鸦
		var mirror: ColorRect     # 水里的倒影
		var mat_body: ShaderMaterial
		var mat_mirror: ShaderMaterial
		var live := false         # 在不在河上
		var z := 0.0              # 这会儿在河面上顺着河多远（越小越近）
		var x0 := 0.0             # 横着离河当中多远（dy 是 1 的时候在画面上离正中多宽）
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
	var _flow := 0.0                         # 水已经流了多远（河面上的距离）：光海里的灯和水纹按它匀速地流
	var _acc := 0.0                          # 上游来灯：攒够 _gap 就来一盏（以"平均隔多久来一盏"为 1）
	var _gap := 1.0                          # 下一盏隔多久来（同上，平均是 1）
	var speed := 1.2                         # 这一刻水流多快：样式给
	var front := FRONT_REST                  # 盖住：灯河的前锋到了哪个深度（dy）。比它远的灯才看得见
	var front_soft := 0.05
	var _hole := Vector2.ZERO                # 掀开的洞在哪儿；半径拿 _hole_far 当 1。hole_r 是 0 就是没开
	var _hole_far := 1.0
	var hole_r := 0.0
	var ebb := 0.0                            # 掀开到后头洞外剩下的灯散尽（0 到 1）

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
			l.mat_mirror.set_shader_parameter("color", Color(1.0, 0.62, 0.30))
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

	## 一趟过渡开始：河上已经满是灯了（近的远的都摆上），只是前锋还没到、看不见
	func begin() -> void:
		_time = 0.0
		_flow = 0.0
		_acc = 0.0
		_gap = 1.0
		front = FRONT_REST
		front_soft = 0.05
		hole_r = 0.0
		# 摆得和水一直这么流着的时候一样多：走得慢的地方（近处）灯就多。
		# 积分一下"每一段河面上停多久"（和 z 的 -FLOW_EXP 次方成正比），反过来取，就是下面这个式子
		var lo := pow(Z_OUT + 0.03, 1.0 - FLOW_EXP)
		var hi := pow(Z_IN, 1.0 - FLOW_EXP)
		for l in _lamps:
			l.live = false
			l.root.visible = false
			_place(l, pow(randf_range(lo, hi), 1.0 / (1.0 - FLOW_EXP)))
		_sea.set_shader_parameter("flow", 0.0)
		set_process(true)

	## 掀开的洞从哪儿开（at，等比坐标；far 是到最远一角的距离）
	func open(at: Vector2, far: float) -> void:
		_hole = at
		_hole_far = far
		hole_r = 0.0
		ebb = 0.0

	## 过渡做完：灯都收起来，不再跟着水流走
	func stop() -> void:
		set_process(false)
		for l in _lamps:
			l.live = false
			l.root.visible = false
		_sea.set_shader_parameter("lamp_n", 0)

	## 往上游放一盏灯。河上满了（LAMPS 盏都在）就先不放，水再流一会儿自然有空出来的
	func _spawn() -> void:
		for l in _lamps:
			if l.live: continue
			_place(l, Z_IN)
			return

	## 把一盏灯放到河面上 z 这儿（顺着河多远）
	func _place(l: Lamp, z: float) -> void:
		l.live = true
		l.z = z
		# 横着：七成挤在河当中那一条（近处画面里看得见的主要是它），三成散到两边（它们只在远处的那一段在画面里）
		var u := randf_range(-1.0, 1.0)
		l.x0 = u * 0.85 if randf() < 0.7 else signf(u) * randf_range(0.85, 2.3)
		l.stature = randf_range(0.8, 1.2)
		l.phase = randf() * TAU
		l.push = Vector2.ZERO
		l.root.visible = false

	func _process(delta: float) -> void:
		_time += delta
		_flow += speed * delta
		_sea.set_shader_parameter("flow", _flow)
		# 上游来灯：按时间算，来得和水流一样快——所以水流得再急，河上的疏密也不变。
		# 两盏之间隔多久有长有短，灯是一簇一簇地来的，不是排着队匀速来
		_acc += SPAWN_RATE * speed * delta
		while _acc >= _gap:
			_acc -= _gap
			_gap = randf_range(0.5, 1.5)
			_spawn()
		var vp := Vector2(VP_X * _aspect, VP_Y)
		var k := _view_h / 720.0
		var lead := 0.05 + 0.10 * front       # 灯比夜色领先这么多（同着色器）
		var n := 0
		for l in _lamps:
			if not l.live: continue
			l.z -= speed * pow(l.z, FLOW_EXP) * delta
			var z := l.z
			if z < Z_OUT:
				l.live = false
				l.root.visible = false
				continue
			var dy := 1.0 / z
			var lamp_h := dy * LAMP_PX * l.stature * k
			# 左右轻轻地晃（两种快慢叠在一起，近处按比例晃得大一点），自己也微微地转
			var sway := (sin(_time * 0.9 + l.phase) * 0.010 + sin(_time * 0.37 + l.phase * 1.7) * 0.016) * dy
			var at := Vector2(vp.x + (l.x0 + sway) * dy, vp.y + dy) + l.push
			# 出了画面的不画。倒影拖在灯底下三倍多长，留够边
			var margin := lamp_h * 3.8 / _view_h + 0.02
			if at.x < -margin or at.x > _aspect + margin or at.y < -margin or at.y > 1.0 + margin:
				if l.root.visible: l.root.visible = false
				continue
			# 灯河的前锋还没到的地方，灯不显：前锋就是最前排的灯
			var seen := 1.0 - smoothstep(front + lead - front_soft, front + lead + front_soft * 1.5, dy)
			if hole_r > 0.0:
				# 掀开：洞里的灯淡出去，洞边的被推着往四周散
				var hq := at - _hole
				var hd := hq.length() / _hole_far
				seen *= smoothstep(hole_r - 0.02, hole_r + 0.14, hd)
				if hd < hole_r + 0.45:
					l.push += hq.normalized() * (delta * PUSH * (1.0 - smoothstep(hole_r, hole_r + 0.45, hd)))
				# 洞外的灯散尽（远处的小灯挪得慢，等不到它们自己漂走）；贴着洞边被挤着的那一圈留到最后
				var re := (hd - hole_r) / 0.16
				var rim := exp(-re * re)
				seen *= 1.0 - ebb * (1.0 - rim)
			if seen <= 0.004:
				if l.root.visible: l.root.visible = false
				continue
			# 火苗的亮度：一快一慢两种晃叠在一起
			var flick := 0.86 + 0.10 * sin(_time * 6.3 + l.phase) + 0.06 * sin(_time * 11.7 + l.phase * 2.3)
			var nearness := smoothstep(0.3, 1.1, dy)          # 0 远，1 近
			l.root.visible = true
			l.root.position = at * _view_h
			l.root.scale = Vector2.ONE * (lamp_h / LAMP_PX)
			l.root.rotation = sin(_time * 0.5 + l.phase) * 0.06
			l.root.z_index = clampi(int(dy * 24.0), 0, Z_TOP)
			# 远处的灯身才几个像素，看不清是什么：小的时候不着痕迹地淡进来，那一段由光海里的灯代表它
			var body_a := smoothstep(16.0, 40.0, lamp_h) * seen
			l.mat_body.set_shader_parameter("alpha", body_a)
			l.mat_mirror.set_shader_parameter("strength", lerpf(0.45, 0.95, nearness) * flick * flick * seen)
			if body_a > 0.01:
				_pos[n] = at
				_lit[n] = Vector4(lamp_h * 2.3 / _view_h, lerpf(0.35, 0.75, nearness) * flick * seen, 0.0, 0.0)
				n += 1
		_sea.set_shader_parameter("lamp_n", n)
		if n > 0:
			_sea.set_shader_parameter("lamp_pos", _pos)
			_sea.set_shader_parameter("lamp_lit", _lit)

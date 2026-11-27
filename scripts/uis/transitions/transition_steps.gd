extends TransitionStyle
## 石阶沉浮（docs/transitions.md 五种样式里的第 3 种）。别的样式往屏幕上贴一层，这一种不贴，动的是棋盘上的石阶：
##   盖住  石阶从水车那一格往外一圈一圈沉进水里，沉下去的地方荡开一圈涟漪；河灯、道具跟着自己那一块走；
##         别处都沉完了，主角脚下那一块才带着主角和水车沉下去。最后"潜进水里"：一层暗幕压上来盖严。
##         调用的人（main.load_level）等盖严了才换棋盘，换棋盘那一帧就藏在暗幕底下。
##   中间  暗幕一直盖严。新棋盘一搭出来就把它按在水底（摆河灯是一件隔一帧落下的，那几帧新棋盘已经在树上）。
##   掀开  暗幕退开（浮上来），新棋盘的石阶从主角落脚的那一格往外一圈一圈浮出水面，带一点过冲；河灯、主角跟着自己那一块上来。
##
## 石阶是逐块挪 Tile 节点：格子上面的灯、站在上面的人、它自己的模型都挂在这一块上，挪节点最直接。Tile、Character、Fish
## 自己的 _process 每一帧会把高度写一遍，所以挪它们的这只手（steps_driver.gd）必须排在它们后面，每帧最后动一次。
## 过渡做完，每一块石阶、每一盏灯、主角都回到载入时记下的那个样子，这里不再碰它们。

const DRIVER := preload("res://scripts/uis/transitions/steps_driver.gd")
const RING_SHADER := preload("res://shaders/transition_steps_ring.gdshader")
const INK := Color(0.04, 0.06, 0.07)     # 和 SceneTransitionControl.INK 是同一个墨色：没有关卡底色的时侯暗幕用它

# ------------------------------------------------------------------ 数都在这儿调
const COVER_SECS := 0.48          # 平时的局盖住多久（规矩是 0.35 到 0.7）。别超过 0.5：调试用的 debug_transition_test 0.5 是过了
                                  # 0.5 秒来掀的，盖得比它久，那一下会被丢掉（见 pad_adapter.gd 的 debug_transition_test）
const REVEAL_SECS := 0.66         # 平时的局掀开多久（规矩是 0.4 到 0.9）：一圈一圈浮上来，圈和圈之间要隔得开，看得出是一圈一圈的
const COVER_FAST := 0.28          # 长夜、轮战的局：各 0.2 到 0.35
const REVEAL_FAST := 0.30
const SINK_DEPTH := 5.0           # 沉多深。藏的不只是石阶：水面在 y = -1.26，石阶上的河灯顶到台面上 1.5，主角连头顶的步数有 3.4，
                                  # 所以要沉到 5 以下它们才全在水里（掀开一开头，别让灯、人先于石阶冒出水面）
const GHOST_DEPTH := 6.0          # 旧棋盘上的对手（脚下已经没有石阶了）按到多深：比石阶还深，整个人在水里
const OUT_DEPTH := 1.75           # 浮上来的时候离水面多近开始"出水"这一段（台面在水下 0.5）：从这儿到停稳是看得见的，带过冲
const HIDDEN_RISE := 0.25         # 浮上来的时间里有这么一大段（占浮上来的时长）还在水底悄悄地升，剩下的才是出水
const DROP_SECS := 0.03           # 每一块沉下去用多久（带一点加速：越落越快）
const HERO_DROP_SECS := 0.11      # 主角脚下那一块：带着人和水车，沉得慢一点，看得出是一块大石头落下去
const RISE_SECS := 0.30           # 每一块浮上来用多久（平时的局）：先在水底升，出水那一段是阻尼弹簧，冲过头的量由弹簧自己给
const SPRING_K := 6.0             # 弹簧阻得多快（按浮上来的进度算）：到头的时侯已经停稳
const SPRING_W := TAU             # 弹簧的快慢：整个浮上来的过程里来回一次（过冲一回，回来就停）
const LAG_SECS := 0.05            # 灯、人比石阶慢这么一拍：石阶冲过头往回落的那一下，它们还往上飘一点，像浮在水上
const LAG_GAIN := 0.6             # 慢这一拍能差出多高（乘在石阶前后两拍的高度差上），封顶 LAG_CAP
const LAG_CAP := 0.16
const WATER_Y := -1.262           # 水面在多高（main.tscn 里 Water 那个节点的高度）：石阶擦过水面的那一刻荡开涟漪
const WAVE_GAP_MIN := 0.035       # 一圈和一圈之间隔多久。大棋盘圈多就挤一挤（换关换得快的局挤得更紧），小棋盘就慢一点
const WAVE_GAP_MAX := 0.11
const VEIL_TAIL := 0.06           # 盖住的最后这么长是纯暗的：换棋盘那一帧有多长看不出来
const VEIL_OUT := 0.5             # 掀开的开头这么一大段（占掀开的时长）暗幕退开：先快后慢，剩一点青色慢慢散掉
const TITLE_SECS := 0.24          # 关卡名换字用这么久（调用的人在盖住一开始就把字换了）：旧的先淡出，再淡入新的，
                                  # 两行字不同长，叠在一起淡会糊成一团

const RINGS := 72                 # 池子里备着多少圈涟漪（一块石阶一圈；最大的一关五六十块）
const RING_LIFE := 0.42           # 一圈荡多久：短。一圈圈石阶挨着沉，圈活得久就叠成一张网
const SPLASH_AT := 0.56           # 沉下去沉到这个份上（0 到 1）台面正好没进水里：那一刻荡开一圈

var veil: TextureRect             # "潜进水里"的那层暗幕，铺满画面、压在所有界面上（在"还没开始"的状态下整张透明）
var under: CanvasLayer            # 画在三维棋盘上面、界面底下的那一层：涟漪、换字时旧的那行关卡名
var driver: Node                  # 每帧最后动石阶的那只手（steps_driver.gd）

enum Phase { IDLE, COVER, MIDDLE, REVEAL }
var _phase: int = Phase.IDLE
var _clock := 0.0                 # 这一段过了几秒
var _time := 0.0                  # 装上样式以后过了几秒（涟漪按它算）
var _delta := 0.0                 # 这一帧过了多久（给不带参数的那几个小函数用）
var _snap_cost := 0.0             # 排查用的存图花了多久：那一帧不计入过渡的时钟（见 _snap）
var _stones: Array[Stone] = []    # 这一趟手里拿着的石阶
var _hero: Stone                  # 主角脚下那一块（盖住时最后沉，掀开时最先浮）
var _riders: Array[Rider] = []    # 站在石阶上的角色（主角、对战里的对手）和它脚下那一块
var _total := 0.0                 # 这一段一共多长
var _rise := 0.30                 # 这一趟每块石阶浮多久（换关换得快的局短一些）
var _hero_end := 0.0              # 主角脚下那一块落到第几秒（暗幕等它落完了再压上来）
var _hero_drop := 0.11            # 主角脚下那一块沉多久（换关换得快的局短一些）
var _veil_from := 0.0             # 暗幕从第几秒开始压上来 / 退开
var _veil_to := 0.0
var _veil := 0.0                  # 暗幕现在有多厚（最后一次写进着色器的数）
var _last_us := 0                 # 量帧时间：上一帧这只手动的时候
var _frames: Dictionary = {}      # 最近这一趟每一段最长的一帧（微秒）：cover、load、reveal，和它出现在那一段的第几秒（_at）
var _slow: Array[String] = []     # 最近这一趟里过了 20 毫秒的帧：哪一段、多长、第几秒（排查用）
var _reveal_us := 0               # 掀开是哪一刻开始的；_first_tick：这一段的第一帧还没量（排查用：把最长的那一帧拆成两半看）
var _first_tick := false
var _first_note := ""              # 掀开头一帧量出来的两半

# 涟漪的池子：节点在 build() 里建一次，反复用
var _ring_nodes: Array[ColorRect] = []
var _ring_at := PackedFloat32Array()      # 每一圈什么时候荡开的（-1：这个位置空着）
var _ring_amp := PackedFloat32Array()
var _ring_from := PackedFloat32Array()    # 每一圈从多大的半径荡起（0 中心，1 方块的边）
var _ring_front := PackedFloat32Array()   # 每一圈是不是迎着镜头的前半圈亮、后半圈淡（石阶还立在那儿的时侯）
var _ring_next := 0

# 关卡名换字
var _title_old: Label             # 旧的那一行（照着 main.level_label 的样子建的）
var _title_fade := 0.0            # 换字换到哪儿了（0 刚开始，1 换完）
var _title_shown := ""            # 画面上这一行现在是哪一关的名字（上一趟掀开完的那一关）
var _title_next := ""             # 这一趟要去的这一关的名字
var _label_modulate := Color.WHITE

## 一块石阶在过渡里的状态
class Stone:
	var tile: Tile                 # 沉浮的这一块
	var rest := 0.0                # 平时停在多高：过冲、回落都以它为准，做完也回到它
	var from := 0.0                # 从多高开始动
	var at := 0.0                  # 第几秒开始动
	var secs := 0.0                # 动多久
	var ring := 0                  # 离中心第几圈（1 是紧挨着的那一圈）
	var surface := 1.262           # 离原处还差多高的时侯台面正好在水面上
	var splashed := false          # 擦过水面的那一圈荡过了没有
	var done := false              # 沉到底 / 浮到位了没有

## 站在石阶上的角色和它脚下那一块。stone 是空的、或者那一块已经收走了：让它一直待在水底下
class Rider:
	var node: Node3D
	var stone: Stone

# ------------------------------------------------------------------ 接口

func build() -> void:
	veil = add(full_rect(shader("steps")), true)
	veil.visible = false          # 预热是外面帮着做的；平时藏着，盖的时候自己设回可见
	# 三维棋盘上面、界面底下的一层（游戏自己的界面在编号 1 的那一层）
	under = CanvasLayer.new()
	under.layer = 0
	_ring_nodes.resize(RINGS)
	_ring_at.resize(RINGS)
	_ring_amp.resize(RINGS)
	_ring_from.resize(RINGS)
	_ring_front.resize(RINGS)
	for i in RINGS:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = RING_SHADER
		m.set_shader_parameter("strength", 0.0)
		r.material = m
		under.add_child(r)
		_ring_nodes[i] = r
		_ring_at[i] = -1.0
		_ring_amp[i] = 0.0
	_title_old = Tutorial.make_label(64, Color.WHITE)
	_title_old.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_old.visible = false
	under.add_child(_title_old)
	add(under, true)               # 涟漪、旧的那行字在"还没开始"的状态下都看不见，白画两帧把着色器编译掉
	under.visible = false
	var hand := DRIVER.new()
	hand.name = "StepsDriver"
	hand.process_priority = 100        # 排在所有格子、角色、对战的玩法后面
	hand.style = self
	driver = add(hand)
	driver.set_process(false)

func cover(ctx: Dictionary) -> void:
	_frames = {}
	_slow.clear()
	_first_note = ""
	_last_us = 0
	_first_tick = false
	_clock = 0.0
	_phase = Phase.COVER
	_total = duration(ctx, COVER_SECS, COVER_FAST)
	_hero_drop = HERO_DROP_SECS * _total / COVER_SECS
	_title_next = str(ctx.get("title", ""))
	_set_veil_tint(ctx)
	veil.material.set("shader_parameter/flow", -1.0)
	veil.material.set("shader_parameter/shine", 0.0)
	_fit_veil()
	veil.visible = true
	under.visible = true
	_take_old_board(ctx)
	_fit_pool()
	_begin_title()
	# 暗幕：有旧棋盘的时侯等主角脚下那一块快落完了再压上来（压上来是先慢后快的，见 _tick_cover：它落的时侯暗幕还很淡，看得清）；
	# 没有旧棋盘（从标题页进游戏）就是一路暗下去
	_veil_from = clampf(_hero_end - 0.09, 0.0, _total * 0.6) if not _stones.is_empty() else 0.0
	_veil_to = _total - VEIL_TAIL
	_set_veil(0.0)
	driver.set_process(true)
	while _phase == Phase.COVER:
		await ctl.get_tree().process_frame

func reveal(ctx: Dictionary) -> void:
	_clock = 0.0
	_phase = Phase.REVEAL
	_reveal_us = Time.get_ticks_usec()
	_total = duration(ctx, REVEAL_SECS, REVEAL_FAST)
	_rise = RISE_SECS * _total / REVEAL_SECS
	_set_veil_tint(ctx)
	veil.material.set("shader_parameter/flow", 1.0)
	_fit_veil()
	# 一进来就把新棋盘按在水底：和调用的人在同一帧里、渲染之前。不然会先闪一帧摆好的棋盘
	_take_new_board(ctx)
	_fit_pool()
	if _stones.is_empty() and not _veil_is_up():
		veil.visible = false       # 开机掀幕：没盖过，画面上也没有石阶，什么都不用做
		_phase = Phase.IDLE
		return
	_veil_from = 0.0
	_veil_to = _total * VEIL_OUT if not _stones.is_empty() else _total * 0.8
	under.visible = true
	_first_tick = true
	driver.set_process(true)
	while _phase == Phase.REVEAL:
		await ctl.get_tree().process_frame
	# 掀开完，画面上那一行关卡名就是这一关的了，记下来：下一趟盖住时旧的这一行要淡出去。
	# 从标题页进游戏的头一趟是换场景那次 close() 触发的，说明里没有关卡名，所以直接读那一行字
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main != null and main.level_label != null: _title_shown = main.level_label.text
	_give_back()

## 换样式的时侯：先把借走的东西都还回去（万一正做到一半），再让基类收走节点
func dispose() -> void:
	driver.set_process(false)
	_give_back()
	super()

# ------------------------------------------------------------------ 每帧

func _tick(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _first_tick and _last_us != 0:
		# 掀开头一帧要是长：一半在 reveal() 之前（上一帧画完、这一帧别的东西在跑），一半在之后（这一帧里样式自己和自己以后的东西）
		_first_note = "掀开头一帧：reveal() 之前 %.0f 毫秒，之后 %.0f 毫秒" % [(_reveal_us - _last_us) / 1000.0, (now - _reveal_us) / 1000.0]
		_first_tick = false
	if _last_us != 0 and _phase != Phase.IDLE:
		var key := "load" if _phase == Phase.MIDDLE else ("cover" if _phase == Phase.COVER else "reveal")
		var took := now - _last_us
		if took > int(_frames.get(key, 0)):
			_frames[key] = took
			_frames["%s_at" % key] = _clock          # 最长的那一帧出现在这一段的第几秒：查是哪一下卡的
		if took > 20000: _slow.append("%s %.0f 毫秒（第 %.2f 秒）" % [key, took / 1000.0, _clock])
	_last_us = now
	if _snap_cost > 0.0:           # 上一帧存图花的时间不算：过渡里的东西都按时间走，不然存一张图就把后面的时候全跳过去了
		delta = maxf(delta - _snap_cost, 0.0)
		_snap_cost = 0.0
	_delta = delta
	_time += delta
	_tick_rings()
	if _phase == Phase.IDLE:
		driver.set_process(false)
		return
	_clock += delta
	match _phase:
		Phase.COVER:
			_tick_cover()
			if _clock >= _total: _to_middle()
		Phase.MIDDLE:
			_tick_middle()
		Phase.REVEAL:
			_tick_reveal()
			if _clock >= _total:
				_phase = Phase.IDLE
				_last_us = 0

func _tick_cover() -> void:
	for s in _stones:
		if not is_instance_valid(s.tile): continue        # 场景换了（回标题页）：旧棋盘已经收走了
		var p := clampf((_clock - s.at) / s.secs, 0.0, 1.0)
		# 越落越快：开头几乎不动，末了直落下去
		_set_stone_y(s, lerpf(s.from, s.rest - SINK_DEPTH, p * p * (0.55 + 0.45 * p)))
		if p >= SPLASH_AT and not s.splashed:
			s.splashed = true           # 台面没进水里的那一刻
			_splash(s, 0.8 if s == _hero else 0.42)
		if p >= 1.0 and not s.done:
			s.done = true
			if s == _hero: _splash(s, 0.6, true)      # 连人带水车都没进去了：再荡开一圈大的
	_tick_title()
	# 暗幕压上来是先慢后快的：头几帧只是暗了一点，看得出主角脚下那一块在落
	var x := _veil_amount()
	_set_veil(x * x)

func _tick_middle() -> void:
	# 摆河灯是一件隔一帧落下的：每一帧都看一眼树上有没有新来的石阶，有就按到水底
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main != null and main.grid != null and not main.grid.tiles.is_empty():
		_hold_board(main)
		# 灯刚摆下来的那一秒本来是从水里跳出来再落回去（fish.gd 的 animation）。石阶还在水底，先让它老老实实待在石阶上
		for s in _stones:
			var f := _lamp_of(s)
			if f != null: _pose_lamp(f, 0.0)
	_keep_under()

func _tick_reveal() -> void:
	for s in _stones:
		if not is_instance_valid(s.tile): continue
		var u := clampf((_clock - s.at) / s.secs, 0.0, 1.0)
		var gap := _rise_gap(u)
		_set_stone_y(s, s.rest - gap)
		# 灯、人比石阶慢一拍：石阶冲过头往回落的那一下，它们还往上飘一点
		var lag := clampf((_rise_gap(u) - _rise_gap(u - LAG_SECS / s.secs)) * LAG_GAIN, -LAG_CAP, LAG_CAP)
		var f := _lamp_of(s)
		if f != null:
			_pose_lamp(f, lag)
			if u >= 1.0 and f.animation < 1.0: f.animation = 1.0      # 入场那一下算它落完了：下一帧它自己会响一声落地的水声
		for r in _riders:
			if r.stone == s and is_instance_valid(r.node):
				var who: Character = r.node as Character
				if who != null: who.sprite_container.position.y = lag * 0.5
		if gap <= s.surface and not s.splashed:
			s.splashed = true           # 台面破水而出
			# 从石阶的轮廓外头荡起：石阶浮上来了，圈要绕着它往外走，别压在它和河灯的脸上
			_splash(s, 0.8 if s == _hero else 0.42, false, 0.72, 1.0)
			if s == _hero: _water_ripple(s, 1.0)      # 水面上真起波浪的那一圈只有六个位置，主角脚下这一块用
		if u >= 1.0 and not s.done: s.done = true
	_hold_ghosts()
	_tick_title()
	# 暗幕退开是先快后慢的：头两三帧就看见河了，剩一点青色慢慢散掉；破水那一下顶上漫下来一点光，退到一半最亮，退净就没了
	var gone := _veil_amount()
	_set_veil(pow(1.0 - gone, 1.6))
	veil.material.set("shader_parameter/shine", 4.0 * gone * (1.0 - gone))

## 浮上来的时候离原处还差多高（正数是还在下面）。前 HIDDEN_RISE 那一段在水底从 SINK_DEPTH 升到 OUT_DEPTH，越升越快，
## 看不见；之后是阻尼弹簧：从 OUT_DEPTH 回到原处，中间冲过头一回。u 小于 0 的时侯还没开始动
static func _rise_gap(u: float) -> float:
	if u <= 0.0: return SINK_DEPTH
	if u >= 1.0: return 0.0
	if u < HIDDEN_RISE:
		var t := u / HIDDEN_RISE
		return SINK_DEPTH - (SINK_DEPTH - OUT_DEPTH) * t * t
	return OUT_DEPTH * exp(-SPRING_K * (u - HIDDEN_RISE) / (1.0 - HIDDEN_RISE)) * cos(SPRING_W * (u - HIDDEN_RISE) / (1.0 - HIDDEN_RISE))

## 这一块石阶上面摆着的灯、道具。已经被收走了的（收走的灯在格子上还留着引用）就当没有
func _lamp_of(s: Stone) -> Fish:
	if not is_instance_valid(s.tile): return null
	return _fish_on(s.tile)

func _fish_on(tile: Tile) -> Fish:
	var o: Node3D = tile.object
	if o == null or not is_instance_valid(o): return null
	return o as Fish

## 灯自己的入场动画每一帧都会写这两个数，这里随后改写：pos 是它比石阶高多少，大小回到原样
func _pose_lamp(f: Fish, pos: float) -> void:
	f.shadow_sprite_container.position = Vector3(0.0, pos, 0.0)
	f.shadow_sprite_container.scale = Vector3.ONE

## 暗幕这会儿退开了多少（0 还盖着，1 退净），按时间算
func _veil_amount() -> float:
	return clampf((_clock - _veil_from) / maxf(_veil_to - _veil_from, 0.001), 0.0, 1.0)

## 把暗幕的厚度写进着色器。自己记一份：不从材质里读回来（读回来的是_variant，空着的时侯不是数）
func _set_veil(amount: float) -> void:
	_veil = amount
	veil.material.set("shader_parameter/depth", amount)

func _veil_is_up() -> bool:
	return _veil > 0.0

func _set_veil_tint(ctx: Dictionary) -> void:
	# 潜进水里看见的就是这条河，颜色照着游戏里水面的算法来：colors.gd 把关卡的底色压暗 0.78 当水的底色，
	# stage_water.gdshader 再往墨色里压四成（那一步是在线性色里做的，这里也在线性色里做，算出来才一模一样）。
	# 换了一关，暗幕的颜色跟着那一关的水走，和棋盘露出来时接得上
	var water: Color = Color(ctx.get("color", INK)).darkened(0.78).srgb_to_linear().lerp(Color(0.012, 0.017, 0.024), 0.40).linear_to_srgb()
	veil.material.set("shader_parameter/tint", water)

## 月光那一汪在画面上的什么地方、多大（照 stage_backdrop.gd 的 _fit_board 的算法：盖住整张棋盘再往外 3.2、2.4）。
## 潜进水里看见它就在头顶上；浮上来时水面上的那一汪正在同一个地方
func _fit_pool() -> void:
	var main := ctl.get_node_or_null("/root/Main") as Main
	var centre := Vector2(0.5, 0.5)
	var radius := Vector2(0.001, 0.001)
	if main != null and main.camera_3d != null and main.grid != null and not _stones.is_empty():
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for s in _stones:
			if not is_instance_valid(s.tile): continue
			var at := Vector2(s.tile.global_position.x, s.tile.global_position.z)
			lo = lo.min(at)
			hi = hi.max(at)
		if lo.x < 1e8:
			var cam: Camera3D = main.camera_3d
			var view: Vector2 = ctl.get_viewport().get_visible_rect().size
			var half: float = main.grid.tile_size.x * 0.5
			var c := Vector3((lo.x + hi.x) * 0.5, WATER_Y, (lo.y + hi.y) * 0.5)
			var size := (hi - lo) * 0.5 + Vector2.ONE * half + Vector2(3.2, 2.4)
			var mid: Vector2 = cam.unproject_position(c)
			var ex: Vector2 = cam.unproject_position(c + Vector3(size.x, 0.0, 0.0)) - mid
			var ez: float = ((cam.unproject_position(c + Vector3(0.0, 0.0, size.y)) - mid).length() + (cam.unproject_position(c - Vector3(0.0, 0.0, size.y)) - mid).length()) * 0.5
			centre = mid / view
			radius = Vector2(maxf(ex.length(), 1.0) / view.x, maxf(ez, 1.0) / view.y)
	veil.material.set("shader_parameter/pool", centre)
	veil.material.set("shader_parameter/pool_r", radius)

## 暗幕按画面算宽高（画面是 1152×720，掌机的窗口是 2560×1600，不写死）
func _fit_veil() -> void:
	var size := ctl.get_viewport().get_visible_rect().size
	veil.material.set("shader_parameter/aspect", size.x / maxf(size.y, 1.0))

## 盖严了。旧棋盘交还给调用的人去收（这里不再碰它），后面那几帧只管把新来的按到水底
func _to_middle() -> void:
	_phase = Phase.MIDDLE
	_clock = 0.0
	_set_veil(1.0)
	_finish_title()
	if _title_next != "": _title_shown = _title_next      # 暗幕底下字已经换了：从现在起画面上这一行是新一关的
	_stones.clear()

# ------------------------------------------------------------------ 拿起来、放回去

## 盖住：把旧棋盘拿起来。从水车那一格往外按格子量距离，近的一圈先沉；主角脚下那一块留到最后
func _take_old_board(ctx: Dictionary) -> void:
	_stones.clear()
	_riders.clear()
	_hero = null
	var main := ctx.get("main") as Main
	if main == null or not is_instance_valid(main.grid) or main.grid.tiles.is_empty(): return
	var centre := _centre(ctx, main)
	var unit: float = main.grid.tile_size.x
	var rings := 0
	for tile: Tile in main.grid.tiles.values():
		var s := Stone.new()
		s.tile = tile
		s.rest = _rest_y(tile)
		s.from = tile.global_position.y
		s.secs = DROP_SECS
		s.surface = s.rest - WATER_Y
		s.ring = int(floor(Vector2(tile.global_position.x - centre.x, tile.global_position.z - centre.y).length() / unit + 0.5))
		rings = maxi(rings, s.ring)
		_stones.append(s)
		if tile == main.character.target_tile: _hero = s
	if _hero == null: _hero = _stones[0]
	# 一圈隔一圈地沉，总归在盖住的前一半里沉完，留给主角那一块和暗幕。大棋盘圈多就挤一挤，小棋盘就慢一点
	var gap := _wave_gap(rings, _total * 0.5 - DROP_SECS)
	var latest := 0.0
	for s in _stones:
		s.at = (s.ring - 1) * gap + s.tile.rseed * gap * 0.3     # 同一圈里的几块差一点点，不是齐刷刷的
		if s != _hero: latest = maxf(latest, s.at)
	_hero.secs = _hero_drop
	_hero.at = clampf(latest + DROP_SECS + 0.02, _total * 0.4, _total - _hero_drop - VEIL_TAIL - 0.05)
	_hero_end = _hero.at + _hero_drop
	_riders.append(_make_rider(main.character, _hero))
	# 对战里的对手站在它自己那一块上，跟着那一块走
	if main.versus != null and is_instance_valid(main.versus.foe):
		var foe: Character = main.versus.foe
		var standing: Tile = foe.target_tile if is_instance_valid(foe.target_tile) else null
		_riders.append(_make_rider(foe, _stone_of(standing)))

func _make_rider(node: Node3D, stone: Stone) -> Rider:
	var r := Rider.new()
	r.node = node
	r.stone = stone
	return r

func _stone_of(tile: Tile) -> Stone:
	if not is_instance_valid(tile): return null
	for s in _stones:
		if s.tile == tile: return s
	return null

## 一圈隔多久：想把 wave 这么长的一段分给 rings 圈，但每圈至少隔那么一下、至多也不过 top 那么久
func _wave_gap(rings: int, wave: float, top := WAVE_GAP_MAX) -> float:
	var lo := 0.02 if _total < 0.4 else WAVE_GAP_MIN
	return clampf(wave / maxf(rings - 1.0, 1.0), lo, top)

## 还没拿起来的石阶都拿起来、按到水底（新棋盘每一块都从水底往上浮）
func _hold_board(main: Main) -> void:
	var taken := {}
	for s in _stones:
		if is_instance_valid(s.tile): taken[s.tile] = s
	for tile: Tile in main.grid.tiles.values():
		if taken.has(tile): continue
		var s := Stone.new()
		s.tile = tile
		s.rest = _rest_y(tile)
		s.from = s.rest - SINK_DEPTH
		s.secs = _rise
		s.surface = s.rest - WATER_Y
		s.done = true
		_stones.append(s)
		_set_stone_y(s, s.from)

## 掀开：新棋盘已经在水底了，定下谁先浮。主角落脚的那一格先浮，往外一圈一圈跟着
func _take_new_board(ctx: Dictionary) -> void:
	var main := ctl.get_node_or_null("/root/Main") as Main
	_stones = _stones.filter(func(s: Stone) -> bool: return is_instance_valid(s.tile))
	_riders = _riders.filter(func(r: Rider) -> bool: return is_instance_valid(r.node))
	_hero = null
	if main == null or not is_instance_valid(main.grid) or main.grid.tiles.is_empty(): return
	_hold_board(main)
	var centre := _centre(ctx, main)
	var unit: float = main.grid.tile_size.x
	var rings := 0
	var nearest := 1e9
	for s in _stones:
		var d := Vector2(s.tile.global_position.x - centre.x, s.tile.global_position.z - centre.y).length() / unit
		s.ring = int(floor(d + 0.5))
		rings = maxi(rings, s.ring)
		s.done = false
		s.secs = _rise
		if d < nearest:
			nearest = d
			_hero = s
	# 一圈隔一圈地浮，最后一圈到头还留一点余量。小棋盘圈少就隔得开些（一眼看得出是一圈一圈的），大棋盘圈多就挤一挤
	var gap := _wave_gap(rings + 1, _total - _rise - 0.06, 0.12)
	for s in _stones:
		s.at = s.ring * gap + s.tile.rseed * gap * 0.3
	_hero.at = 0.02
	# 主角站上新一关的起点。上一趟记下的主角那一条不要了（它脚下是旧棋盘的石头）；
	# 别的角色（对战里的对手）照旧留着：脚下那一块还在的跟着走，不在了的沉在水底（见 _hold_ghosts），新对手摆好了游戏会把它收走
	_riders = _riders.filter(func(r: Rider) -> bool: return r.node != main.character)
	_riders.append(_make_rider(main.character, _hero))

## 把一块石阶放到 y 这么高。它上面摆着的灯、道具跟着走；站在它上面的角色也跟着走
func _set_stone_y(s: Stone, y: float) -> void:
	if not is_instance_valid(s.tile): return
	s.tile.global_position.y = y
	var f := _lamp_of(s)
	if f != null: f.global_position.y = y
	for r in _riders:
		if r.stone == s and is_instance_valid(r.node): r.node.global_position.y = y

## 中间那几帧，角色每一帧都会被它自己的 _process 拉回原处（它记着的目标格子的高度是载入时的）：
## 脚下有石阶的跟着石阶走，脚下没有的按在水底下
func _keep_under() -> void:
	for r in _riders:
		if not is_instance_valid(r.node): continue
		if r.stone != null and is_instance_valid(r.stone.tile): r.node.global_position.y = r.stone.tile.global_position.y
		else: r.node.global_position.y = -GHOST_DEPTH

## 脚下已经没有石阶的角色（旧棋盘上的对手）：按在水底下，别让它浮出来站在新棋盘上
func _hold_ghosts() -> void:
	for r in _riders:
		if is_instance_valid(r.node) and (r.stone == null or not is_instance_valid(r.stone.tile)):
			r.node.global_position.y = -GHOST_DEPTH

## 过渡做完：借走的都还回去。石阶回到载入时记下的高度，暗幕收走
func _give_back() -> void:
	for s in _stones:
		if not is_instance_valid(s.tile): continue
		_set_stone_y(s, s.rest)
		var f := _lamp_of(s)
		if f != null and f.animation < 1.0: f.animation = 1.0        # 没浮到位就做完的灯：入场那一下也算落完了
	for r in _riders:
		if not is_instance_valid(r.node): continue
		var who: Character = r.node as Character
		if who == null: continue
		who.sprite_container.position.y = 0.0
		# 脚下已经没有石阶的角色：把它放回它自己记着的位置
		if r.stone == null or not is_instance_valid(r.stone.tile): who.global_position.y = who.target_position.y
	_stones.clear()
	_riders.clear()
	_hero = null
	_finish_title()
	_phase = Phase.IDLE
	_set_veil(0.0)
	veil.visible = false
	under.visible = false
	driver.set_process(false)

## 中心在哪儿：盖住的时侯是水车那一格（主角正站在它上面）；掀开的时侯是主角落脚的那一格
func _centre(ctx: Dictionary, main: Main) -> Vector2:
	var p: Vector3 = main.character.global_position
	if ctx.has("to"):
		p = ctx.to
	elif is_instance_valid(main.end_portal_instance):
		p = main.end_portal_instance.global_position
	return Vector2(p.x, p.z)

## 平时石阶停在多高。和 tile.gd 的 _process 里那个 rest_height 是同一个式子：碎掉的脆格沉着一截，
## 障碍高出一截，选技能目标的时侯选中的那一格抬起来。过渡做完要回到这儿，不然它自己还得慢慢飘回去
static func _rest_y(tile: Tile) -> float:
	return tile.pos_y + tile.aim_raise - (0.9 if tile.is_broken() else 0.0) + (0.8 if tile.is_blocked() else 0.0)

# ------------------------------------------------------------------ 涟漪

## 一块石阶擦过水面（沉下去没进水里、浮上来破水而出）：在它那一格荡开一小圈。画在格子面上、界面底下，
## 样子照 stage_backdrop.gd 落地那圈环（俯着看是扁的）。
## from：从多大的半径荡起（石阶的半边是 0.52）。沉下去的时侯石阶已经没了，从当中起；浮上来的时侯它还在那儿，从轮廓外头起。
## front：迎着镜头的前半圈亮、后半圈淡（石阶还立在那儿的时侯用）。
## big：荡得更大的一圈，给主角脚下那一块连人一起没进去的那一下
func _splash(s: Stone, amp: float, big := false, from := 0.3, front := 0.0) -> void:
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main == null or main.camera_3d == null: return
	var cam: Camera3D = main.camera_3d
	var p: Vector3 = s.tile.global_position
	p.y = s.rest
	var c: Vector2 = cam.unproject_position(p)
	var half_cell: float = main.grid.tile_size.x * 0.5
	var ex: Vector2 = cam.unproject_position(p + Vector3(half_cell, 0.0, 0.0)) - c
	var ez: Vector2 = cam.unproject_position(p + Vector3(0.0, 0.0, half_cell)) - c
	var half: float = maxf(ex.length(), 4.0) * (2.6 if big else 1.9)      # 方块的半边：环荡到边上（半径 1）有一格多宽，细而薄，像水面自己的水纹
	var i := _ring_next
	_ring_next = (_ring_next + 1) % RINGS
	_ring_at[i] = _time
	_ring_amp[i] = amp
	_ring_from[i] = from
	_ring_front[i] = front
	var r := _ring_nodes[i]
	r.position = c - Vector2(half, half)
	r.size = Vector2(half * 2.0, half * 2.0)
	var m := r.material as ShaderMaterial
	m.set_shader_parameter("squash", clampf(ez.length() / maxf(ex.length(), 0.001), 0.3, 1.0))
	m.set_shader_parameter("phase", s.tile.rseed * TAU)
	m.set_shader_parameter("front", front)

## 水面上真荡开一圈（stage_backdrop.gd 的 ripple）。水面上这样的涟漪只有六个位置轮着用，一圈要荡一秒多，
## 所以只给掀开时主角脚下那一块破水而出的那一下（盖住时落地那圈已经在那儿了，别再叠一圈：它会一直荡到新棋盘露出来，抢戏）
func _water_ripple(s: Stone, amp: float) -> void:
	var main := ctl.get_node_or_null("/root/Main")
	if main == null: return
	var stage: Node = main.get_node_or_null("StageBackdrop")
	if stage == null or not stage.has_method("ripple"): return
	var p: Vector3 = s.tile.global_position
	stage.call("ripple", Vector2(p.x, p.z), amp)

## 池子里的每一圈：荡开、淡下去。先快后慢；亮一下就淡，活得短（一圈圈石阶挨着沉，圈活得久就叠成一张网）
func _tick_rings() -> void:
	for i in RINGS:
		if _ring_at[i] < 0.0: continue
		var age := _time - _ring_at[i]
		var m := _ring_nodes[i].material as ShaderMaterial
		if age >= RING_LIFE:
			_ring_at[i] = -1.0
			m.set_shader_parameter("strength", 0.0)
			continue
		var k := age / RING_LIFE
		m.set_shader_parameter("radius", lerpf(_ring_from[i], 1.0, 1.0 - (1.0 - k) * (1.0 - k)))
		m.set_shader_parameter("strength", _ring_amp[i] * minf(age / 0.03, 1.0) * (1.0 - smoothstep(0.08, 1.0, k)))

# ------------------------------------------------------------------ 关卡名换字

## 调用的人在盖住一开始就把关卡名换成了要去的这一关（main.load_level）。旧棋盘还在眼前沉，先别让新的那行字突兀地蹦出来：
## 旧的淡出、新的淡入。上一趟是哪一关记在 _title_shown 里；进游戏的头一趟没有旧的，新的那行就跟着暗幕退开一起出来
func _begin_title() -> void:
	_title_fade = 1.0
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main == null or main.level_label == null: return
	var label: Label = main.level_label
	_label_modulate = label.modulate
	_title_old.label_settings = label.label_settings
	_title_old.anchor_left = label.anchor_left
	_title_old.anchor_right = label.anchor_right
	_title_old.anchor_top = label.anchor_top
	_title_old.anchor_bottom = label.anchor_bottom
	_title_old.offset_left = label.offset_left
	_title_old.offset_right = label.offset_right
	_title_old.offset_top = label.offset_top
	_title_old.offset_bottom = label.offset_bottom
	if _title_shown == "" or _title_shown == label.text:
		_finish_title()
		return
	_title_old.text = _title_shown
	_title_old.visible = true
	_title_old.modulate = _label_modulate
	_title_fade = 0.0
	label.modulate.a = 0.0

func _tick_title() -> void:
	if _title_fade >= 1.0: return
	_title_fade = minf(_title_fade + _delta / TITLE_SECS, 1.0)
	# 前四成：旧的淡出；后六成：新的淡入
	_title_old.modulate.a = _label_modulate.a * (1.0 - minf(_title_fade / 0.4, 1.0))
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main != null and main.level_label != null:
		main.level_label.modulate.a = _label_modulate.a * clampf((_title_fade - 0.4) / 0.6, 0.0, 1.0)
	if _title_fade >= 1.0: _finish_title()

## 换完了：旧的那行收走，真的那行亮出来（这时暗幕盖严了，或者本来就不用换）
func _finish_title() -> void:
	_title_fade = 1.0
	_title_old.visible = false
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main != null and main.level_label != null: main.level_label.modulate = _label_modulate

# ------------------------------------------------------------------ 给调试遥控用

## 最近一趟量出来的数：每一段最长的一帧，和它出现在那一段的第几秒；再列出过了 20 毫秒的帧
func debug_last() -> String:
	var names := {"cover": "盖住", "load": "中间", "reveal": "掀开"}
	var parts: Array[String] = []
	for key in ["cover", "load", "reveal"]:
		if not _frames.has(key): continue
		parts.append("%s最长一帧 %.1f 毫秒（第 %.2f 秒）" % [names[key], float(_frames[key]) / 1000.0, float(_frames.get("%s_at" % key, 0.0))])
	var text := "石阶沉浮：" + "；".join(parts)
	if _first_note != "": text += "；" + _first_note
	if not _slow.is_empty(): text += "；过了 20 毫秒的帧：" + "，".join(_slow.slice(0, 12))
	return text

## 排查用（call steps_driver.gd debug_frames）：就地放一遍（盖住、停一下、掀开），在几处要紧的时刻各存一张全分辨率的 PNG。
## 录像存的 JPG 深色偏色（暗青的水会存成暗棕），暗幕、水面这种暗处要看无损的图才准。
## 文件在 <SW_SNAP>_steps_<时刻>.png：c 是盖住、m 是盖严、r 是掀开，后面的数是那一段过了几百分之几秒
func debug_frames() -> String:
	_shoot_frames()
	return "正在存图：%s_steps_*.png" % _snap_base()

func _snap_base() -> String:
	var base := OS.get_environment("SW_SNAP")
	return base if base != "" else "/tmp/sw_snap"

func _shoot_frames() -> void:
	var scene_ctl: Node = SceneManager.scene_transition_control
	if scene_ctl == null or scene_ctl.is_opened: return
	scene_ctl.call("open", {"mode": "level"})
	for t in [8, 16, 24, 33, 42]:
		while _phase == Phase.COVER and _clock < float(t) / 100.0: await ctl.get_tree().process_frame
		_snap("c%02d" % t)
	await ctl.get_tree().create_timer(0.2).timeout
	_snap("m00")
	scene_ctl.call("close", {"mode": "level"})
	for t in [4, 9, 14, 19, 24, 30, 38, 50]:
		while _phase == Phase.REVEAL and _clock < float(t) / 100.0: await ctl.get_tree().process_frame
		_snap("r%02d" % t)

func _snap(tag: String) -> void:
	# 存的是上一帧画出来的那张（这一帧还没画）：盖住、掀开里的东西都按时间算位置，所以它就是"这一刻"的样子。
	# 存一张要大半秒：这段时间从下一帧的 delta 里扣掉，过渡的时钟只走真实玩的时候该走的那一点
	var t0 := Time.get_ticks_usec()
	ctl.get_viewport().get_texture().get_image().save_png("%s_steps_%s.png" % [_snap_base(), tag])
	_snap_cost = float(Time.get_ticks_usec() - t0) / 1000000.0

## 过渡做完以后查一遍。哪一块石阶、哪盏灯、哪个角色没回到平时的样子就报出来
func debug_trace() -> String:
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main == null: return "RESULT 石阶沉浮：不在游戏里"
	var bad: Array[String] = []
	for tile: Tile in main.grid.tiles.values():
		var where := "(%.1f, %.1f)" % [tile.global_position.x, tile.global_position.z]
		if absf(tile.global_position.y - _rest_y(tile)) > 0.002: bad.append("格子 %s 的高度 %f，应该是 %f" % [where, tile.global_position.y, _rest_y(tile)])
		if not tile.is_processing(): bad.append("格子 %s 的 _process 没开" % where)
		var f := _fish_on(tile)
		if f != null:
			if absf(f.global_position.y - tile.global_position.y) > 0.002: bad.append("%s 上的灯高 %f，石阶高 %f" % [where, f.global_position.y, tile.global_position.y])
			if f.shadow_sprite_container.position != Vector3.ZERO: bad.append("%s 上的灯还偏着 %s" % [where, f.shadow_sprite_container.position])
			if f.shadow_sprite_container.scale != Vector3.ONE: bad.append("%s 上的灯大小是 %s" % [where, f.shadow_sprite_container.scale])
			if not f.is_processing(): bad.append("%s 上的灯 _process 没开" % where)
	var who: Character = main.character
	if absf(who.global_position.y - who.target_position.y) > 0.002: bad.append("主角高 %f，应该在 %f" % [who.global_position.y, who.target_position.y])
	if who.sprite_container.position.y != 0.0: bad.append("主角的身子还偏着 %f" % who.sprite_container.position.y)
	if main.level_label.modulate != _label_modulate: bad.append("关卡名的 modulate 是 %s" % main.level_label.modulate)
	if veil.visible or under.visible or _phase != Phase.IDLE: bad.append("样式自己的东西还露着（暗幕 %s，底层 %s，阶段 %d）" % [veil.visible, under.visible, _phase])
	if driver.is_processing(): bad.append("Driver 还在跑")
	if bad.is_empty(): return "RESULT 石阶沉浮：通过（%d 块石阶都在原处，灯、主角也都回了位，样式自己的东西都收了）" % main.grid.tiles.size()
	return "RESULT 石阶沉浮：没过，%d 处：%s" % [bad.size(), "；".join(bad.slice(0, 6))]

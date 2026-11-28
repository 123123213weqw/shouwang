extends TransitionStyle
## 涟漪开合：换关的过渡的一种。任务书在 docs/transitions.md 的「ripple」，接口在 transition_style.gd。
##   盖住  主角踩上水车，脚下那圈涟漪不停，一圈一圈往外荡，把棋盘淹了：圈里是夜里的河面，和标题页是同一条河
##         （shaders/transition_ripple.gdshader，照着 lobby_river.gdshader 改的），主圈后面跟着两圈淡的拖尾。
##         河面的颜色每帧读游戏里那条河此刻的水色，在游戏里水纹也照它画：淹上来的水和四周永远是同一片
##   题字  河面快盖严的时侯在正中淡入"第几关"和这一关的名字，名字右下角落一方印。只在真的过了上一关的时侯题
##   掀开  河面以主角落脚的那一格为中心收拢，圈外露出新的关卡，收到脚下为止；题字跟着这一圈一起走
##
## 时间上的事都在这个文件里：过渡进行中每一帧调一次 _apply()，按"这一段开始了多久"把着色器的参数和题字
## 整个算一遍，着色器只管画。所以没有补间、没有定时器，哪一帧都是从时间现算的，帧率高低都不走样。
## 调样式的时侯：call pad_adapter.gd debug_transition_test 3（就地放一遍，不换关；在游戏里这一遍一定题字）。
## 停多久是从盖住做完以后算的；要看盖严的样子就多停一会儿，停着的时侯截图

const SOFT := 0.02           # 圈边的软边有多宽（画面高度的几分之几）。主圈要多荡出这么一段才算盖严
const WOBBLE := 0.025        # 圈边沿着圈起伏，最多偏这么多（和着色器里一个数）。算盖严的半径时也要留出来
const SQUASH := 0.72         # 游戏里的圈有多扁：俯着看，地上的圆在画面上是扁的。和落地的那圈环一个数（StageBackdrop.RING_SQUASH）
# 平时的局盖住、掀开各多久（秒）。两段加起来别超过 1.3 秒（docs/transitions.md 的规矩），题字的节奏也是照着 0.5 秒排的
const COVER := 0.5
const REVEAL := 0.5
const FAST := 0.28           # 换关换得快的局（长夜、轮战）：两段各 0.25 秒上下。量出来不到 0.25 会被判太快，所以留一点余量
const LAG := 0.08            # 拖尾比主圈晚出生多久（秒）：一圈一圈的节奏

# 题字的时间：小字在"盖住这一段走到几分之几"时开始淡入（KICKER_AT），大字、印章比它晚多久开始。
# 主角站得离画面正中远的时侯圈要晚一点才淹到题字那一块，那就等圈淹到了再开始（_text_wait）
const KICKER_AT := 0.30
const NAME_LATER := 0.14
const SEAL_LATER := 0.42
const TEXT_IN := 0.24        # 小字、大字各淡入多久（也是盖住这一段的几分之几）
const SEAL_DROP := 0.12      # 印章落下来用多久（秒）。照开场动画里那一方印（opening.gd 的 _seal）：从大缩到正常，不出声
const SEAL_BIG := 3.2        # 印章落下以前有多大
const TEXT_OUT := 0.45       # 掀开这一段走到几分之几，题字走完了

const KICKER_PX := 30
const NAME_PX := 96
const SEAL_PX := 70          # 印章的边长。开场那一方是 104，对着 182 宽的标志；这里的大字是 96，按比例小一号
const GAP := 14              # 小字和大字之间隔多远
const RULE_W := 46           # 小字两边两道细线的长，和离小字多远
const RULE_GAP := 16
const SEAL_GAP := 18         # 印章离大字多远（大字最右一笔会探出它的框几个像素，留够才不贴上）

const JADE := Color(0.86, 0.94, 0.90)       # 落地那圈环的颜色（StageBackdrop._ring）：小字和两道细线用它
const MOON := Color(0.95, 0.93, 0.85)       # 河里月亮的颜色，大字用它：和河面是一套
const INK := Color(0.02, 0.05, 0.05)        # 字底下垫的一点影（开场动画的墨色）
const WATER_INK := Color(0.012, 0.017, 0.024)   # 游戏里的水面把底色往墨里压，压向的就是这个颜色（stage_water.gdshader）
const NIGHT := 0.40                             # 压多少（同上）
const TINT := 1.0                               # 在游戏里河面全用这一关的水色：淹上来的水和棋盘底下原来的水是同一片
const TITLE_RIVER := Color(0.04, 0.06, 0.07)    # 标题页那条河的底色，就是 SceneTransitionControl.INK

var _rect: TextureRect                 # 整张河面：圈里是水，圈外透明
var _mat: ShaderMaterial
var _group: Control                    # 题字的一组，摆在画面正中；淡出、缩小都以它的心为准
var _kicker: Label                     # 小字：第几关
var _name: Label                       # 大字：这一关的名字
var _rules: Array[ColorRect] = []      # 小字两边的两道细线
var _seal: Panel                       # 印章

var _phase := ""                       # 正在哪一段：cover 盖住、load 盖严着（中间换棋盘）、reveal 掀开；空是没在过渡
var _t0 := 0                           # 这一段开始的那一刻（微秒）
var _secs := 0.001                     # 这一段多长（秒）
var _ctx := {}                         # 这一段的说明
var _titled := false                   # 这一趟题不题字
var _seed := 0.0                       # 圈边起伏的相位：每一趟随手取一个，圈的形状不是回回一样
var _x_text := 0.0                     # 盖住这一段走到几分之几，主圈才淹到题字那一块；这以前小字不开始淡入
var _box := Rect2()                    # 题字（小字、大字、印章）在画面上占的一块（_group 里的坐标）
var _last_index := 0                   # 上一趟是第几关：只有真的过了上一关才题字
var _river := TITLE_RIVER              # 眼前这片水是按哪个底色染的（上一趟掀开完留下的）；不在游戏里的时侯当起点用
var _river_amount := 0.0
var _tint_from := TITLE_RIVER          # 这一段河面从哪个底色走到哪个底色（都是关卡底色本身，换算在 _apply 里）
var _tint_to := TITLE_RIVER
var _amount_from := 0.0
var _amount_to := 0.0
var _driving := false                  # 每帧算参数的那个循环是不是已经在走了

func build() -> void:
	_rect = add(full_rect(shader("ripple")), true)
	_rect.visible = false               # 预热是外面帮着做的（TransitionStyle.warm_up）；平时藏着，盖的时侯自己设回可见
	_mat = _rect.material as ShaderMaterial
	_build_card()

func cover(ctx: Dictionary) -> void:
	_begin(ctx, "cover", duration(ctx, COVER, FAST))
	_seed = randf_range(0.0, TAU)
	# 河面从哪儿走到哪儿：起点是上一趟留下的样子，终点是要去的那一关的水色。
	# 不用 ctx.color_from 当起点：换关的时侯它拿到的已经是新一关的底色了（main.load_level 先把 current_level 换成新一关才来盖）。
	# 在游戏里这两个数其实用不上：那儿河面每一帧直接跟着游戏里那条河此刻的水色走（见 _apply）
	_tint_from = _river
	_amount_from = _river_amount
	_tint_to = _aim(ctx)
	_amount_to = _amount(ctx)
	# 先判题不题字，再记下这一趟是第几关：反过来写的话就是拿自己比自己，永远不题
	_titled = _wants_title(ctx)
	if ctx.has("index"): _last_index = int(ctx["index"])
	_x_text = 0.0
	if _titled:
		_write_title(ctx)
		_x_text = _text_wait(ctx)
	_group.visible = _titled
	_start()
	await _until()
	_phase = "load"          # 盖严了。中间换棋盘的这一段河面不动，只有拖尾接着荡完（_apply 还在每帧走）

func reveal(ctx: Dictionary) -> void:
	_begin(ctx, "reveal", duration(ctx, REVEAL, FAST))
	_seed = randf_range(0.0, TAU)
	# 掀开这一段河面的颜色，接着盖住那一段走完的样子往下走（换关的时侯两头是同一个颜色；没盖过就掀的那一趟是标题页那条河）
	_tint_from = _tint_to
	_amount_from = _amount_to
	_tint_to = _aim(ctx)
	_amount_to = _amount(ctx)
	_start()
	await _until()
	_phase = ""
	_river = _tint_to
	_river_amount = _amount_to
	var main: Variant = ctx.get("main")
	if main != null and main.get("colors") != null: _river = main.colors.current_color      # 离开游戏的时侯河面是什么颜色
	_rect.visible = false
	_group.visible = false

# ================================================================ 每帧算一遍

func _begin(ctx: Dictionary, phase: String, secs: float) -> void:
	_phase = phase
	_t0 = Time.get_ticks_usec()
	_secs = maxf(secs, 0.001)
	_ctx = ctx

## 开始每帧算参数；已经在走了就不用再起一个
func _start() -> void:
	if _driving: return
	_driving = true
	_drive()

func _drive() -> void:
	var tree := ctl.get_tree()
	while _phase != "" and is_instance_valid(ctl):
		_apply()
		await tree.process_frame
	_driving = false

## 等这一段走完
func _until() -> void:
	var tree := ctl.get_tree()
	while _elapsed() < _secs:
		await tree.process_frame

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1000000.0

## 盖住：缓出，先快后慢
static func _opening(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)

## 掀开：缓入，先慢后快。开头多出来的那一段软边（SOFT）先走掉，圈一露头就在最远的那一角上动，不白等
static func _closing(u: float, far: float) -> float:
	return far * (1.0 - u * u) + SOFT * (1.0 - u) * (1.0 - u)

## 盖住的时侯的一圈拖尾：比主圈晚出生 delay（这一段的几分之几），然后照主圈的路子荡。越荡越淡，荡完正好没了。
## 返回（半径，亮度）；还没出生的是（-1, 0）
static func _opening_trail(x: float, delay: float, far: float) -> Vector2:
	if x <= delay: return Vector2(-1.0, 0.0)
	var q := clampf(x - delay, 0.0, 1.0)       # 它自己走到了几分之几
	return Vector2(far * _opening(q), smoothstep(0.0, 0.12, q) * (1.0 - q * q))

## 掀开的时侯的一圈拖尾：也比主圈晚出发一会儿，但和主圈同时收进脚下（它这一段短一些，所以快一些）；
## 快到的时候先淡掉，别和主圈挤成一点突然没了
static func _closing_trail(x: float, delay: float, far: float) -> Vector2:
	if x <= delay: return Vector2(-1.0, 0.0)
	var s := minf((x - delay) / maxf(1.0 - delay, 0.01), 1.0)
	return Vector2(_closing(s, far), smoothstep(0.0, 0.12, s) * (1.0 - smoothstep(0.7, 0.95, s)))

## 涟漪的心在画面上的什么地方：盖住的时侯是 from（主角踩上水车的地方），掀开的时侯是 to（主角落脚的地方）。
## 每帧都重新量：镜头平时一直在跟着主角挪，量一回就定死的话圈收到最后会对不准脚下
func _centre() -> Vector2:
	var world: Variant = _ctx.get("from" if _phase != "reveal" else "to")
	return screen_uv(world, Vector2(0.5, 0.5))

## 游戏里的圈有多扁：在游戏里是地上的圈，扁的；在标题页上是河面上的圈，圆的（标题页自己的涟漪就是圆的）
func _squash() -> float:
	return 1.0 if _ctx.get("main") == null else SQUASH

## 画面上的两点在"圈的单位"里隔多远（和着色器一个量法：等比坐标，再按扁的程度拉开）
static func _reach(from: Vector2, to: Vector2, asp: float, squash: float) -> float:
	return Vector2((to.x - from.x) * asp, (to.y - from.y) / squash).length()

## 从 at 到画面四个角最远的一角有多远。圈荡到这么大（外面再加上软边和起伏）一寸不漏
static func _far(at: Vector2, asp: float, squash: float) -> float:
	var best := 0.0
	for corner in [Vector2.ZERO, Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2.ONE]:
		best = maxf(best, _reach(at, corner, asp, squash))
	return best

## 主圈荡到题字那一块的最远一角，是盖住这一段的几分之几。主角站得离画面正中远的时侯圈要晚一点才淹到题字，
## 那就等淹到了再开始淡入，字不会浮在还没淹到的棋盘上
func _text_wait(ctx: Dictionary) -> float:
	var view := ctl.get_viewport().get_visible_rect().size
	var asp := view.x / maxf(view.y, 1.0)
	var squash := _squash()
	var at := screen_uv(ctx.get("from"), Vector2(0.5, 0.5))
	var need := 0.0
	for corner in [_box.position, Vector2(_box.end.x, _box.position.y), Vector2(_box.position.x, _box.end.y), _box.end]:
		need = maxf(need, _reach(at, (_group.position + corner) / view, asp, squash))
	need += SOFT + WOBBLE                                   # 软边和圈边的起伏都让出去才算淹严
	var far := _far(at, asp, squash) + SOFT + WOBBLE
	return 1.0 - pow(1.0 - clampf(need / far, 0.0, 1.0), 1.0 / 3.0)      # _opening 的反函数

## 游戏里一条河的水色。那条河是三维的着色器（stage_water.gdshader）：底色压暗，进到线性空间里往墨里压，画出来再变回 sRGB。
## 这里是二维的着色器，直接吃 sRGB，所以照它同一个算式算，末了把颜色变回 sRGB，淹上来的水和棋盘底下那条河才是同一种颜色
static func _river_of(level_color: Color) -> Color:
	return level_color.darkened(0.78).srgb_to_linear().lerp(WATER_INK, NIGHT).linear_to_srgb()

func _aim(ctx: Dictionary) -> Color:
	return ctx.color          # 关卡的底色本身（还没换算）。换算成画面上的水色只在 _apply 里做一回（_river_of）

## 在哪儿河面就染多重：在游戏里全染（这一关的水色），在标题页上不染（标题页那条河本来的颜色）。
## 看的是人在不在游戏里，不是 ctx 里有没有 level：从标题页进游戏那一趟掀开，说明里就没带这个键
##（SceneTransitionControl._context 只拿它推出底色，没写回去），可那时候人已经在游戏里了
static func _amount(ctx: Dictionary) -> float:
	return TINT if ctx.get("main") != null else 0.0

func _apply() -> void:
	var x := _elapsed() / _secs
	var view := ctl.get_viewport().get_visible_rect().size
	var asp := view.x / maxf(view.y, 1.0)
	var squash := _squash()
	var at := _centre()
	var far := _far(at, asp, squash) + SOFT + WOBBLE      # 主圈荡到这么大就盖严了
	var lag := LAG / _secs
	var front := far
	var rim := 0.0
	var trail := Vector4(-1.0, 0.0, -1.0, 0.0)
	if _phase == "reveal":
		var u := minf(x, 1.0)
		front = _closing(u, far)
		# 亮纹开头淡上来（圈在画面外头就有亮边了，一上来就是足亮的会在角上闪一下），收到脚下以前先淡掉
		rim = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.7, 1.0, u))
		var t1 := _closing_trail(x, lag, far)
		var t2 := _closing_trail(x, lag * 2.0, far)
		trail = Vector4(t1.x, t1.y * 0.55, t2.x, t2.y * 0.3)
	else:
		var u := minf(x, 1.0)
		front = far * _opening(u)
		rim = 1.0 - u                                   # 随扩散变淡，荡出画面正好淡完，盖严以后角上不留一道亮
		var t1 := _opening_trail(x, lag, far)
		var t2 := _opening_trail(x, lag * 2.0, far)
		trail = Vector4(t1.x, t1.y * 0.55, t2.x, t2.y * 0.3)

	# 可见每帧都设一回，而且延到这一帧的最后再设：外面预热完会把节点藏掉（TransitionStyle.warm_up）。
	# 开机掀幕现在由 SceneTransitionControl 等预热做完再掀，碰不上；可在游戏里换了样式以后头几帧就换关的话还是会撞上，
	# 它那一下"藏"会落在过渡的半道上。延后设，谁先谁后都盖得过它
	_rect.set_deferred("visible", true)
	_mat.set_shader_parameter("aspect", asp)
	_mat.set_shader_parameter("view_h", view.y)
	_mat.set_shader_parameter("center", at)
	_mat.set_shader_parameter("squash", squash)
	_mat.set_shader_parameter("front", front)
	_mat.set_shader_parameter("rim", rim)
	_mat.set_shader_parameter("trails", trail)
	_mat.set_shader_parameter("seed", _seed)
	var dyed := smoothstep(0.0, 1.0, minf(x, 1.0))
	# 在游戏里，河面每一帧就是游戏里那条河此刻的水色：连击的时侯它跟着灯的颜色走，换关的时侯它自己慢慢从旧的底色
	# 渐变到新的（每帧只挪一点点）。淹上来的水、掀到最后剩下的那一汪，和四周的水才永远是同一片。标题页上没有这条河，
	# 就从这一段开始的底色走到要去的底色
	var base := _tint_from.lerp(_tint_to, dyed)
	var main: Variant = _ctx.get("main")
	if main != null and main.get("colors") != null: base = main.colors.current_color
	var tint := _river_of(base)
	_mat.set_shader_parameter("water_tint", Vector3(tint.r, tint.g, tint.b))
	_mat.set_shader_parameter("tint_amount", lerpf(_amount_from, _amount_to, dyed))

	# 题字周围的水纹压下去多少：跟着小字淡入、跟着整组淡出；不题字的时侯是 0
	var calm := 0.0
	if _titled:
		_apply_text(x)
		calm = _kicker.modulate.a * _group.modulate.a
	_mat.set_shader_parameter("calm", calm)

## 题字：盖住的时侯小字、大字先后淡入，印章落下来；掀开的时侯整组跟着圈一起缩小、淡出
func _apply_text(x: float) -> void:
	if _phase == "reveal":
		var out := smoothstep(0.0, TEXT_OUT, minf(x, 1.0))
		_group.modulate.a = 1.0 - out
		_group.scale = Vector2.ONE * lerpf(1.0, 0.92, out)
		return
	_group.modulate = Color.WHITE
	_group.scale = Vector2.ONE
	var k0 := maxf(KICKER_AT, _x_text)
	var n0 := k0 + NAME_LATER
	_kicker.modulate.a = smoothstep(k0, k0 + TEXT_IN, x)
	for rule in _rules: rule.modulate.a = _kicker.modulate.a
	_name.modulate.a = smoothstep(n0, n0 + TEXT_IN, x)
	var drop := clampf((x - k0 - SEAL_LATER) * _secs / SEAL_DROP, 0.0, 1.0)
	_seal.scale = Vector2.ONE * lerpf(SEAL_BIG, 1.0, drop * drop)      # 越落越快
	_seal.modulate.a = clampf((x - k0 - SEAL_LATER) * _secs / 0.05, 0.0, 1.0)

# ================================================================ 题字

## 这一趟题不题字：只在真的过了上一关的时侯题（第几关比上一趟大）。重来、换难度、换场景、掀幕、对战都不题；
## 换关换得快的局（长夜、轮战）也不题，两段本来就短。
## 就地放的那一遍（debug_transition_test）没带第几关：在游戏里一定题（调样式用），在标题页上没字可题
func _wants_title(ctx: Dictionary) -> bool:
	var main: Variant = ctx.get("main")
	if not ctx.has("index"): return main != null
	if bool(ctx.get("fast", false)): return false
	if str(ctx.get("mode", "level")) != "level": return false
	if main != null and main.get("versus") != null: return false
	return int(ctx["index"]) > _last_index

func _build_card() -> void:
	_group = Control.new()
	_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.visible = false
	add(_group)
	_kicker = _make_text(KICKER_PX, JADE)
	_name = _make_text(NAME_PX, MOON)
	for i in 2:
		var rule := ColorRect.new()
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.color = Color(JADE.r, JADE.g, JADE.b, 0.55)
		rule.size = Vector2(RULE_W, 2.0)
		_group.add_child(rule)
		_rules.append(rule)
	_build_seal()

func _make_text(px: int, colour: Color) -> Label:
	var label := Tutorial.make_label(px, colour)
	# 字底下垫一点墨色的影：字是从水里浮上来的，不是贴在水面上的
	label.label_settings.shadow_color = Color(INK.r, INK.g, INK.b, 0.6)
	label.label_settings.shadow_offset = Vector2(0.0, 3.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_group.add_child(label)
	return label

## 一方朱红大印，上面是"守望"两个字。照着 opening.gd 的 _seal() 写的（那个是私有的，也不该动），按大字的大小小一号
func _build_seal() -> void:
	_seal = Panel.new()
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.80, 0.14, 0.10)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.95, 0.90, 0.82)
	_seal.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = "守\n望"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = Tutorial.FONT
	settings.font_size = 30
	settings.font_color = Color(0.97, 0.93, 0.86)
	settings.line_spacing = -5
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal.add_child(label)
	_group.add_child(_seal)

## 这一趟题什么字、摆在哪儿。一趟只调一次；之后每一帧只改透明度和大小（_apply_text）
func _write_title(ctx: Dictionary) -> void:
	var main: Variant = ctx.get("main")
	var index := int(ctx.get("index", 0))
	if index <= 0 and main != null: index = int(main.get("current_level_index")) + 1     # 就地放的那一遍没带第几关
	var night := main != null and bool(main.call("is_endless"))
	if night: _kicker.text = "第 %d 更" % index
	else: _kicker.text = "第 %d 关" % index
	_name.text = str(ctx.get("name", ""))
	var view := ctl.get_viewport().get_visible_rect().size
	# 摆版：大字横着居中，小字在它上面，印章落在它右下角。整组的高低按"小字的顶到大字的底"这一块的正中算，
	# 放在画面偏上一点的地方（正中看着偏低）；有印章在右边，整组往左挪一点才看着居中
	var name_w := Tutorial.text_width(_name.text, NAME_PX)
	var name_h := Tutorial.FONT.get_height(NAME_PX)
	var kicker_w := Tutorial.text_width(_kicker.text, KICKER_PX)
	var kicker_h := Tutorial.FONT.get_height(KICKER_PX)
	_name.size = Vector2(name_w, name_h)
	_name.position = Vector2(-name_w * 0.5, 0.0)
	_kicker.size = Vector2(kicker_w, kicker_h)
	_kicker.position = Vector2(-kicker_w * 0.5, -GAP - kicker_h)
	var rule_y := _kicker.position.y + kicker_h * 0.5 - 1.0
	_rules[0].position = Vector2(-kicker_w * 0.5 - RULE_GAP - RULE_W, rule_y)
	_rules[1].position = Vector2(kicker_w * 0.5 + RULE_GAP, rule_y)
	_seal.size = Vector2(SEAL_PX, SEAL_PX)
	_seal.pivot_offset = _seal.size * 0.5           # 落下来是冲着自己的心缩的
	_seal.position = Vector2(name_w * 0.5 + SEAL_GAP, name_h - SEAL_PX * 0.82)
	_group.position = Vector2(view.x * 0.5 - SEAL_PX * 0.2, view.y * 0.47 - (name_h - GAP - kicker_h) * 0.5)
	# 整组占了多大一块：主圈要淹到它的最远一角，字才能开始往外冒（_text_wait）
	var left := -kicker_w * 0.5 - RULE_GAP - RULE_W
	var right := maxf(kicker_w * 0.5 + RULE_GAP + RULE_W, name_w * 0.5 + SEAL_GAP + SEAL_PX)
	_box = Rect2(Vector2(left, -GAP - kicker_h), Vector2(right - left, GAP + kicker_h + name_h))
	# 刚开始什么都看不见
	for node in [_kicker, _name, _seal] + _rules:
		(node as CanvasItem).modulate.a = 0.0

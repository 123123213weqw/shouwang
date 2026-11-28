extends TransitionStyle
## 墨迹晕开：一滴墨落在水车那儿，在纸上晕开，吞掉棋盘；然后从主角落脚的地方化开、褪净，新的关卡从墨底下出来。
## 画面的全在着色器里（shaders/transition_ink.gdshader），这儿只管墨从哪儿开始、走多快、是什么颜色，再管题字。
##
## 盖住：front 从"一滴"走到 FRONT_END。先让那一滴在纸上停一下（LAND_SECS），再往外晕，用缓出。
## 掀开：hole 从 0 走到 FRONT_END，淡痕在最后褪掉。没盖过就直接掀（开机掀幕）也走得通：先让墨铺满，再化开。
## 题字：真的过了上一关的时侯，墨盖严前后那一瞬，画面正中用留白显一下要去的这一关的名字（见 _set_title）。
## 改长短改下面那几个数；改样子改着色器。

const SHADER := preload("res://shaders/transition_ink.gdshader")
const LAYER := preload("res://scripts/uis/transitions/transition_ink_layer.gd")   # 贴图节点的脚本：只放着调试用的 debug_pose
const FLOW: Texture2D = preload("res://assets/sprites/FlowMap.png")               # 纸纹，着色器要的

const INK := Color(0.02, 0.05, 0.05)      ## 墨色，和开场动画里那一滴同一种（opening.gd 的 INK）
const TINT := 0.1                        ## 墨里掺多少要去的这一关的底色
const FRONT_END := 1.05                  ## 前沿走到这儿算盖满、褪净（着色器里那个数在画面里最大是 1）
const DROP := 0.045                      ## 刚落下来的那一滴有多大（按"到最远那一角的距离"算）
const CENTRE := Vector2(0.5, 0.5)        ## 没有触发点的时侯（换场景、掀幕）从画面正中开始

const COVER_SECS := 0.50                 ## 盖住：平时的局、换得快的局
const COVER_FAST := 0.30
const LAND_SECS := 0.06                  ## 那一滴落下来先停这么久再晕开（换得快的局减半）
const REVEAL_SECS := 0.58                ## 掀开
const REVEAL_FAST := 0.30
## 盖住加掀开（中间换棋盘那 0.1 秒出头不算）一共 1.1 秒上下，别再长：tools/playtest/steps_transition.txt 是在过渡开始
## 1.3 秒上下截图的（call 一步等 1 秒、再 sleep 0.3），截图那一帧本身要 30 毫秒以上；过渡拖过了那一刻，量帧时间的
## 时候就会把截图算成"掀开的时候卡了一下"。要拖节奏也不该在这儿拖

const TENDRILS := 6                     ## 一圈里几缕长的须（和着色器里的 TENDRILS、那两个数组的大小要对上）

const PAPER := Color(0.88, 0.85, 0.74)     ## 留白的纸色（宣纸，比开场动画里的纸暗一点：这是夜里）
const TITLE_BIG := 76                   ## 题字：关卡名多大
const TITLE_SMALL := 30                 ##       上面那一小行"第 N 关"多大
const TITLE_AT := 0.20                  ## 盖住开始这么久以后题字（那时墨已经把画面正中吞掉了）
const TITLE_IN := 0.18                  ##       用多久显出来
const TITLE_OUT := 0.14                 ##       掀开的时侯用多久褪掉

var rect: TextureRect
var _mat: ShaderMaterial
var _tween: Tween
var _ink_from := INK                   ## 盖住那一滴的墨色：掺的是离开的那一关的底色
var _ink_to := INK                     ## 盖严了、掀开的时侯的墨色：掺的是要去的那一关的底色
var _title: Control                     ## 题字：一小行"第 N 关"，底下一个大字是关卡名，后面衬着一圈洇开的淡墨。平时藏着
var _title_small: Label
var _title_big: Label
var _halo: Label
var _last_index := 0                    ## 上一趟是第几关：只往后的关才题
var _title_tween: Tween

func build() -> void:
	rect = full_rect(SHADER)
	rect.set_script(LAYER)                 # 在加进场景树以前换上：和直接用那个脚本建节点是一回事
	rect.visible = false                   # 预热是外面帮着做的（warm_up 会临时让它可见）；平时藏着，盖的时候自己设回可见
	_mat = rect.material as ShaderMaterial
	_mat.set_shader_parameter("texture_flow_map", FLOW)
	add(rect, true)
	rect.set("ink", self)                  # 那个脚本里的 ink 不是 TextureRect 自带的，只能这么给
	# 题字也在这儿建好（过渡途中不新建节点）：一个跟着整张画面的空节点，字挂在它下面，淡入淡出只动它一个
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.visible = false
	_halo = Tutorial.make_label(TITLE_BIG + 16, Color(0.36, 0.42, 0.40, 0.55))   # 留白周围那圈薄墨：比字大一圈的一层淡的
	_title_big = Tutorial.make_label(TITLE_BIG, PAPER)
	_title_small = Tutorial.make_label(TITLE_SMALL, Color(PAPER.r, PAPER.g, PAPER.b, 0.66))
	for l in [_halo, _title_big, _title_small]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.add_child(l)
	add(_title)

## 盖住。from 平时是主角这会儿站的地方（踩上水车的那一格）；换场景的时侯没有，就从画面正中晕。
## 墨色跟着墨一起走：落下来的那一滴掺的是离开的那一关的底色，晕开的过程中换成要去的那一关的
##（一章里的几关底色一样，看不出换；换章的时侯墨色会跟着变）
func cover(ctx: Dictionary) -> void:
	_begin(screen_uv(ctx.from, CENTRE), ctx)
	var land := _land(ctx)
	_tween = ctl.create_tween()
	_tween.tween_interval(land)           # 那一滴先落定
	_tween.tween_method(_cover_at, 0.0, 1.0, _secs(ctx, COVER_SECS, COVER_FAST) - land)
	_set_title(ctx)                       # 该题字的话，墨把正中吞掉以后字从墨里显出来
	await _tween.finished
	_cover_at(1.0)                         # 保险：做完的这一帧必须已经盖严

## 掀开。to 是主角落脚的地方；回标题页、掀幕的时侯没有，就从画面正中化开
func reveal(ctx: Dictionary) -> void:
	var colour: Color = ctx.get("color", SceneTransitionControl.INK)
	_ink_to = INK.lerp(colour, TINT)          # 开机掀幕没盖过：这儿的墨色是现定的
	_mat.set_shader_parameter("ink", _ink_to)
	_mat.set_shader_parameter("revealing", 1.0)
	_mat.set_shader_parameter("front", FRONT_END)      # 开机掀幕没盖过：这一帧先铺满，下一帧才开始化开
	_mat.set_shader_parameter("origin", screen_uv(ctx.to, CENTRE))
	_set_seed(randf() * 20.0)                          # 化开的形状和晕开的不是一套
	_last_index = int(ctx.get("index", _last_index))     # 开机第一关没经过盖住，关号在这儿记
	if _title.visible:                     # 题着的字跟着墨一起褪
		_kill_title_tween()
		_title_tween = ctl.create_tween()
		_title_tween.tween_property(_title, "modulate:a", 0.0, TITLE_OUT)
	_tween = ctl.create_tween()
	_tween.tween_method(_reveal_at, 0.0, 1.0, _secs(ctx, REVEAL_SECS, REVEAL_FAST))
	await _tween.finished
	_reveal_at(1.0)
	_tween = null
	_reset()
	rect.visible = false
	_kill_title_tween()
	_title.modulate.a = 0.0
	_title.visible = false

## 换样式的时候把题字的补间也收走
func dispose() -> void:
	_kill_title_tween()
	super()

## 这一趟题不题字、题什么。只题真的往前过的关（关号比上一趟大）、不是换得快的局、不是对战：
## 重来、换难度、长夜、轮战换棋盘都不题——和涟漪那一种一个规矩。换场景、掀幕没有"上一关"，也不题
func _set_title(ctx: Dictionary) -> void:
	var index := int(ctx.get("index", 0))
	var main := ctx.get("main") as Main
	var level_name := str(ctx.get("name", ""))
	var on := (
		str(ctx.get("mode", "level")) == "level" and not bool(ctx.get("fast", false))
		and index > _last_index and level_name != "" and main != null and main.versus == null
	)
	_last_index = index                   # 记的是上一趟：往回走过一关再往前过，照样题
	_kill_title_tween()
	_title.modulate.a = 0.0
	_title.visible = on
	if not on: return
	_title_big.text = level_name
	_title_small.text = "第 %d 关" % index
	var size := ctl.get_viewport().get_visible_rect().size
	_centre(_title_big, size, 0.47)
	_centre(_halo, size, 0.47)
	_centre(_title_small, size, 0.47 - (TITLE_BIG * 0.62 + TITLE_SMALL) / size.y)
	_title_tween = ctl.create_tween()
	_title_tween.tween_interval(TITLE_AT)
	_title_tween.tween_property(_title, "modulate:a", 1.0, TITLE_IN)

## 把一行字摆在画面横着的正中、竖着的 at 那么高
func _centre(l: Label, size: Vector2, at: float) -> void:
	# 用 get_minimum_size：字刚换过，节点自己的 size 要到下一帧排版时才跟上
	l.position = Vector2(size.x * 0.5, size.y * at) - l.get_minimum_size() / 2.0

func _kill_title_tween() -> void:
	if _title_tween != null and _title_tween.is_valid(): _title_tween.kill()
	_title_tween = null

## 排查用：把墨冻在盖住（phase 1）或者掀开（phase 2）走到千分之 step 的那一帧，长短按平时的局算。
## 落点给成画面的百分之 ox、oy；ox 给负数就用主角这会儿站的地方。phase 0 是收起来。见 transition_ink_layer.gd
func debug_pose(phase: int, step: int, ox: int, oy: int) -> String:
	if phase == 0:
		if _tween != null and _tween.is_valid(): _tween.kill()
		_tween = null
		_reset()
		rect.visible = false
		ctl.visible = false
		return "墨收起来了"
	var main := ctl.get_node_or_null("/root/Main") as Main
	var where: Variant = main.character.global_position if main != null and is_instance_valid(main.character) else null
	var at := screen_uv(where, CENTRE) if ox < 0 else Vector2(float(ox) / 100.0, float(oy) / 100.0)
	var level: Variant = main.current_level if main != null else null
	_begin(at, {"color": level.base_color if level != null else SceneTransitionControl.INK})
	var x := clampf(float(step) / 1000.0, 0.0, 1.0)
	ctl.visible = true                     # 平时这一整层是藏着的（open 才让它露面）
	if phase == 1:
		_cover_at(clampf((x * COVER_SECS - LAND_SECS) / (COVER_SECS - LAND_SECS), 0.0, 1.0))
		return "墨冻在盖住的第 %d 千分位，从 (%.2f, %.2f) 晕开" % [step, at.x, at.y]
	_mat.set_shader_parameter("revealing", 1.0)
	_mat.set_shader_parameter("front", FRONT_END)
	_reveal_at(x)
	return "墨冻在掀开的第 %d 千分位，从 (%.2f, %.2f) 化开" % [step, at.x, at.y]

## 这一趟的开头：落点、墨色、形状，都回到"一滴刚落下"
func _begin(at: Vector2, ctx: Dictionary) -> void:
	var size := ctl.get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", size.x / size.y)
	_mat.set_shader_parameter("origin", at)
	var colour: Color = ctx.get("color", SceneTransitionControl.INK)
	_ink_to = INK.lerp(colour, TINT)
	_ink_from = INK.lerp(ctx.get("color_from", colour), TINT)
	_set_seed(randf() * 20.0)
	_mat.set_shader_parameter("revealing", 0.0)
	_mat.set_shader_parameter("hole", 0.0)
	_mat.set_shader_parameter("residue", 1.0)
	_cover_at(0.0)                        # 第一帧就看得见那一滴
	rect.visible = true

## 这一趟的形状：换一个 seed，顺带把几缕须的角度、长短、弯势按它算出来交给着色器。
## 这几样只跟 seed 有关、整张画面一样，在着色器里逐像素算的话每个像素要多算 6 次正弦余弦、24 个随机数（掌机上贵）
func _set_seed(seed_value: float) -> void:
	_mat.set_shader_parameter("seed", seed_value)
	var shape := PackedVector4Array()
	var bend := PackedFloat32Array()
	shape.resize(TENDRILS)
	bend.resize(TENDRILS)
	for i in TENDRILS:
		var k := float(i) + 0.5
		var ang := _hash21(k + 11.0, seed_value + 11.0) * TAU
		var base := lerpf(0.035, 0.11, _hash21(k + 37.0, seed_value + 37.0))
		var skew := _hash21(k + 71.0, seed_value + 71.0) - 0.5
		shape[i] = Vector4(cos(ang), sin(ang), base, skew)
		bend[i] = _hash21(k + 53.0, seed_value + 53.0) - 0.5
	_mat.set_shader_parameter("tendril_shape", shape)
	_mat.set_shader_parameter("tendril_bend", bend)

## 和着色器里的 hash21 是同一个式子（格点上的随机数，0 到 1）。着色器里是单精度，这儿是双精度，
## 算出来的数不完全一样——须的角度本来就是每趟随机的，差一点看不出来
static func _hash21(x: float, y: float) -> float:
	var p := Vector3(x, y, x) * 0.1031
	p = Vector3(fposmod(p.x, 1.0), fposmod(p.y, 1.0), fposmod(p.z, 1.0))
	# 着色器里是 p3 += dot(p3, p3.yzx + 33.33)：向量加减一个数、加上一个数，都是每个分量各自算
	p += Vector3.ONE * p.dot(Vector3(p.y + 33.33, p.z + 33.33, p.x + 33.33))
	return fposmod((p.x + p.y) * p.z, 1.0)

## 回到"还没开始"：整张透明
func _reset() -> void:
	_mat.set_shader_parameter("revealing", 0.0)
	_mat.set_shader_parameter("front", 0.0)
	_mat.set_shader_parameter("hole", 0.0)
	_mat.set_shader_parameter("residue", 1.0)

func _land(ctx: Dictionary) -> float:
	return LAND_SECS * 0.5 if bool(ctx.get("fast", false)) else LAND_SECS

func _secs(ctx: Dictionary, normal: float, fast: float) -> float:
	return duration(ctx, normal, fast)

## 盖住晕开的那一段走到 t（0 到 1）。先提速后减速：那一滴停了一下才"化开"，然后越晕越慢、往角里渗
func _cover_at(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - pow(t, 1.6), 2.0)
	_mat.set_shader_parameter("front", lerpf(DROP, FRONT_END, eased))
	_mat.set_shader_parameter("ink", _ink_from.lerp(_ink_to, t))

## 掀开走到 x（0 到 1）：洞慢慢化开、越化越快；淡痕在后半段褪掉。
## 起头别太慢：盖严到洞露脸之间画面是不动的墨，那段越短越好
func _reveal_at(x: float) -> void:
	x = clampf(x, 0.0, 1.0)
	var eased := lerpf(x, x * x * (3.0 - 2.0 * x), 0.45)
	_mat.set_shader_parameter("hole", eased * FRONT_END)
	_mat.set_shader_parameter("residue", 1.0 - smoothstep(0.5, 1.0, x))

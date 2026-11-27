extends TransitionStyle
## 墨迹晕开：一滴墨落在水车那儿，在纸上晕开，吞掉棋盘；然后从主角落脚的地方化开、褪净，新的关卡从墨底下出来。
## 画面的全在着色器里（shaders/transition_ink.gdshader），这儿只管三件事：墨从哪儿开始、走多快、是什么颜色。
##
## 盖住：front 从"一滴"走到 FRONT_END。先让那一滴在纸上停一下（LAND_SECS），再往外晕，用缓出。
## 掀开：hole 从 0 走到 FRONT_END，淡痕在最后褪掉。没盖过就直接掀（开机掀幕）也走得通：先让墨铺满，再化开。
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

var rect: TextureRect
var _mat: ShaderMaterial
var _tween: Tween

func build() -> void:
	rect = full_rect(SHADER)
	rect.set_script(LAYER)                 # 在加进场景树以前换上：和直接用那个脚本建节点是一回事
	rect.visible = false                   # 预热是外面帮着做的（warm_up 会临时让它可见）；平时藏着，盖的时候自己设回可见
	_mat = rect.material as ShaderMaterial
	_mat.set_shader_parameter("texture_flow_map", FLOW)
	add(rect, true)
	rect.set("ink", self)                  # 那个脚本里的 ink 不是 TextureRect 自带的，只能这么给

## 盖住。from 平时是主角这会儿站的地方（踩上水车的那一格）；换场景的时侯没有，就从画面正中晕
func cover(ctx: Dictionary) -> void:
	_begin(screen_uv(ctx.from, CENTRE), ctx)
	var land := _land(ctx)
	_tween = ctl.create_tween()
	_tween.tween_interval(land)           # 那一滴先落定
	_tween.tween_method(_cover_at, 0.0, 1.0, _secs(ctx, COVER_SECS, COVER_FAST) - land)
	await _tween.finished
	_cover_at(1.0)                         # 保险：做完的这一帧必须已经盖严

## 掀开。to 是主角落脚的地方；回标题页、掀幕的时侯没有，就从画面正中化开
func reveal(ctx: Dictionary) -> void:
	_mat.set_shader_parameter("revealing", 1.0)
	_mat.set_shader_parameter("front", FRONT_END)      # 开机掀幕没盖过：这一帧先铺满，下一帧才开始化开
	_mat.set_shader_parameter("origin", screen_uv(ctx.to, CENTRE))
	_mat.set_shader_parameter("seed", randf() * 20.0)   # 化开的形状和晕开的不是一套
	_tween = ctl.create_tween()
	_tween.tween_method(_reveal_at, 0.0, 1.0, _secs(ctx, REVEAL_SECS, REVEAL_FAST))
	await _tween.finished
	_reveal_at(1.0)
	_tween = null
	_reset()
	rect.visible = false

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
	_mat.set_shader_parameter("peek", 0)
	if phase >= 3:                         # 排查用（临时）：phase 3 起把中间量画成灰度，全盖住的状态
		_mat.set_shader_parameter("peek", phase - 2)
		_cover_at(1.0)
		return "看中间量 %d" % (phase - 2)
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
	_mat.set_shader_parameter("ink", INK.lerp(colour, TINT))
	_mat.set_shader_parameter("seed", randf() * 20.0)
	_mat.set_shader_parameter("revealing", 0.0)
	_mat.set_shader_parameter("hole", 0.0)
	_mat.set_shader_parameter("residue", 1.0)
	_cover_at(0.0)                        # 第一帧就看得见那一滴
	rect.visible = true

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

## 掀开走到 x（0 到 1）：洞慢慢化开、越化越快；淡痕在后半段褪掉
func _reveal_at(x: float) -> void:
	x = clampf(x, 0.0, 1.0)
	var eased := lerpf(x, x * x * (3.0 - 2.0 * x), 0.6)
	_mat.set_shader_parameter("hole", eased * FRONT_END)
	_mat.set_shader_parameter("residue", 1.0 - smoothstep(0.5, 1.0, x))

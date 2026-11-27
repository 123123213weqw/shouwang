extends TransitionStyle
## 「镜头钻进水车」：踩上水车换关的那一下，镜头朝水车推过去（不转，水车在眼前越转越大），水从四面涌到水车那儿盖严——
## 眼前进了水里。再出来时已经是新的一关：水破开、退下去，镜头从贴着水面的低位拉回平时的机位。
## 没有水车可推的场合（换场景、开机掀幕、重来、换难度、对战换棋盘）和换关换得快的局（fast）只做水层，不动镜头。
## 画面全在 shaders/transition_wheel.gdshader 里；这儿管的是两段的进度和镜头的借与还。
## 镜头的算法在 main.gd（fit_camera、camera_target_x），这儿不改它，只读它算出来的数、照着算一遍。

# ---- 时长（秒）
const COVER := 0.45          # 盖住：镜头在动的这一段不能再长（掌机离眼睛近）
const REVEAL := 0.5          # 掀开
const REVEAL_DIVE := 0.45    # 镜头往回拉的那一种掀开
const FAST := 0.25           # 换关换得快的局，两段各这么长

# ---- 镜头。掌机离眼睛近，这几样都是往小了收的：不转镜头，推进的距离最多七成，视角最多变 25 度
const PUSH := 0.6            # 盖住：镜头朝水车推过去多少（现在到水车的几成）
const PINCH := 14.0          # 盖住：视角收窄多少度
const LOW := 0.3             # 掀开：镜头从多低的地方拉回来（平时到棋盘平面的距离的几成）
const WHEEL_HEIGHT := 0.7    # 水车的轴心离格子多高：镜头朝那儿推，水最后盖住的也是画面上的那一点
const WATCHDOG := 0.6        # 看门狗：这一段该做完以后再过这么久镜头还没还回去，就不管中间出了什么事，先还回去

var rect: TextureRect
var _mat: ShaderMaterial

var _cam: Camera3D           # 借着的镜头；没借的时侯是空的
var _home := Vector3.ZERO    # 镜头该回到哪儿
var _fov := 0.0              # 平时的视角（度）。头一回借镜头的时侯记下来
var _dived := false          # 盖住的时侯镜头推进过水车：掀开的时侯要从低位拉回来
var _armed := 0              # 看门狗的号：0 是没借镜头
var _watch: SceneTreeTimer
var _watch_call: Callable

func build() -> void:
	rect = add(full_rect(shader("wheel")), true)
	rect.visible = false          # 预热是外面帮着做的；平时藏着，盖的时候自己设回可见
	_mat = rect.material as ShaderMaterial

func cover(ctx: Dictionary) -> void:
	_begin(ctx, 0.0, 0.0)                            # 还没有水
	_dived = false
	var secs := duration(ctx, COVER, FAST)
	var t := ctl.create_tween().set_parallel(true)
	t.tween_property(_mat, "shader_parameter/cover", 1.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var portal := _wheel(ctx)                        # 这趟是不是踩着水车换的关
	if portal != null:
		_dived = true
		_dive(ctx, portal, t, secs)
	t.chain().tween_callback(_give_back)             # 还镜头写在补间里：中间哪一步出了错，补间自己也会做完
	await t.finished
	_give_back()

func reveal(ctx: Dictionary) -> void:
	_begin(ctx, 1.0, 0.0)                            # 盖严的；掀幕那一趟没盖过，也是从盖严的开始
	var surfacing := _dived
	_dived = false
	var secs := duration(ctx, REVEAL, FAST)
	if surfacing: secs = minf(secs, REVEAL_DIVE)
	var t := ctl.create_tween().set_parallel(true)
	t.tween_property(_mat, "shader_parameter/drain", 1.0, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if surfacing: _surface(ctx, t, secs)
	t.chain().tween_callback(_give_back)
	await t.finished
	_give_back()
	_mat.set_shader_parameter("cover", 0.0)          # 回到什么都看不见
	_mat.set_shader_parameter("drain", 0.0)
	rect.visible = false

## 换样式的时侯：正借着的镜头先还回去（过渡中间不会换样式，以防万一）
func dispose() -> void:
	_give_back()
	super()

## 每一段开头：把这一趟的数交给着色器
func _begin(ctx: Dictionary, wet_from: float, drain_from: float) -> void:
	rect.visible = true
	var size := ctl.get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_mat.set_shader_parameter("tint", ctx.get("color"))
	_mat.set_shader_parameter("seed", randf())
	_mat.set_shader_parameter("cover", wet_from)
	_mat.set_shader_parameter("drain", drain_from)

## 这一趟盖住是不是踩着水车换的关（主角就站在水车上）。是的话把水车交回去，不然交回空的：
## fast 的局、换场景、掀幕、重来、换难度、对战换棋盘都没有水车可推，只做水层
func _wheel(ctx: Dictionary) -> Node3D:
	if str(ctx.get("mode", "level")) != "level" or bool(ctx.get("fast", false)): return null
	var main: Main = ctx.get("main")
	if main == null or not is_instance_valid(main.end_portal_instance): return null
	var portal := main.end_portal_instance
	var from: Variant = ctx.get("from")
	if not (from is Vector3): return null
	var stood: Vector3 = from
	if stood.distance_to(portal.global_position) > main.grid.tile_size.x * 0.5: return null
	return portal

## 盖住的镜头：从现在的位置朝水车的轴心推过去（不转），视角收一点
func _dive(ctx: Dictionary, portal: Node3D, t: Tween, secs: float) -> void:
	var main: Main = ctx.main
	var cam: Camera3D = main.camera_3d
	var aim := portal.global_position + Vector3.UP * WHEEL_HEIGHT
	var where := screen_uv(aim)
	_mat.set_shader_parameter("focus", Vector2(clampf(where.x, 0.3, 0.7), clampf(where.y, 0.3, 0.7)))
	if _fov <= 0.0: _fov = cam.fov
	_borrow(cam, cam.global_position, secs)
	t.tween_property(cam, "global_position", cam.global_position.lerp(aim, PUSH), secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(cam, "fov", _fov - PINCH, secs)

## 掀开的镜头：从贴着水面的低位拉回平时的机位。平时的高低远近是 main.fit_camera() 按新棋盘定的，
## 左右是 camera_target_x() 定的——load_level 在调 close() 之前已经照这两样把镜头摆好了。这儿不拿镜头现在的位置当机位
##（万一被谁挪过呢），照同一个算法再算一遍
func _surface(ctx: Dictionary, t: Tween, secs: float) -> void:
	var main: Main = ctx.get("main")
	if main == null or not is_instance_valid(main.camera_3d): return
	var cam: Camera3D = main.camera_3d
	var fwd: Vector3 = main.camera_forward
	var home := cam.global_position
	if main.camera_dist > 0.0:
		home = Vector3(main.camera_target_x(), -fwd.y * main.camera_dist, main.camera_focus_z - fwd.z * main.camera_dist)
	var low := Vector3(home.x, 0.0, main.camera_focus_z) - fwd * (main.camera_dist * LOW)
	_borrow(cam, home, secs)
	cam.global_position = low                  # 画面盖严着，这一下看不见
	t.tween_property(cam, "global_position", home, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 借镜头：记下它该回到哪儿，按住它不让跟着主角走，再上一个闹钟（看门狗）
func _borrow(cam: Camera3D, home: Vector3, secs: float) -> void:
	_cam = cam
	_home = home
	_armed += 1
	hold_camera(true)
	_watch = ctl.get_tree().create_timer(secs + WATCHDOG)
	_watch_call = _expired.bind(_armed)
	_watch.timeout.connect(_watch_call)

## 看门狗响了：这一段早该做完了，镜头还没还回去（补间没做完，或者样式里哪一步出了错），现在还
func _expired(id: int) -> void:
	if id != _armed: return          # 以前哪一段留下的闹钟
	_give_back()

## 还镜头：位置和视角都回去，放开它。只还一次；没借的时侯什么都不做
func _give_back() -> void:
	if _armed == 0: return
	_armed = 0
	if _watch != null and _watch.timeout.is_connected(_watch_call): _watch.timeout.disconnect(_watch_call)
	_watch = null
	if is_instance_valid(_cam):
		_cam.global_position = _home
		_cam.fov = _fov
	_cam = null
	hold_camera(false)

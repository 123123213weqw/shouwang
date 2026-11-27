extends TransitionStyle
## 「镜头钻进水车」：踩上水车换关的那一下，主角沉进水车里（水车本来就是过关的门），镜头朝水车推过去（不转），
## 水车在眼前越转越大，水从四面漫上来盖严——眼前进了水里。再出来时已经是新的一关：水线往下滑掉，镜头从贴着水面的低位拉回平时的机位。
## 没有水车可推的场合（换场景、开机掀幕、重来、换难度、对战换棋盘）和换关换得快的局（fast）只做水层，不动镜头。
## 画面全在 shaders/transition_wheel.gdshader 里；这儿管的是两段的进度，和借走的东西（镜头、主角）怎么还。
## 镜头的算法在 main.gd（fit_camera、camera_target_x），这儿不改它，只读它算出来的数、照着算一遍。

# ---- 时长（秒）
const COVER := 0.45          # 盖住（只做水层的那些场合）
const COVER_DIVE := 0.42     # 踩水车的那一种盖住：镜头在动，短一点才量得准不超过 0.45 秒
const REVEAL := 0.5          # 掀开（只做水层的那些场合）
const REVEAL_DIVE := 0.42    # 镜头往回拉的那一种掀开
const FAST := 0.3            # 换关换得快的局，两段各这么长。不能定成 0.25：量出来总比设定的短一点，会判"不到 0.25 秒"

# ---- 主角沉进水车
const FADE := 0.14           # 多久淡没。要在水漫到它之前沉完，水车才露得出来说话
const SINK := 0.22           # 往下沉用多久
const SINK_DEPTH := 0.9      # 沉多深（世界单位）
const SUNK := Color(0.62, 0.90, 0.88)   # 沉下去的时侯头上染的水色（红让水吸掉了）。水车是白的，这样两个分得开

# ---- 镜头。掌机离眼睛近，这几样都是往小了收的：不转镜头，推进的距离最多七成，视角最多变 25 度
const PUSH := 0.6            # 盖住：镜头朝水车推过去多少（现在到水车的几成）
const PINCH := 14.0          # 盖住：视角收窄多少度
const LOW := 0.3             # 掀开：镜头从多低的地方拉回来（平时到棋盘平面的距离的几成）
const WHEEL_HEIGHT := 0.7    # 水车的轴心离格子多高：镜头朝那儿推，水最后盖住的也是画面上的那一点
const SPIN := 0.75           # 盖住：水车在这一段里比平时多转几圈（转太快在 60 帧上看是一顿一顿的，别加多）
const ZOOM := 0.15           # 焦散的网跟着镜头放大多少（见着色器里的 zoom）

const WATCHDOG := 0.6        # 看门狗：这一段该做完以后再过这么久，不管中间出了什么事，把借走的东西还回去

var rect: TextureRect
var _mat: ShaderMaterial

var _cam: Camera3D           # 借着的镜头；没借过是空的
var _who: Character          # 借着的主角（推进水车的时侯让它沉进水车里）
var _home := Vector3.ZERO    # 镜头该回到哪儿
var _fov := 0.0              # 平时的视角（度）。头一回借镜头的时侯记下来
var _head_alpha := 1.0       # 主角的头、身子、影子、头顶的步数原来各画得多实：还的时侯照这些数还
var _body_alpha := 1.0
var _shadow_alpha := 1.0
var _moves_alpha := 1.0
var _held_alpha := 1.0
var _box_y := 0.0            # 主角那团精灵在它自己坐标系里的高度：平时是 0，跳起来的时侯游戏在改它
var _head_tint := Color.WHITE        # 头原来的颜色
var _dived := false          # 盖住的时侯镜头推进过水车：掀开的时候要从低位拉回来
var _armed := 0              # 这是第几次借东西：0 是没借。补间和看门狗回头来还的时侯带着自己那一次的号，对不上就不动
var _tween: Tween            # 这一次借东西用的补间

func build() -> void:
	# 登记预热：开机时这一层在黑幕底下先白画两帧。早先开机不登记（那会儿底座的开机掀幕要等预热，黑幕却先撤了，
	# 标题页会裸露两帧）；后来底座改成黑幕等预热完再撤，而且平时是几种样式随机的——不预热的话，这一层要等到头一回
	# 抽到它才头一回画，着色器还没编译，盖住时补间的 shader_parameter/zoom 在材质上还不存在（报错，那一段不动）
	rect = add(full_rect(shader("wheel")), true)
	rect.visible = false          # 平时藏着，盖的时候自己设回可见
	_mat = rect.material as ShaderMaterial

func cover(ctx: Dictionary) -> void:
	_begin(ctx, 0.0, 0.0, true)                      # 还没有水；水色按要去的这一关定
	_dived = false
	var portal := _wheel(ctx)                        # 这趟是不是踩着水车换的关
	var secs := duration(ctx, COVER, FAST)
	if portal != null: secs = minf(secs, COVER_DIVE)
	var t := ctl.create_tween().set_parallel(true)
	# 水：先慢慢从边上漫进来，越涌越快。和推镜头是叠着走的，不是一前一后两件事
	t.tween_property(_mat, "shader_parameter/cover", 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_mat, "shader_parameter/zoom", 1.0 + (ZOOM if portal != null else 0.03), secs)
	if portal != null:
		_dived = true
		_dive(ctx, portal, t, secs)
	t.chain().tween_callback(_give_back.bind(true, _armed))   # 还东西写在补间里：中间哪一步出了错，补间自己也会做完
	await t.finished
	_give_back()

func reveal(ctx: Dictionary) -> void:
	# 盖严的；掀幕那一趟没盖过，也是从盖严的开始。水色沿用盖住时定的那一个：盖严着的那一会儿画面是看得见的，
	# 这会儿再换一次色，水底会跳一下（换场景的时侯盖住那头还不知道要去哪一关，两头取到的本来就不是同一个色）
	var boot := str(ctx.get("mode", "level")) == "boot"
	_begin(ctx, 1.0, 0.0, boot)
	if boot:
		# 开机掀幕从第一帧就开始了，这会儿画面是一整片水底。外面那块黑幕要过三帧才撤（SceneManager._drop_boot_cover_soon）：
		# 等它撤了再放水线，水线才是从头走到底的
		for i in 3: await ctl.get_tree().process_frame
		rect.visible = true
	var surfacing := _dived
	_dived = false
	var secs := duration(ctx, REVEAL, FAST)
	if surfacing: secs = minf(secs, REVEAL_DIVE)
	_mat.set_shader_parameter("zoom", 1.0 + (ZOOM * 2.0 if surfacing else 0.06))
	var t := ctl.create_tween().set_parallel(true)
	# 水线往下滑。快慢的曲线在着色器里（先慢后快），这儿匀着走就行：最后那一丝不能在底边拖着不走
	t.tween_property(_mat, "shader_parameter/drain", 1.0, secs)
	t.tween_property(_mat, "shader_parameter/zoom", 1.0, secs)
	if surfacing: _surface(ctx, t, secs)
	t.chain().tween_callback(_give_back.bind(true, _armed))
	await t.finished
	_give_back()
	_mat.set_shader_parameter("cover", 0.0)          # 回到什么都看不见
	_mat.set_shader_parameter("drain", 0.0)
	_mat.set_shader_parameter("zoom", 1.0)
	rect.visible = false

## 换样式的时侯：正借着的东西先还回去（过渡中间不会换样式，以防万一）
func dispose() -> void:
	_give_back()
	super()

## 每一段开头：把这一趟的数交给着色器。tint_now = true 才重新取水色（见 cover、reveal）
func _begin(ctx: Dictionary, wet_from: float, drain_from: float, tint_now: bool) -> void:
	rect.visible = true
	var size := ctl.get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	if tint_now: _mat.set_shader_parameter("tint", ctx.get("color"))
	_mat.set_shader_parameter("seed", randf())
	_mat.set_shader_parameter("cover", wet_from)
	_mat.set_shader_parameter("drain", drain_from)
	_mat.set_shader_parameter("focus", Vector2(0.5, 0.5))

## 这一趟盖住是不是踩着水车换的关（主角就站在水车上）。是的话把水车交回去，不然交回空的：
## fast 的局、换场景、掀幕、重来、换难度、对战换棋盘都没有水车可推，只做水层
func _wheel(ctx: Dictionary) -> Portal:
	if str(ctx.get("mode", "level")) != "level" or bool(ctx.get("fast", false)): return null
	var main: Main = ctx.get("main")
	if main == null or not is_instance_valid(main.end_portal_instance): return null
	var portal := main.end_portal_instance
	var from: Variant = ctx.get("from")
	if not (from is Vector3): return null
	var stood: Vector3 = from
	if stood.distance_to(portal.global_position) > main.grid.tile_size.x * 0.5: return null
	return portal

## 盖住：主角沉进水车里，水车露出来转；镜头从现在的位置朝水车的轴心推过去（不转），视角收一点
func _dive(ctx: Dictionary, portal: Portal, t: Tween, secs: float) -> void:
	var main: Main = ctx.main
	var cam: Camera3D = main.camera_3d
	var aim := portal.global_position + Vector3.UP * WHEEL_HEIGHT
	var where := screen_uv(aim)
	_mat.set_shader_parameter("focus", Vector2(clampf(where.x, 0.3, 0.7), clampf(where.y, 0.3, 0.7)))
	if _fov <= 0.0: _fov = cam.fov
	_borrow(main, cam, cam.global_position, secs, t)
	# 先记下要还的数，再动东西（上面 _borrow）。镜头：去的时候由快到慢，像冲过去以后停住
	t.tween_property(cam, "global_position", cam.global_position.lerp(aim, PUSH), secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(cam, "fov", _fov - PINCH, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 主角沉进水车：往下沉、头上染一层水色、淡掉；影子、头顶的步数一起没了，水车才不被它挡着。
	# 身子的颜色游戏每一帧都在改（Character._process），别碰它，只染头
	var who: Character = main.character
	var box := who.sprite_container
	t.tween_property(box, "position:y", box.position.y - SINK_DEPTH, SINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var head := who.head_sprite.material_override as ShaderMaterial
	if head != null: t.tween_property(head, "shader_parameter/color", SUNK, FADE)
	for sprite: Sprite3D in [who.head_sprite, who.body_sprite]:
		var m := sprite.material_override as ShaderMaterial
		if m != null: t.tween_property(m, "shader_parameter/alpha", 0.0, FADE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if is_instance_valid(who.shadow): t.tween_property(who.shadow, "modulate:a", 0.0, FADE)
	for label: Label3D in [who.character_moves_left_label, who.held_label]:
		if is_instance_valid(label): t.tween_property(label, "modulate:a", 0.0, FADE)
	# 水车越转越快。它自己每一帧也在转（Portal._process），这儿是另加的；旧水车换关时就收走了，这一下不用还
	var wheel := portal.sprite_3d
	t.tween_property(wheel, "rotation", wheel.rotation + Vector3(0.0, 0.0, TAU * SPIN), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

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
	_borrow(main, cam, home, secs, t)
	cam.global_position = low                  # 画面盖严着，这一下看不见
	t.tween_property(cam, "global_position", home, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 借东西：记下它们原来是什么样、该回到哪儿，按住镜头不让跟着主角走，再上一个闹钟（看门狗）。
## 平时借了就还、还了才再借。只有一样例外：盖住里哪一步出了错，那一段函数就当作做完了，过渡照常往下走，
## 掀开的时侯上一次借的还没还——主角原来的样子这时侯不能再记一遍（记下的就是半路的样子，还回去主角就成了隐形的），
## 上一次那个还在跑的补间也得先停了（它还在改视角、淡主角）
func _borrow(main: Main, cam: Camera3D, home: Vector3, secs: float, t: Tween) -> void:
	if _armed != 0:
		if _tween != null and _tween.is_valid(): _tween.kill()
		_restore_who()          # 画面盖严着，这一下看不见；不还的话主角会停在淡了一半的样子，等掀开露出来才蹦回原样
	_tween = t
	_cam = cam
	_home = home
	_who = main.character
	if _armed == 0:
		_head_alpha = _alpha_of(_who.head_sprite)
		_body_alpha = _alpha_of(_who.body_sprite)
		_shadow_alpha = _who.shadow.modulate.a
		_moves_alpha = _who.character_moves_left_label.modulate.a
		_held_alpha = _who.held_label.modulate.a if is_instance_valid(_who.held_label) else 1.0
		_box_y = _who.sprite_container.position.y
		_head_tint = _tint_of(_who.head_sprite.material_override as ShaderMaterial)
	_armed += 1
	hold_camera(true)
	# 跟着暂停走（第一个参数给 false）：树一停补间也停，闹钟不能自己先响
	ctl.get_tree().create_timer(secs + WATCHDOG, false).timeout.connect(_expired.bind(_armed))

## 看门狗响了：这一段早该做完了，借走的东西还没还（补间没做完，或者样式里哪一步出了错），现在还。
## 只还、不销账：补间回头自己做完的时侯还会再还一遍，那一遍才销账
func _expired(id: int) -> void:
	if id != _armed: return          # 以前哪一段留下的闹钟
	_give_back(false)

## 还东西：镜头的位置和视角回去、放开它，主角的各处画回原来的样子。
## final = false 是看门狗喊的（见 _expired）；id 是哪一次借东西的补间、闹钟喊的，0 是样式自己喊的
func _give_back(final := true, id := 0) -> void:
	if _armed == 0: return
	if id != 0 and id != _armed: return       # 以前那一次的补间回头做完了：现在这一次自己会还
	if is_instance_valid(_cam):
		_cam.global_position = _home
		_cam.fov = _fov
	_restore_who()
	hold_camera(false)
	if not final: return
	_armed = 0
	_cam = null
	_who = null
	_tween = null

## 一张精灵现在画得多实（wobbly 着色器的 alpha 参数）。不是那种材质、或者没有这个参数，就当它是实的
static func _alpha_of(sprite: Sprite3D) -> float:
	var m := sprite.material_override as ShaderMaterial
	if m == null: return 1.0
	var v: Variant = m.get_shader_parameter("alpha")
	return float(v) if v is float else 1.0

## 一份材质原来的颜色。没有这个参数就当它是白的
static func _tint_of(m: ShaderMaterial) -> Color:
	if m == null: return Color.WHITE
	var v: Variant = m.get_shader_parameter("color")
	return Color(v) if v is Color else Color.WHITE

static func _set_alpha(sprite: Sprite3D, value: float) -> void:
	if not is_instance_valid(sprite): return
	var m := sprite.material_override as ShaderMaterial
	if m != null: m.set_shader_parameter("alpha", value)

## 主角的各处画回借以前的样式
func _restore_who() -> void:
	if not is_instance_valid(_who): return
	_set_alpha(_who.head_sprite, _head_alpha)
	_set_alpha(_who.body_sprite, _body_alpha)
	if is_instance_valid(_who.shadow): _who.shadow.modulate.a = _shadow_alpha
	if is_instance_valid(_who.character_moves_left_label): _who.character_moves_left_label.modulate.a = _moves_alpha
	if is_instance_valid(_who.held_label): _who.held_label.modulate.a = _held_alpha
	# 跳到一半的话游戏自己每一帧会接着摆它的高度，这儿写回去的那一下不碍事
	_who.sprite_container.position.y = _box_y
	var head := _who.head_sprite.material_override as ShaderMaterial
	if head != null: head.set_shader_parameter("color", _head_tint)

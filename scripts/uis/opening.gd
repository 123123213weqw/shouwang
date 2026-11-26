class_name Opening extends CanvasLayer
## 开场动画（游戏一启动、标题页出来之前播的那一段）。原工程只有一张静止的启动图；这里换成在引擎里实时演的动画，
## 用的都是游戏自己的东西：白色剪影、会抖的笔触（FlowMap）、石绿 / 朱砂 / 金、夜色里的水面。
##
## 三个方案，设置里选（Game.opening 记着是哪一个；默认每次开机随机换一个）：
##   A 一灯破夜     一片黑里一点灯花，一盏河灯漂上来，接着一串灯从水底涌起、汇到标志处炸开成光
##   B 水墨惊雷     宣纸上一滴墨化开，标志从墨里反白浮现，一方朱红大印重重盖下，墨色铺满全屏转场
##   D 守夜人点灯   五块石台升起，守夜人一格一格跳过去，每落一格点亮一盏灯，最后一举灯照亮全屏
## 按任意键（或手柄按键、鼠标）跳过。每个方案三四秒，标题页的标志和按钮在最后入场。
## 界面全是代码搭的（和新手教程的卡片一个做法），场景文件 title.tscn 不用改。
## 每个方案配一段声音（assets/audio/opening/，由 tools/audio/remake.py 生成，时刻对着下面的动画）：
## 开场一响，标题页自己的音乐先压低，揭出标题的时侯再回来。
## 旁白是可选的：assets/audio/opening/voice<A>.wav 在（真人录的一句话）就放，不在就不放。台词、录和收拾的办法见 tools/audio/voice.py

signal finished

const FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const FLOW: Texture2D = preload("res://assets/sprites/FlowMap.png")
const SH_SPRITE := preload("res://shaders/opening_sprite.gdshader")
const SH_GLOW := preload("res://shaders/opening_glow.gdshader")
const SH_DISC := preload("res://shaders/opening_disc.gdshader")
const SH_COVER := preload("res://shaders/opening_cover.gdshader")
const SH_INK := preload("res://shaders/opening_ink.gdshader")
const TEX_LAMP: Texture2D = preload("res://assets/sprites/upgrades/fish.png")
const TEX_TILE: Texture2D = preload("res://assets/sprites/tile.png")
const TEX_LOGO: Texture2D = preload("res://assets/sprites/ui/title-logo.png")
const HEAD_SRC: Texture2D = preload("res://assets/sprites/characters/default.png")
const BODY_SRC: Texture2D = preload("res://assets/sprites/characters/default_body.png")

const NAMES := {"A": "一灯破夜", "B": "水墨惊雷", "D": "守夜人点灯"}

const SOUNDS := {
	"A": preload("res://assets/audio/opening/openA.wav"),
	"B": preload("res://assets/audio/opening/openB.wav"),
	"D": preload("res://assets/audio/opening/openD.wav"),
}
const MUSIC_DUCK_DB := -13.0        # 开场播着的时候，标题页的音乐压低这么多，给开场自己的声音让地方
const NARRATION_AT := 0.30           # 旁白从开场的第几秒说起
const NARRATION_DUCK_DB := -7.0      # 旁白说着的时候，开场自己的声音轻这么多，给人的声音让地方

# 查"哪一下卡"用的：设了 SW_OPENING_TRACE 就把每一处创建（贴图、光、粒子、涟漪）的时刻打进日志，
# 配着 pad_adapter 的逐帧计时（debug_frame_stats）就能对上哪一处创建撞出了长帧
var _trace := OS.get_environment("SW_OPENING_TRACE") != ""

func _mark(what: String) -> void:
	# 两个时间：一个是开场自己的计时，一个是游戏启动以来的秒数（和 pad_adapter 的逐帧计时同一把尺子）
	if _trace: print("OPENING_T all=%.3f t=%.3f %s" % [Time.get_ticks_msec() / 1000.0, _elapsed, what])

const SHILV := Color(0.30, 0.72, 0.54)      # 石绿
const ZHUSHA := Color(0.89, 0.33, 0.23)     # 朱砂
const GOLD := Color(0.98, 0.80, 0.34)       # 金
const JINHONG := Color(0.99, 0.60, 0.22)    # 灯焰的金红
const NIGHT := Color(0.0, 0.0, 0.0)
const PAPER := Color(0.93, 0.89, 0.78)      # 宣纸
const INK := Color(0.02, 0.05, 0.05)        # 墨
const STONE := Color(0.16, 0.30, 0.27)      # 石台

var variant := "A"
var title: TitleControl            # 标题页。标志、按钮、音乐都从它那儿要（它自己的三个方法）
var stage: Control                 # 整个覆盖层，盖在标题页上面
var art: Control                   # 动画里的东西（底幕以外）
var cover: ColorRect               # 底幕：一开始盖住整个画面，收尾的时侯让开
var _logo_real: CanvasItem         # 标题页自己的标志
var _buttons: Control              # 标题页自己的按钮
var _buttons_home := Vector2.ZERO
var _buttons_moved := false
var _tweens: Array[Tween] = []
var _elapsed := 0.0
var _hold := false                 # 正在等头几帧画出来（这期间动画的时钟不走）
var _done := false
var _keep: Array[Control] = []     # 动画结束后留在标题页上的装饰（印章）
var _music: AudioStreamPlayer       # 标题页自己的音乐
var _music_home_db := 0.0           # 它平常的音量
var _voice: AudioStreamPlayer       # 开场自己的声音。挂在标题页的根上：开场这一层销毁了，它还能把尾音收完
var _narration: AudioStreamPlayer   # 旁白（有真人录音才有）
var _dot: Texture2D

func _ready() -> void:
	layer = 90
	_dot = _dot_texture()

func _vw() -> float:
	return get_viewport().get_visible_rect().size.x

func _vh() -> float:
	return get_viewport().get_visible_rect().size.y

## 画面上的位置，用"宽的几分之几、高的几分之几"给
func _p(fx: float, fy: float) -> Vector2:
	return Vector2(fx * _vw(), fy * _vh())

## 播一个方案。title_control 是标题页的 TitleControl：它自己的标志和按钮先藏起来，最后由动画放出来
func play(which: String, title_control: TitleControl) -> void:
	variant = which if NAMES.has(which) else "A"
	title = title_control
	# 标志、按钮、音乐都向标题页要（TitleControl 上的三个方法），不在这里写节点路径
	_logo_real = title.logo_image()
	_buttons = title.menu_buttons()
	_music = title.music_player()
	stage = Control.new()
	stage.name = "OpeningStage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_STOP      # 动画播着的时候别点到下面的标题页
	add_child(stage)
	cover = ColorRect.new()
	cover.name = "OpeningCover"
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_COVER
	m.set_shader_parameter("texture_flow_map", FLOW)
	m.set_shader_parameter("progress", 0.0)
	cover.material = m
	stage.add_child(cover)
	art = Control.new()
	art.name = "OpeningArt"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	if _logo_real: _logo_real.modulate.a = 0.0
	if _buttons: _buttons.modulate.a = 0.0
	_sound_start()
	print("OPENING_PLAY %s sound=%s" % [variant, "ok" if (_voice != null and _voice.playing) else "none"])   # 录预览视频的脚本靠这一行核对
	get_node("/root/PadAdapter").note_opening_played(variant)      # 开场状态的检查靠这个知道"这一局真的播过"
	# 这一段的画面在下面一帧里全部建好；接下来两三帧它们第一次画出来，要花一百多毫秒。
	# 屏幕上这时还是黑的（开场自己的底幕盖着），先把这几帧放过去，再让动画从第 0 帧开始走
	_hold = true
	for i in 2: await get_tree().process_frame
	_hold = false
	SceneManager.drop_boot_cover()
	if _done: return
	match variant:
		"B": _b()
		"D": _d()
		_: _a()

## 放这一段的声音；标题页的音乐先压低
func _sound_start() -> void:
	if _music:
		_music_home_db = _music.volume_db
		_after(0.0).tween_property(_music, "volume_db", _music_home_db + MUSIC_DUCK_DB, 0.3).set_trans(Tween.TRANS_SINE)
	if SOUNDS.has(variant):
		_voice = AudioStreamPlayer.new()
		_voice.name = "OpeningVoice"
		_voice.bus = &"SFX"
		_voice.stream = SOUNDS[variant]
		title.add_child(_voice)
		_voice.play()
	# 旁白：有真人录的那一句才放
	var path := "res://assets/audio/opening/voice%s.wav" % variant
	if ResourceLoader.exists(path):
		var line: AudioStream = load(path)
		if line != null and _voice != null:
			_narration = AudioStreamPlayer.new()
			_narration.name = "OpeningNarration"
			_narration.bus = &"SFX"
			_narration.stream = line
			title.add_child(_narration)
			_narration.play(NARRATION_AT)
			_after(NARRATION_AT).tween_property(_voice, "volume_db", NARRATION_DUCK_DB, 0.15)
			_after(NARRATION_AT + line.get_length()).tween_property(_voice, "volume_db", 0.0, 0.4)

## 结束（播完了，或者被跳过）：开场自己的声音很快收掉（播完的时侯只剩一点尾音；跳过的时侯不要突然掐断），
## 音乐回到平常的音量。这两个动画挂在标题页上，开场这一层销毁了也接着走完
func _sound_stop() -> void:
	if is_instance_valid(_voice):
		_voice.name = "OpeningVoiceTail"
		var tv := _voice.create_tween()
		tv.tween_property(_voice, "volume_db", -60.0, 0.22)
		tv.tween_callback(_voice.queue_free)
	if is_instance_valid(_music):
		_music.create_tween().tween_property(_music, "volume_db", _music_home_db, 0.35)
	if is_instance_valid(_narration):
		_narration.name = "OpeningNarrationTail"
		var tn := _narration.create_tween()
		tn.tween_property(_narration, "volume_db", -60.0, 0.12)
		tn.tween_callback(_narration.queue_free)
	_voice = null
	_music = null
	_narration = null

func _process(delta: float) -> void:
	if not _hold: _elapsed += delta

## 按任意键、手柄按键或者鼠标：跳过
func _input(event: InputEvent) -> void:
	if _done or _elapsed < 0.3: return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		if event.is_pressed(): _skip()

# ================================================================ 小工具

func _after(delay: float) -> Tween:
	var t := create_tween()
	_tweens.append(t)
	if delay > 0.0: t.tween_interval(delay)
	return t

## 着色器参数的属性路径（给 tween_property 用）
func _sp(node: CanvasItem, param: String) -> String:
	return "material:shader_parameter/" + param

func _spset(node: CanvasItem, param: String, value) -> void:
	(node.material as ShaderMaterial).set_shader_parameter(param, value)

func _place(r: Control, centre: Vector2) -> void:
	r.position = centre - r.size / 2.0

## 标志的中心：直接从标题页真正的那个标志上量，动画里的标志和它严丝合缝
func _logo_centre() -> Vector2:
	if _logo_real is Control:
		return (_logo_real as Control).get_global_rect().get_center()
	return _p(0.5, 0.343)

## 裁出贴图里图形的那一块（角色的头和身子四周留白很大）
func _crop(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	return a

## 一个会抖的白色剪影，高 height 像素，染成 colour，中心放在 at
func _sprite(tex: Texture2D, height: float, colour: Color, at: Vector2, wobble := 2.0, parent: Node = null) -> TextureRect:
	_mark("sprite h=%.0f" % height)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := height / float(tex.get_height())
	r.size = Vector2(tex.get_width() * k, height)
	r.pivot_offset = r.size / 2.0
	var m := ShaderMaterial.new()
	m.shader = SH_SPRITE
	m.set_shader_parameter("texture_albedo", tex)
	m.set_shader_parameter("texture_flow_map", FLOW)
	m.set_shader_parameter("color", colour)
	m.set_shader_parameter("wobble", wobble)
	# 其余参数也都先赋一遍：着色器的参数要先赋过值，引擎才认它是可以拿去做动画的属性
	m.set_shader_parameter("wobble_size", 5.0)
	m.set_shader_parameter("mode", 0)
	m.set_shader_parameter("progress", 1.0)
	m.set_shader_parameter("origin", Vector2(0.5, 0.5))
	m.set_shader_parameter("soft", 0.2)
	m.set_shader_parameter("flash", 0.0)
	m.set_shader_parameter("ghost", 0.0)
	r.material = m
	if parent == null: parent = art
	parent.add_child(r)
	_place(r, at)
	return r

## 标志的一份拷贝（和标题页自己的那个一样大），一开始没亮，由动画点亮
func _logo(at: Vector2, colour: Color, parent: Node = null) -> TextureRect:
	_mark("logo")
	var l := _sprite(TEX_LOGO, 182.0, colour, at, 2.0, parent)
	_spset(l, "mode", 1)
	_spset(l, "origin", Vector2(0.5, 0.5))
	_spset(l, "progress", 0.0)
	_spset(l, "soft", 0.35)
	# 原来 ghost 给 0.16：黑底上从一开始就看得到一个灰灰的"守望"。人物会觉得那是脏的，不是设计。要亮就从 0 亮
	_spset(l, "ghost", 0.0)
	return l

## 一团光（size 是它所占的方块边长）
func _glow(size: float, colour: Color, strength := 1.0) -> ColorRect:
	_mark("glow %.0f" % size)
	var g := ColorRect.new()
	g.size = Vector2(size, size)
	g.pivot_offset = g.size / 2.0
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_GLOW
	m.set_shader_parameter("color", colour)
	m.set_shader_parameter("strength", strength)
	g.material = m
	return g

## 圆点（radius 0）或者圆环
func _disc(size: float, colour: Color, radius := 0.0, width := 1.0, strength := 1.0) -> ColorRect:
	_mark("disc %.0f" % size)
	var d := ColorRect.new()
	d.size = Vector2(size, size)
	d.pivot_offset = d.size / 2.0
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_DISC
	m.set_shader_parameter("color", colour)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("strength", strength)
	d.material = m
	return d

## 一圈涟漪：从 at 荡开、变淡。squash 小于 1 是俯视水面上的椭圆
func _ripple(at: Vector2, size: float, colour: Color, delay := 0.0, squash := 1.0, dur := 0.85) -> void:
	var r := _disc(size, colour, 0.04, 0.06, 0.0)
	art.add_child(r)
	_place(r, at)
	r.scale = Vector2(1.0, squash)
	var t := _after(delay)
	t.tween_property(r, _sp(r, "strength"), 0.55, 0.06)
	t.tween_property(r, _sp(r, "radius"), 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(r, _sp(r, "strength"), 0.0, dur)
	t.tween_callback(r.queue_free)

## 迸出一把火星（additive 为假是普通的画法，深色的墨点要这样才看得见）
func _burst(at: Vector2, colour: Color, count := 40, speed := 300.0, life := 0.8, additive := true) -> void:
	_mark("burst %d" % count)
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.gravity = Vector2(0.0, 160.0)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.45
	p.scale_amount_max = 1.25
	p.texture = _dot
	p.color = colour
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	art.add_child(p)
	p.emitting = true
	_after(life * 2.2).tween_callback(p.queue_free)

## 把一个节点从动画层里拿到覆盖层的最上面（位置不变）：收尾的时侯动画层整个淡出去，它不受影响
func _detach(node: Control) -> void:
	var gp: Vector2 = node.global_position
	art.remove_child(node)
	stage.add_child(node)
	node.global_position = gp

## 震屏
func _shake(px: float, dur: float) -> void:
	_after(0.0).tween_method(_jitter.bind(px), 0.0, 1.0, dur)
	_after(dur).tween_callback(func() -> void: stage.position = Vector2.ZERO)

func _jitter(t: float, px: float) -> void:
	stage.position = Vector2(randf_range(-px, px), randf_range(-px, px)) * (1.0 - t)

## 从 from 直线走到 to；_sway 多一个左右轻摆
func _move(v: float, node: Control, from: Vector2, to: Vector2) -> void:
	_place(node, from.lerp(to, v))

func _sway(v: float, node: Control, from: Vector2, to: Vector2, amp: float, freq: float, phase: float) -> void:
	_place(node, from.lerp(to, v) + Vector2(sin(v * freq + phase) * amp, 0.0))

## 火星用的小圆点
func _dot_texture() -> Texture2D:
	var t := GradientTexture2D.new()
	t.width = 24
	t.height = 24
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	t.gradient = g
	return t

func _cover(colour: Color) -> void:
	_spset(cover, "color", colour)
	_spset(cover, "progress", 0.0)
	_spset(cover, "mode", 0)
	_spset(cover, "aspect", _vw() / _vh())

## 收尾：底幕让开（mode 是让开的方式，-1 表示底幕已经处理过了），露出真正的标题页；
## 动画里自己那份标志淡出去、标题页的标志淡进来；按钮按 style 的样子入场（drop 落下来 / slide 从右边滑进来 / pop 弹出来）
func _end(at: float, mode: int, origin: Vector2, dur: float, style: String) -> void:
	if is_instance_valid(_music):
		_after(at).tween_property(_music, "volume_db", _music_home_db, dur + 0.2).set_trans(Tween.TRANS_SINE)
	if mode >= 0:
		_spset(cover, "mode", mode)
		_spset(cover, "origin", origin)
		_spset(cover, "soft", 0.3)
		_after(at).tween_property(cover, _sp(cover, "progress"), 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var t2 := _after(at + dur * 0.35)
	t2.tween_property(art, "modulate:a", 0.0, dur * 0.6)
	if _logo_real:
		t2.parallel().tween_property(_logo_real, "modulate:a", 1.0, dur * 0.6)
	var tb := _after(at + dur * 0.5)
	if _buttons:
		_buttons_home = _buttons.position
		_buttons_moved = true
		match style:
			"drop": _buttons.position = _buttons_home + Vector2(0.0, -46.0)
			"slide": _buttons.position = _buttons_home + Vector2(150.0, 0.0)
			"pop":
				_buttons.pivot_offset = _buttons.size / 2.0
				_buttons.scale = Vector2(0.8, 0.8)
		tb.tween_property(_buttons, "modulate:a", 1.0, 0.35)
		tb.parallel().tween_property(_buttons, "position", _buttons_home, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tb.parallel().tween_property(_buttons, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_after(at + dur + 0.6).tween_callback(_finish)

## 结束（播完了，或者被跳过）：把标题页恢复成平常的样子
func _finish() -> void:
	if _done: return
	_done = true
	_sound_stop()
	for node in _keep:
		if is_instance_valid(node) and node.has_meta("keep"):
			var gp: Vector2 = node.global_position
			node.get_parent().remove_child(node)
			title.add_child(node)
			node.global_position = gp
	stage.queue_free()
	if _logo_real: _logo_real.modulate.a = 1.0
	if _buttons:
		_buttons.modulate.a = 1.0
		_buttons.scale = Vector2.ONE
		if _buttons_moved: _buttons.position = _buttons_home
	finished.emit()
	queue_free()

func _skip() -> void:
	for t in _tweens:
		if t.is_valid(): t.kill()
	_finish()

# ================================================================ A 一灯破夜

func _a() -> void:
	_cover(NIGHT)
	var c := _logo_centre()                         # 标志的中心
	var bottom := _p(0.5, 0.93)
	# 第一盏灯：先是一点灯花，忽明忽暗，然后定了下来
	var lamp := _sprite(TEX_LAMP, 126.0, GOLD, bottom)
	lamp.modulate.a = 0.0
	var g := _glow(380.0, GOLD, 0.0)
	lamp.add_child(g)
	g.position = (lamp.size - g.size) / 2.0
	var t := _after(0.2)
	for i in 3:
		t.tween_property(g, _sp(g, "strength"), 0.28 + 0.16 * i, 0.17)
		t.tween_property(g, _sp(g, "strength"), 0.10 + 0.06 * i, 0.11)
	t.tween_callback(func() -> void: lamp.modulate.a = 1.0)
	t.tween_property(g, _sp(g, "strength"), 1.0, 0.5)
	_ripple(bottom, 460.0, SHILV, 1.05)
	_ripple(bottom, 460.0, SHILV, 1.3)
	_ripple(bottom, 460.0, SHILV, 1.55)
	var mid := _p(0.5, 0.66)
	_after(1.3).tween_method(_sway.bind(lamp, bottom, mid, 9.0, 7.0, 0.0), 0.0, 1.0, 1.4)
	# 一串河灯从水底涌上来
	var warm: Array[Color] = [GOLD, JINHONG, ZHUSHA, SHILV, Color(0.80, 0.92, 0.62)]
	for i in 12:
		var fx := 0.14 + 0.72 * (float((i * 5) % 12) / 11.0)
		var start := _p(fx, 1.10)
		var up := _p(fx, 0.28 + 0.26 * (float((i * 3) % 7) / 6.0))
		var h := 58.0 + 40.0 * (float((i * 7) % 5) / 4.0)
		var col: Color = warm[i % warm.size()]
		var l := _sprite(TEX_LAMP, h, col, start)
		l.modulate.a = 0.0
		var lg := _glow(h * 3.4, col, 1.1)
		l.add_child(lg)
		lg.position = (l.size - lg.size) / 2.0
		var t1 := _after(0.75 + i * 0.11)
		t1.tween_property(l, "modulate:a", 1.0, 0.3)
		t1.parallel().tween_method(_sway.bind(l, start, up, 14.0, 6.0, float(i)), 0.0, 1.0, 1.3)
		# 涌到半空的灯一齐汇向标志：一盏一盏地飞进去，最后一盏也要在光炸开（2.56）之前落进标志里。
		# 淡出只放在飞行的最后 0.10 秒，人看到的是"收进标志里"，而不是半路消失
		var arrive := 2.34 + i * 0.016
		var dur := 0.40 + 0.03 * float(i % 3)
		var t2 := _after(arrive - dur)
		t2.tween_method(_move.bind(l, up, c), 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t2.parallel().tween_property(l, "scale", Vector2(0.10, 0.10), dur)
		t2.parallel().tween_property(l, "modulate:a", 0.0, 0.10).set_delay(dur - 0.10)
	# 最先浮上来的那盏灯也一样：飞到标志里再消失
	_after(1.95).tween_method(_move.bind(lamp, mid, c), 0.0, 1.0, 0.57).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_after(2.42).tween_property(lamp, "modulate:a", 0.0, 0.10)
	# 标志亮起来：一团大光、闪一下、迸出一圈火星
	var flash := _glow(1200.0, GOLD, 0.0)
	art.add_child(flash)
	_place(flash, c)
	var logo := _logo(c, Color.WHITE)
	var ts := _after(2.56)
	ts.tween_property(flash, _sp(flash, "strength"), 1.15, 0.10)
	ts.tween_property(flash, _sp(flash, "strength"), 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 同时收小：一闪之后光往回收，让位给标志，别留一团黄球挂着
	ts.parallel().tween_property(flash, "scale", Vector2(0.55, 0.55), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var tl := _after(2.58)
	# 亮起来的时候从稍大一点落回原大小，人会觉着它"落定"了，而不是凭空浮出来
	logo.scale = Vector2(1.06, 1.06)
	tl.tween_property(logo, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tl.parallel().tween_property(logo, _sp(logo, "progress"), 1.0, 0.65)
	tl.parallel().tween_property(logo, _sp(logo, "flash"), 0.9, 0.05)
	tl.tween_property(logo, _sp(logo, "flash"), 0.0, 0.5)
	_after(2.6).tween_callback(func() -> void:
		_burst(c, GOLD, 46, 420.0, 0.8)
		_burst(c, SHILV, 20, 230.0, 0.9)
		_burst(c, ZHUSHA, 14, 280.0, 0.85)
	)
	_end(2.95, 1, Vector2(0.5, c.y / _vh()), 0.95, "drop")

# ================================================================ B 水墨惊雷

func _b() -> void:
	_cover(PAPER)
	# 纸是从暗处亮起来的：起点用"暗的米色"而不是纯黑（黑到米白的中途会过一道发棕的颜色，像换了张纸）
	_spset(cover, "color", Color(PAPER.r * 0.16, PAPER.g * 0.16, PAPER.b * 0.16))
	_after(0.02).tween_property(cover, _sp(cover, "color"), PAPER, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var c := _logo_centre()
	# 墨：从落下的那一点往外化开
	var ink := ColorRect.new()
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mi := ShaderMaterial.new()
	mi.shader = SH_INK
	mi.set_shader_parameter("texture_flow_map", FLOW)
	mi.set_shader_parameter("color", INK)
	mi.set_shader_parameter("origin", Vector2(0.5, 0.43))
	mi.set_shader_parameter("aspect", _vw() / _vh())
	mi.set_shader_parameter("progress", 0.0)
	mi.set_shader_parameter("soft", 0.09)
	ink.material = mi
	art.add_child(ink)
	# 一滴墨落在纸上：一个墨点、一圈墨环、几点飞溅，然后化开成一朵云
	var drop := _disc(30.0, INK)
	art.add_child(drop)
	_place(drop, c)
	drop.scale = Vector2.ZERO
	var t0 := _after(0.15)
	t0.tween_property(drop, "scale", Vector2.ONE, 0.1)
	t0.tween_property(ink, _sp(ink, "progress"), 0.84, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 原来这里还有一圈墨环：一条细黑圈从落点往外扩。看着像肥皂泡的边，不像墨，去掉了
	_after(0.17).tween_callback(func() -> void: _burst(c, INK, 40, 340.0, 0.7, false))
	# 标志从墨里反白浮现
	var logo := _sprite(TEX_LOGO, 182.0, PAPER.lightened(0.35), c)
	_spset(logo, "mode", 2)
	_spset(logo, "progress", 0.0)
	_spset(logo, "soft", 0.16)
	_spset(logo, "ghost", 0.0)
	_after(0.95).tween_property(logo, _sp(logo, "progress"), 1.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 朱红大印：从空中重重盖下来
	var seal := _seal()
	var sc := c + Vector2(212.0, 84.0)
	_place(seal, sc)
	seal.scale = Vector2(3.2, 3.2)
	seal.modulate.a = 0.0
	var t1 := _after(1.95)
	t1.tween_property(seal, "modulate:a", 1.0, 0.05)
	t1.tween_property(seal, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t1.tween_callback(func() -> void:
		seal.set_meta("keep", true)          # 盖实了：留在标题页上
		_detach(seal)                        # 从动画层里拿出来，转场的时侯不跟着淡出去
		_shake(11.0, 0.4)
		_ripple(sc, 520.0, INK, 0.0, 1.0, 0.6)
		_burst(sc, INK, 60, 420.0, 0.8, false)
		_burst(sc, ZHUSHA, 24, 220.0, 0.6)
	)
	_keep.append(seal)
	# 墨铺满全屏，纸被盖住；然后墨色淡出去，底下就是游戏的夜色标题页
	var t2 := _after(2.55)
	# 铺满要比"算出来够用"再多给一点：墨的边是不规则的，有的地方阈值高，1.6 会在淡出前留一条没铺到的带子
	t2.tween_property(ink, _sp(ink, "progress"), 2.4, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t2.tween_callback(func() -> void: cover.visible = false)
	t2.tween_property(ink, "modulate:a", 0.0, 0.7)
	_end(3.0, -1, Vector2(0.5, 0.5), 0.8, "slide")

## 一方朱红大印，上面是"守望"两个字
func _seal() -> Panel:
	var seal := Panel.new()
	seal.name = "OpeningSeal"
	seal.size = Vector2(104.0, 104.0)
	seal.pivot_offset = seal.size / 2.0
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.80, 0.14, 0.10)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.95, 0.90, 0.82)
	seal.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = "守\n望"
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 44
	ls.font_color = Color(0.97, 0.93, 0.86)
	ls.line_spacing = -8
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seal.add_child(l)
	art.add_child(seal)
	return seal

# ================================================================ D 守夜人点灯

func _d() -> void:
	_cover(NIGHT)
	var vw := _vw()
	var vh := _vh()
	var c := _logo_centre()
	# 夜里的水面：几圈很淡的涟漪
	for i in 5:
		_ripple(Vector2(vw * (0.12 + 0.19 * i), vh * (0.5 + 0.3 * (float((i * 3) % 4) / 3.0))), 520.0, Color(0.10, 0.24, 0.22), 0.2 + i * 0.5, 0.35, 1.6)
	# 五块石台从水里升起来
	var tile_tex := _crop(TEX_TILE, Rect2(19, 17, 123, 122))
	var xs: Array[float] = [0.30, 0.40, 0.50, 0.60, 0.70]
	var dys: Array[float] = [0.0, -10.0, 6.0, -6.0, 0.0]
	var tiles: Array[Control] = []
	var spots: Array[Vector2] = []
	for k in 5:
		var at := Vector2(vw * xs[k], vh * 0.66 + dys[k])
		spots.append(at)
		var tile := _sprite(tile_tex, 92.0, STONE, at + Vector2(0.0, 80.0), 1.0)
		tile.modulate.a = 0.0
		tiles.append(tile)
		var t := _after(0.25 + k * 0.09)
		t.tween_property(tile, "modulate:a", 1.0, 0.2)
		t.parallel().tween_method(_rise_in.bind(tile, at), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 守夜人：头、蓑衣，手里提着一盏灯
	var s := 0.8
	var head_size := Vector2(118.0, 108.0) * s
	var body_size := Vector2(105.0, 154.0) * s
	var body_at := Vector2(7.0, 102.0) * s
	var man := Control.new()
	man.size = Vector2(maxf(head_size.x, body_at.x + body_size.x), body_at.y + body_size.y)
	man.pivot_offset = man.size / 2.0
	man.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(man)
	var head := _sprite(_crop(HEAD_SRC, Rect2(59, 70, 118, 108)), head_size.y, Color(0.93, 0.95, 0.90), head_size / 2.0, 1.0, man)
	var body := _sprite(_crop(BODY_SRC, Rect2(66, 56, 105, 154)), body_size.y, Color(0.74, 0.63, 0.40), body_at + body_size / 2.0, 1.0, man)
	var hand := _sprite(TEX_LAMP, 44.0, GOLD, Vector2(man.size.x - 10.0, man.size.y * 0.40), 2.0, man)
	var hand_glow := _glow(150.0, GOLD, 1.0)
	hand.add_child(hand_glow)
	hand_glow.position = (hand.size - hand_glow.size) / 2.0
	man.modulate.a = 0.0
	# 一格一格跳过去：每落在一块石台上，就点亮一盏灯
	var foot := func(at: Vector2) -> Vector2: return Vector2(at.x, at.y - 34.0 - man.size.y / 2.0)
	var prev: Vector2 = foot.call(spots[0]) + Vector2(-vw * 0.11, 0.0)
	_place(man, prev)
	_after(0.7).tween_property(man, "modulate:a", 1.0, 0.25)
	var warm: Array[Color] = [GOLD, JINHONG, SHILV, ZHUSHA, GOLD]
	var lamps: Array[Control] = []
	for k in 5:
		var to: Vector2 = foot.call(spots[k])
		var from := prev
		var th := _after(0.95 + k * 0.3)
		th.tween_method(_hop.bind(man, from, to), 0.0, 1.0, 0.3)
		var tl := _after(1.25 + k * 0.3)
		tl.tween_callback(_light_tile.bind(tiles[k], spots[k], warm[k], lamps))
		prev = to
	# 最后举起灯：手里的灯变大变亮，光从守夜人那里扫开全屏，石台、灯和人一起汇向标志
	var tu := _after(2.42)
	tu.tween_property(hand, "scale", Vector2(3.2, 3.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tu.parallel().tween_property(hand_glow, _sp(hand_glow, "strength"), 2.4, 0.3)
	var origin := Vector2(prev.x / vw, (prev.y - 20.0) / vh)
	var logo := _logo(c, Color.WHITE)
	_spset(logo, "origin", Vector2(0.5, 0.95))
	# 石台、灯和人先全部汇进标志（2.05 起，2.62 之前到齐），标志再亮起来
	var tc := _after(2.05)
	for node in tiles:
		tc.tween_method(_converge.bind(node, node.position + node.size / 2.0, c), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for l in lamps:
		tc.tween_method(_converge.bind(l, l.position + l.size / 2.0, c), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tc.tween_method(_converge.bind(man, man.position + man.size / 2.0, c), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_after(2.60).tween_property(logo, _sp(logo, "progress"), 1.0, 0.65)
	_after(2.62).tween_callback(func() -> void:
		_burst(c, GOLD, 60, 430.0, 0.9)
		_burst(c, SHILV, 28, 240.0, 1.0)
	)
	_end(2.86, 1, origin, 0.9, "drop")

func _rise_in(v: float, tile: Control, at: Vector2) -> void:
	_place(tile, at + Vector2(0.0, 80.0 * (1.0 - v)))

## 跳一步：横着过去，竖着走一个弧
func _hop(v: float, man: Control, from: Vector2, to: Vector2) -> void:
	_place(man, from.lerp(to, v) - Vector2(0.0, sin(v * PI) * 54.0))
	man.scale = Vector2(1.0, 1.0 + sin(v * PI) * 0.08)

## 落在一块石台上：石台亮一下，头顶上亮起一盏灯，荡开一圈涟漪
func _light_tile(tile: Control, at: Vector2, col: Color, lamps: Array[Control]) -> void:
	_spset(tile, "color", GOLD)
	var t := _after(0.0)
	t.tween_property(tile, "material:shader_parameter/color", SHILV, 0.6)
	var l := _sprite(TEX_LAMP, 58.0, col, at + Vector2(0.0, -104.0))
	l.scale = Vector2.ZERO
	var lg := _glow(170.0, col, 0.9)
	l.add_child(lg)
	lg.position = (l.size - lg.size) / 2.0
	lamps.append(l)
	_after(0.0).tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ripple(at + Vector2(0.0, 26.0), 320.0, SHILV, 0.0, 0.35, 0.6)
	_burst(at, GOLD, 10, 170.0, 0.5)

## 汇向标志，越近越小
func _converge(v: float, node: Control, from: Vector2, c: Vector2) -> void:
	_place(node, from.lerp(c, v))
	node.modulate.a = 1.0 - v
	node.scale = Vector2.ONE * (1.0 - 0.6 * v)

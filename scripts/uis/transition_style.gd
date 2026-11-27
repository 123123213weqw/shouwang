class_name TransitionStyle extends RefCounted
## 换关、换场景时那段过渡的一种样式。scripts/uis/transitions/ 里每个文件是一种：文件名 transition_<样式>.gd，
## 第一行写 extends TransitionStyle，不写 class_name（SceneTransitionControl 按样式名到那个目录里找文件，load 了直接 new）。
## 选哪一种见 SceneTransitionControl.set_style；测试时用环境变量 SW_TRANSITION，或者在游戏里 call pad_adapter.gd debug_transition <样式>。
## 怎么加一种、怎么录片子见 docs/transitions.md。
##
## 盖住、掀开各是一个函数，做完再返回（里面可以 await）。分两类：
##   贴一层的：盖住 = 一层画面盖满屏幕，掀开 = 它退走。盖住做完的那一刻，屏幕必须已经完全看不见后面的东西
##             （调用的人紧接着就换棋盘）；掀开做完的时候，自己加的节点要看不见了，借走的东西要还回去。
##   棋盘上的（比如石阶沉浮）：不盖屏幕，动的是棋盘上的东西，那就自己保证换棋盘的那几帧看着不别扭。
##
## 说明（ctx，一个 Dictionary）里有这一趟的事：
##   mode        "level" 换关（过关、长夜的下一更、再守这一关、重来、换难度、对战的轮战都算）；"scene" 标题页和游戏之间换场景
##   fast        true = 换关换得快的局（长夜、轮战）：过渡要短，别拖节奏
##   from        谁触发的，世界坐标。平时是主角这会儿站的地方；换场景的时侯没有（null）
##   to          掀开以后主角站在哪儿，世界坐标。掀开的时侯有；盖住的时侯可能还没有
##   title       关卡名那一行（"第 3 关 · 断桥"）；name 关卡自己的名字（"断桥"）；index 第几关（从 1 数起）
##   color       要去的这一关的底色（LevelResource.base_color）；color_from 离开的那一关的底色
##   level       要去的这一关（LevelResource）；main 是 Main 节点（换场景的时侯可能还没有）
## 样式要往屏幕上画东西：ctl 是一个 CanvasLayer（编号 10，压在所有界面上面），节点用 add() 加在它下面。
## 世界坐标的点画在画面上的哪儿，用 screen_uv() 算。

var ctl: CanvasLayer                 ## 挂在谁下面：SceneTransitionControl.set_style 建好它以后给上
var nodes: Array[Node] = []          ## 自己加的节点（add() 记的账）：换样式的时候一起收走
var _warm: Array[Node] = []          ## 其中要预热的那几个（add 的时候给了 warm）

## 建好以后调一次：把要用的节点先建出来（先藏着）。这时候 ctl 已经有了
func build() -> void:
	pass

## 盖住：做完再返回
func cover(ctx: Dictionary) -> void:
	pass

## 掀开：做完再返回
func reveal(ctx: Dictionary) -> void:
	pass

## 换样式的时候调：把加过的节点收走、借走的东西还回去。默认只做这两件，自己另借了什么（主角、河灯……）在这儿还
func dispose() -> void:
	if ctl != null: hold_camera(false)
	for n in nodes:
		if is_instance_valid(n): n.queue_free()
	nodes.clear()

## 往 ctl 下面加一个节点，记在账上。给了 warm = true 的话，装上这个样式的时侯会让它先白画两帧
##（着色器头一回画要编译，那一帧很长：趁着开机的黑幕还在先花掉，别留到第一次换关）
func add(node: Node, warm := false) -> Node:
	ctl.add_child(node)
	nodes.append(node)
	if warm: _warm.append(node)
	return node

## 让记了账的那些节点白画两帧（外面在装好样式以后调）。它们这会儿必须是画出来什么都看不见的：着色器在"还没开始"的状态下
## 整张是透明的，别靠藏节点或者 modulate —— 藏着的节点不会画，着色器也就不编译
func warm_up() -> void:
	if ctl == null or _warm.is_empty(): return
	for i in 3:
		await ctl.get_tree().process_frame
	for n in _warm:
		if is_instance_valid(n): n.visible = true
	for i in 2:
		await ctl.get_tree().process_frame
	for n in _warm:
		if is_instance_valid(n): n.visible = false

## 世界坐标的某一点在画面上的位置（0 到 1，左上角是 0, 0）。没有这个点、或者它在镜头背后，就用 fallback
func screen_uv(world: Variant, fallback := Vector2(0.5, 0.5)) -> Vector2:
	if ctl == null or world == null: return fallback
	var cam := ctl.get_viewport().get_camera_3d()
	if cam == null: return fallback
	var w: Vector3 = world
	if cam.is_position_behind(w): return fallback
	return cam.unproject_position(w) / ctl.get_viewport().get_visible_rect().size

## 这一段该多长：平时的局用 normal 秒，换关换得快的局（ctx.fast）用 fast 秒
static func duration(ctx: Dictionary, normal: float, fast: float) -> float:
	return fast if bool(ctx.get("fast", false)) else normal

## 按住镜头：过渡里要自己摆弄镜头的样式用。镜头平时每一帧都跟着主角走（main._process），不按住就和样式抢
func hold_camera(on: bool) -> void:
	var main := ctl.get_node_or_null("/root/Main")
	if main != null: main.camera_hold = on

## 一张铺满整个画面的贴图节点，套着给的着色器。节点是看得见的，画出来是什么全看着色器
##（在"还没开始"的状态下得是整张透明的）。用 add(rect, true) 加上去，着色器就预热过了
static func full_rect(shader: Shader) -> TextureRect:
	var rect := TextureRect.new()
	# 没贴贴图的 TextureRect 是不画的（着色器也就不会跑）：贴一张纯白的小方图，画面全看着色器
	rect.texture = load("res://assets/sprites/rect.png")
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = shader
	rect.material = m
	return rect

## 这一种样式的着色器：shaders/transition_<样式>.gdshader
static func shader(id: String) -> Shader:
	return load("res://shaders/transition_%s.gdshader" % id) as Shader

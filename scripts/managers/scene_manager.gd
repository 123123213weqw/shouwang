extends Node

var current_scene = null
var game_scene = "res://scenes/main.tscn"
var title_scene = "res://scenes/title.tscn"

var run_time = 0
var coin_count = 0
var max_coins = 0
var reset_count = 0

const SCENE_TRANSITION_CONTROL = preload("res://scenes/uis/scene_transition_control.tscn")
var scene_transition_control

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	
	scene_transition_control = SCENE_TRANSITION_CONTROL.instantiate()
	add_child(scene_transition_control)
	_add_boot_cover()

	# 游戏一启动先播开场动画（等标题页自己准备好了再说）。播哪一个看 Game.opening
	_play_opening.call_deferred()

## 开机先盖一层黑。标题页第一次画出来要一百多毫秒（着色器要编译），开场里那些材质第一次画也要一百多毫秒；
## 盖着黑幕的时侯这些钱在幕后花掉，人看到的就是黑一下，不是画面顿一下。开场自己也有底幕，撤的时候看不出缝
var _boot: CanvasLayer

func _add_boot_cover() -> void:
	_boot = CanvasLayer.new()
	_boot.name = "BootCover"
	_boot.layer = 200                          # 盖在所有东西上面
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot.add_child(rect)
	add_child(_boot)

## 撤掉开机那块黑。开场把底幕铺好、材质都画过一遍以后才撤
func drop_boot_cover() -> void:
	if _boot != null and is_instance_valid(_boot):
		_boot.queue_free()
	_boot = null

## 开机第一幕是标题页的话，播开场动画（设置里可以关掉）。从游戏里回到标题页的不播
func _play_opening() -> void:
	if current_scene == null or Game.opening == "" or Game.opening == "off": return
	# 标题页场景的根节点挂的就是 TitleControl 这个脚本（CanvasLayer/TitleControl 只是它下面的一个容器，没有脚本）。
	# 开场要调它的三个方法（标志、按钮、音乐），所以直接用根节点；不是标题页就不播
	var title_control := current_scene as TitleControl
	if title_control == null: return
	var which: String = Game.roll_opening() if Game.opening == "random" else Game.opening
	var opening := Opening.new()
	opening.name = "Opening"
	current_scene.add_child(opening)
	opening.play(which, title_control)
func load_title():
	load_scene_progress(title_scene)

func load_character_select():
	var title := await load_scene_progress(title_scene) as TitleControl
	title.select_character()

func load_game():
	load_scene_progress(game_scene)

func load_scene(path):
	_deferred_goto_scene.call_deferred(path)

func _deferred_goto_scene(path):
	var s = ResourceLoader.load(path)
	set_scene(s.instantiate())
	
func set_scene(scene):
	get_tree().current_scene.free()
	current_scene = scene
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene

func load_scene_progress(path):
	await scene_transition_control.open()
	
	var s = await _thread_load(path)
	var s_instance = s.instantiate()
	set_scene(s_instance)
	
	scene_transition_control.close()
	return s_instance

func _thread_load(path):
	ResourceLoader.load_threaded_request(path)
	var tree = get_tree()
	var progress = 0
	var arrProgress = [0]
	while progress < 1:
		await tree.process_frame
		ResourceLoader.load_threaded_get_status(path, arrProgress)
		progress = arrProgress[0]
	return ResourceLoader.load_threaded_get(path)
	

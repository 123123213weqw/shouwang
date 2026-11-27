class_name TitleControl extends Control

@export var texture_map: Texture2DArray
@onready var title: Control = $CanvasLayer/TitleControl/Panel/Title
@onready var play_button: Button = $CanvasLayer/TitleControl/ButtonsContainer/PlayButton
@onready var endless_button: Button = $CanvasLayer/TitleControl/ButtonsContainer/EndlessButton
@onready var settings_button: Button = $CanvasLayer/TitleControl/ButtonsContainer/SettingsButton
@onready var quit_button: Button = $CanvasLayer/TitleControl/ButtonsContainer/QuitButton
@onready var leaderboard_button: Button = $CanvasLayer/TitleControl/ButtonsContainer/LeaderboardButton
@onready var buttons_container: VBoxContainer = $CanvasLayer/TitleControl/ButtonsContainer

@onready var character_select: Control = $CanvasLayer/TitleControl/CharacterSelect
@onready var characters_container: GridContainer = $CanvasLayer/TitleControl/CharacterSelect/CharactersContainer
@onready var character_description: Label = $CanvasLayer/TitleControl/CharacterSelect/CharacterDescription
@onready var return_button: Button = $CanvasLayer/TitleControl/CharacterSelect/ReturnButton

@onready var leader_board_container_control_container: Control = $CanvasLayer/TitleControl/LeaderBoardContainerControlContainer
@onready var leader_board_container_control: LeaderBoardContainerControl = $CanvasLayer/TitleControl/LeaderBoardContainerControlContainer/LeaderBoardContainerControl
@onready var leader_board_return_button: Button = $CanvasLayer/TitleControl/LeaderBoardContainerControlContainer/LeaderBoardReturnButton

@onready var settings_container: Control = $CanvasLayer/TitleControl/SettingsContainer
@onready var settings_return_button: Button = $CanvasLayer/TitleControl/SettingsContainer/SettingsReturnButton

@onready var ui_root: Control = $CanvasLayer/TitleControl     # 标题页所有界面的根，难度选择面板挂在它下面
@onready var _lobby_river: Node = $CanvasLayer/LobbyRiver     # 标题页的背景：一条夜里的河（scripts/uis/lobby_river.gd）

## 标题页按钮列里的"难度"按钮和它点开的难度选择面板（节点名还是叫 Ruleset…：测试的步骤文件里按名字找它们，没改）。
## 场景里没有它们，是 _ready() 里用代码加的
var ruleset_button: Button
var ruleset_picker: RulesetPicker

const BUTTON := preload("res://scenes/uis/button.tscn")
const RULESET_BUTTON_SIZE := 36            # "难度 · 中等"是次要的入口，字比上面两个小一号

@export var character_resources: Array[CharacterResource]
const CHARACTER_SELECT_CONTROL = preload("res://scenes/uis/character_select_control.tscn")

## 给别的模块用的四个入口。节点在场景里叫什么、放在哪，只有这个脚本知道；
## 开场动画、设置页、调试遥控要动它们，只调这几个方法，不在别处写节点路径（改了场景名也不会悄悄失灵）
func logo_image() -> CanvasItem:
	return $CanvasLayer/TitleControl/Panel/Title/TextureRect as CanvasItem

func menu_buttons() -> Control:
	return buttons_container

func music_player() -> AudioStreamPlayer:
	return get_node_or_null("MainTitle2") as AudioStreamPlayer

func lobby_river() -> Node:
	return get_node_or_null("CanvasLayer/LobbyRiver")

func _ready() -> void:
	Game.characters = character_resources
	Game.load()
	
	character_select.set_visible(false)
	play_button.pressed.connect(func(): start_run(Game.GameMode.CAMPAIGN))
	endless_button.pressed.connect(func(): start_run(Game.GameMode.ENDLESS))
	leaderboard_button.pressed.connect(show_leaderboard)
	return_button.pressed.connect(func(): return_to_title())
	quit_button.pressed.connect(func(): get_tree().quit())
	leader_board_return_button.pressed.connect(func(): return_to_title())
	settings_button.pressed.connect(func(): show_settings())
	settings_return_button.pressed.connect(func(): return_to_title())
	SceneManager.scene_transition_control.close()
	_add_ruleset_ui()
	update_characters()
	character_description.text = ""
	_lobby_river.follow_menu(buttons_container)
	_lobby_river.avoid(logo_image())
	_lobby_start.call_deferred()

## 标题页露出来的那一下（开场动画收完）：河面从标志底下荡开一圈。
## 开场那一层是 SceneManager 稍后才挂到标题页上的，所以要等这一帧过了再去找它；没播开场就现在荡
func _lobby_start() -> void:
	var centre := Vector2.ZERO
	var logo := logo_image() as Control
	if logo != null: centre = logo.get_global_rect().get_center()
	var opening := get_node_or_null("Opening")
	if opening != null and not opening.is_queued_for_deletion() and opening.has_signal("finished"):
		opening.finished.connect(func() -> void: _lobby_river.wake(centre))
	else:
		_lobby_river.wake(centre)

## 在"长夜"后面加一个"难度"按钮，再建难度选择面板（挂在 CanvasLayer/TitleControl 下，画在最上面）。
## 面板开着的时候标题页的按钮和标志都藏起来，按"返回"再回到标题页
func _add_ruleset_ui() -> void:
	ruleset_button = BUTTON.instantiate() as Button
	ruleset_button.name = "RulesetButton"
	ruleset_button.add_theme_font_size_override("font_size", RULESET_BUTTON_SIZE)
	buttons_container.add_child(ruleset_button)
	buttons_container.move_child(ruleset_button, endless_button.get_index() + 1)
	# 多了一个按钮，这一列比原来高了 50 多个像素，16:9 的画面（逻辑高度只有 648）里放不下，"设置"会贴到底下的署名。
	# 所以行间距从 16 收到 10，整列 297 像素；再让它从固定的高度往下排（原来是在这一列里居中）。
	# 离标志的字底还是 32 像素（和原来一样）。底下的署名那一行后来去掉了，这里的间距留着不动
	buttons_container.add_theme_constant_override("separation", 10)
	buttons_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	buttons_container.offset_top = -17.0
	buttons_container.offset_bottom = 285.0

	ruleset_picker = RulesetPicker.new()
	ruleset_picker.name = "RulesetPicker"
	ui_root.add_child(ruleset_picker)
	ruleset_button.pressed.connect(show_rulesets)
	ruleset_picker.selected.connect(update_ruleset_button)
	ruleset_picker.closed.connect(return_to_title)
	update_ruleset_button()

## "难度"按钮上写的是现在选的难度，例如"难度 · 中等"
func update_ruleset_button() -> void:
	var r: Ruleset = Game.ruleset
	ruleset_button.text = "难度 · %s" % (r.title if r != null and r.title != "" else "—")

func update_characters():
	for child in characters_container.get_children():
		child.queue_free()
	var i = 0.0
	for cr in character_resources:
		var nchar := CHARACTER_SELECT_CONTROL.instantiate() as CharacterSelectControl
		characters_container.add_child(nchar)
		nchar.load_resource(cr)
		nchar.set_state(Game.unlocked_characters.has(cr))
		nchar.star_texture.set_visible(Game.has_completed_run(cr))
		nchar.mouse_entered.connect(func():
			var text = cr.description
			if not Game.unlocked_characters.has(cr): text = str("解锁：", cr.unlock_description)
			character_description.text = text
		)
		nchar.mouse_exited.connect(func():
			character_description.text = ""
		)
		nchar.rseed = i / character_resources.size()
		i += 1.0
		
## 选好模式再去选角色
func start_run(mode: int):
	Game.game_mode = mode
	select_character()

func select_character():
	character_select.set_visible(true)
	buttons_container.set_visible(false)
	title.set_visible(true)
	
func return_to_title():
	ruleset_picker.close()
	character_select.set_visible(false)
	leader_board_container_control_container.set_visible(false)
	settings_container.set_visible(false)
	buttons_container.set_visible(true)
	title.set_visible(true)
	
## 打开难度选择面板。面板在正中，会压住标志，所以按钮和标志都先藏起来
func show_rulesets():
	buttons_container.set_visible(false)
	title.set_visible(false)
	ruleset_picker.open()
	
func show_settings():
	buttons_container.set_visible(false)
	settings_container.set_visible(true)
	
func show_leaderboard():
	leader_board_container_control_container.set_visible(true)
	leader_board_container_control.update()
	buttons_container.set_visible(false)
	title.set_visible(false)
	

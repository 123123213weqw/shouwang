class_name Main extends Node3D

@onready var grid: Grid = $Grid
@onready var character: Character = $Character
@onready var camera_3d: Camera3D = $Camera3D
@onready var combo_label: Label = $CanvasLayer/Control/ComboControl/ComboLabel
@onready var combo_control: ComboControl = $CanvasLayer/Control/ComboControl
@onready var colors: Colors = $Colors
@onready var score_label: Label = $CanvasLayer/Control/Control/ScoreLabel
@onready var level_label: Label = $CanvasLayer/Control/LevelLabel
@onready var character_moves_left_label: Label3D = $Character/SpriteContainer/CharacterMovesLeftLabel
@onready var unlock_control_container: UnlockControlContainer = $CanvasLayer/Control/UnlockControlContainer
@onready var final_score_control: FinalScoreControl = $CanvasLayer/Control/FinalScoreControl
@onready var pause_menu: Control = $CanvasLayer/Control/Menu
@onready var hud_return_button: Button = $CanvasLayer/Control/HudReturnButton
@onready var leader_board_container_control: LeaderBoardContainerControl = $CanvasLayer/Control/FinalScoreControl/LeaderBoardContainerControl
@onready var water: MeshInstance3D = $Water

const FISH = preload("res://scenes/fish.tscn")
const COMBO = preload("res://scenes/combo.tscn")
const HEART = preload("res://scenes/heart.tscn")
const HEART_LOSS = preload("res://scenes/heart_loss.tscn")
const BUTTON := preload("res://scenes/uis/button.tscn")

@export var levels: Array[LevelResource]
var score := 0
var score_display := 0.0
var credits = 10.0
var combo := 0

var max_combo := 10.0
var moves_left := 10
var max_moves_left := 10
var max_move_distance := 1.0
var max_combo_move_distance := 2.0
var move_per_combo := 0.2
var magnet_power := 0.0
var temporary_mov_distance := 0.0
var credits_gain = 1.0

# 没有角色加成、没有道具时的数值（reset_upgrades 回到的就是这些）
const BASE_MAX_MOVE_DISTANCE := 1.0
const BASE_MOVE_PER_COMBO := 0.2
const BASE_MAX_COMBO_DISTANCE := 2.0
const BASE_CREDITS_GAIN := 0.6
const BASE_UPGRADE_CHANCE := 0.1

var ruleset: Ruleset                 # 这一局用的难度（标题页里选的）
var versus: VersusBase               # 对战类的玩法（scripts/versus/）：进了对战的局才有，平时是空
var free_moves := false               # 跳格子不花步数。对战里有的玩法这样

## 技能选目标：有的技能要在棋盘上自己挑一格（守夜人点灯、钓叟收灯）。按下技能先进这个状态，
## 候选格子亮起来；方向键在候选之间挪，A / 空格 确认，B / Esc 取消（选的时候不扣充能）。
## 鼠标直接点候选格子也算确认。选够了才算用掉
enum Aim { NONE, PLACE, COLLECT }
var aiming := Aim.NONE
var aim_left := 0                    # 还要选几格
var aim_list: Array = []             # 现在能选的格子
var aim_index := 0                   # 方向键选中的是第几个
var _aim_label: Label
var current_deal: Dictionary = {}    # 开局摆好的那一局（河灯开局摆好的档里用）；空 = 这一关是边收边刷的
var _thing_resources: Dictionary = {}   # 摆棋时路线上每样东西用哪个资源（键是 BoardGen.Thing 的编号）
var _cell_tiles: Dictionary = {}        # 格子坐标（整数）→ Tile
var _cell_parity := Vector2i.ZERO

var level_reach_bonus := 0.0         # 草鞋：这一关每一跳多跳这么远（过关清零）
var shields := 0                     # 斗笠：还能挡几次踩空
var level_missteps := 0              # 这一关踩空了几次
var level_max_combo := 0.0           # 这一关连击到过多少
var level_start_score := 0           # 这一关开头的分数和步数：原地重来的时侯退回到这里
var level_start_moves := 0
var level_retries := 0               # 这一关重来了几次
var held_lamps := 0                  # 手里的灯：可以放到够得着的空格上补救（规矩"手里的灯"，ruleset.hold_lamps）
var _placed := {}                    # 放出去的灯所在的格子 -> 那盏灯。放出去的灯捡起来不加连击
var wind_dir := Vector2i.ZERO        # 这一关的风往哪边吹（格子坐标：x 向右、y 朝镜头这边）。没有风向这条规矩的时侯是零
var _wind_initial := {}              # 这一局里每一关头一个试的风向（关数 → 方向）
var _wind_by_level := {}             # 这一局里每一关最后刮的风向（关数 → 方向）：摆不出来换过方向的以它为准
var night_on := false                # 夜巡的蜡烛是不是在烧：这一关载入完了、人在玩的时侯才烧
var night_left := 0.0                # 蜡烛还能烧多久（秒）
var night_hold := false              # 排查用：让蜡烛停住不烧（拍截图用，见 pad_adapter.debug_night_pause）。玩法不碰它
var rule_hud: RuleHud                # 左上角的旗子（风向）和蜡烛（夜巡）：规矩打开了才看得见
var pause_stepper: DifficultyStepper # 暂停菜单里的"难度 ‹ 中等 ›"：点一下换一档
var over_stepper: DifficultyStepper  # 没过的结算面板上的"‹ 困难 ›"
var over_note: Label                 # 结算面板标题下面的一行小字：现在的难度、还能再守几次
var run_ruleset: Ruleset             # 这一局用过的最低一档：成绩记在它名下（半路调低过的，不算高一档的成绩）
var _pending_note := ""              # 关了暂停菜单再弹的说明（换过难度的时侯："这一关从头来"），菜单开着时弹了也看不见
var level_serial := 0                # 每载入一关加一：自动试玩的机器人靠它知道换关了
var level_ready := false             # 这一关载入完了（幕布掀开、灯都摆好了）

var is_combo : bool : 
	get: return combo > 1
var last_color: Color

# 无尽模式的随机数来源：每次进游戏都不一样
var endless_rng := RandomNumberGenerator.new()

func is_endless() -> bool:
	return Game.game_mode == Game.GameMode.ENDLESS

## 这一局的第一关
func first_level() -> LevelResource:
	if versus != null: return versus.first_level()
	if is_endless(): return endless_level(0)
	return levels[current_level_index]

## 无尽模式第 n 关（从 0 数起）的参数。棋盘本身由 BoardGen 按同一个 n 生成。
func endless_level(n: int) -> LevelResource:
	var p := BoardGen.params(n)
	var res := LevelResource.new()
	res.level_name = "长夜"
	res.fish_before_end_portal = p.fish
	res.starting_credits = p.credits
	# 越守越深：从石绿（色相 0.46）一路挪到朱砂（色相 0.02），24 关走完，之后一直是朱砂
	res.base_color = Color.from_hsv(0.46 - minf(n, 24.0) / 24.0 * 0.44, 0.74, 0.62)
	return res

# 镜头：朝向和俯角沿用场景里摆好的，只按棋盘的宽度决定离棋盘多远（见 fit_camera）
var camera_forward := Vector3.FORWARD
var camera_base_dist := 0.0   # 场景里镜头到棋盘平面的距离，也是离得最近的时候
var camera_focus_z := 0.0     # 镜头正对着棋盘平面上的哪一点（z 坐标）
var camera_dist := 0.0
var camera_slack := 0.0       # 镜头左右最多跟着主角挪多远
const CAMERA_SLACK := 1.2
const CAMERA_MARGIN := 1.5    # 镜头挪到头时，棋盘的边离画面边缘至少留这么远

## 记下场景里摆的镜头：它看着棋盘平面上的哪一点、离多远
func setup_camera():
	camera_forward = -camera_3d.global_transform.basis.z
	camera_base_dist = camera_3d.global_position.y / (-camera_forward.y)
	camera_focus_z = camera_3d.global_position.z + camera_forward.z * camera_base_dist

## 按这一关棋盘的宽度决定镜头离棋盘多远：离镜头最近的一行，两端也要在画面里，整张棋盘才看得全。
## 宽棋盘比默认距离远一些，窄棋盘就用场景里原来的距离
func fit_camera():
	if grid.tiles.is_empty(): return
	var half_width := 0.0
	var near_z := -1e9
	for tile in grid.tiles.values():
		half_width = maxf(half_width, absf(tile.global_position.x))
		near_z = maxf(near_z, tile.global_position.z)
	half_width += grid.tile_size.x * 0.5
	near_z += grid.tile_size.y * 0.5
	var view: Vector2 = get_viewport().get_visible_rect().size
	# 画面里某一行能看到的半宽 = 纵横比 × tan(半视角) × 镜头到这一行的视距
	var wide: float = view.x / view.y * tan(deg_to_rad(camera_3d.fov) * 0.5)
	var to_near: float = (near_z - camera_focus_z) * (-camera_forward.z)
	# 镜头跟着主角最多挪 camera_follow 那么远（棋盘比这还窄就全程跟着走）；
	# 挪到头的时候，棋盘的边离画面边缘还要留出 CAMERA_MARGIN
	var camera_follow: float = minf(half_width, CAMERA_SLACK)
	camera_dist = maxf((half_width + camera_follow + CAMERA_MARGIN) / wide + to_near, camera_base_dist)
	camera_slack = camera_follow
	camera_3d.global_position.y = -camera_forward.y * camera_dist
	camera_3d.global_position.z = camera_focus_z - camera_forward.z * camera_dist

## 镜头跟着主角左右走，但最多挪 camera_slack：再挪棋盘的边就要出画面了
func camera_target_x() -> float:
	var pos = (get_viewport().get_mouse_position() / Vector2(get_viewport().size)) - Vector2.ONE / 2.0
	return clampf(character.global_position.x + pos.x * 8.0, -camera_slack, camera_slack)

@export_category("Fishes")
@export var fish_before_end_portal := 5
var current_fish_count := 0
var end_portal_instance: Portal
@export var fishes: Array[ObjectResource]
@export var upgrades: Array[ObjectResource]
@export var end_portal: ObjectResource
@export var fish_level := 1.05;
@export var upgrade_chance := 0.1;

var upgrade_random: FixedRandom
var current_level_index = 0
var current_level: LevelResource

var available_upgrades : Array[ObjectResource]

@export_category("Actions")
@onready var active_control: ActiveControl = $CanvasLayer/Control/ActiveControl
@onready var menu: SettingsMenu = $CanvasLayer/Control/Menu      # 暂停菜单（Esc）。它并不真的暂停游戏，只是挡在前面
var is_free_move := false
var tutorial: Tutorial           # 新手教程（放在界面层的最上面）

var start_time := 0.0
var water_strength := 0.0

func _ready() -> void:
	upgrade_random = FixedRandom.new()
	# 对战类的玩法：选了哪一个记在 Game.versus 里，没选就是空。它得在载入关卡之前就挂上
	versus = VersusBase.create(Game.versus)
	# 对战的局不套标题页上选的难度（步数的加减、风向、夜巡、手里的灯都不算数）：每种对战自己的数在 resources/versus/ 里。
	# 所以给它一套什么都不开的规矩；摆河灯照旧是开局摆好
	if versus != null:
		ruleset = Ruleset.new()
		ruleset.hold_per_coin = 0            # 铜钱不给手里的灯
	else:
		ruleset = Game.ruleset
		if ruleset == null: ruleset = Ruleset.new()
	run_ruleset = ruleset
	if versus != null: add_child(versus)
	_load_thing_resources()
	# 新手教程放在界面层的最后面，画在所有界面之上
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.main = self
	$CanvasLayer/Control.add_child(tutorial)
	hud_return_button.icon = Tutorial.icon_texture(hud_return_button.icon)
	hud_return_button.pressed.connect(_open_pause_menu)
	for overlay in [pause_menu, final_score_control, tutorial.card, SceneManager.scene_transition_control]:
		overlay.visibility_changed.connect(_update_hud_return_visibility)
	endless_rng.randomize()
	character.moved.connect(handle_movement)

	active_control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
			trigger_active_effect()
	)

	max_moves_left = maxi(Game.selected_character.max_moves_left + ruleset.moves_add, 1)
	moves_left = max_moves_left
	setup_camera()
	# 左上角的旗子和蜡烛要在第一关载入之前就建好：载入的时侯就要告诉它这一关刮什么风
	_add_rule_hud()
	load_level(first_level())
	reset_upgrades()
	load_character(Game.selected_character)
	reset_active_charges()
	bind_character_unlocks()
	get_viewport().size_changed.connect(fit_camera)
	_add_retry_button()
	_add_pause_stepper()
	_add_over_panel_bits()

	start_time = get_time()


## 关卡左上角的弯箭头打开暂停菜单。
## 不直接回标题页：手柄的 A 既是放技能又是点光标停着的按钮，光标停在它上面的时侯想放技能，一局就没了
func _open_pause_menu() -> void:
	if pause_menu == null or pause_menu.visible: return
	if tutorial != null and tutorial.card_open(): return      # 新手卡片开着：和按 Esc 一样，先不动
	pause_menu.visible = true

func _update_hud_return_visibility() -> void:
	hud_return_button.visible = (
		level_ready
		and not pause_menu.visible
		and not final_score_control.visible
		and not tutorial.card_open()
		and not SceneManager.scene_transition_control.visible
	)


func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("ui_up"):
		#next_level()
	#if event.is_action_pressed("ui_down"):
		#Game.clear()
	#if event.is_action_pressed("ui_right"):
		#gain_combo(1)
	#if event.is_action_pressed("ui_left"):
		#reset_combo()
	if aiming != Aim.NONE:
		# 选目标的时候：方向键在候选之间挪，A / 空格 确认，B / Esc 取消
		if event.is_action_pressed("ui_cancel"):
			aim_cancel()
			return
		if event.is_action_pressed("Power") and can_use_skill():
			aim_confirm()
			return
		if event.is_action_pressed("MoveRight") or event.is_action_pressed("MoveBack"):
			aim_step(1)
			return
		if event.is_action_pressed("MoveLeft") or event.is_action_pressed("MoveForward"):
			aim_step(-1)
			return
		return
	if event.is_action_pressed("Power") and can_use_skill():
		trigger_active_effect()
	# 放一盏手里的灯（键盘 E，手柄 X）。只有这一档给了手里的灯才管用
	if event.is_action_pressed("PlaceLamp"):
		place_lamp()

## 现在能不能放技能。手柄的 A 键既是"放技能"，又是"点屏幕上的按钮"（见 pad_adapter）：
## 不拦一下的话，在暂停菜单、结算面板、新手卡片上按 A 想确认，技能会被顺带放掉。
## 菜单开着的时候不放；手柄的光标（或者鼠标）正停在某个按钮上、要按的是那个按钮，也不放
func can_use_skill() -> bool:
	if final_score_control.visible: return false
	if tutorial != null and tutorial.card_open(): return false
	if pause_menu != null and pause_menu.visible: return false      # 暂停菜单（场景里的 Menu）：在它上面按 A 是点按钮
	if get_viewport().gui_get_hovered_control() is BaseButton: return false
	return true
		
func load_character(res: CharacterResource):
	max_combo += res.max_combo
	#max_moves_left += res.max_moves_left
	max_move_distance += res.max_move_distance
	max_combo_move_distance += res.max_combo_move_distance
	move_per_combo *= res.move_per_combo
	magnet_power += res.magnet_power
	temporary_mov_distance += res.temporary_mov_distance
	credits_gain *= res.credits_gain
	character.load_resource(res)
	
	active_control.charges_control.max_charges = res.active_cooldown
	active_control.charges_control.build()
	active_control.charges_control.update()
	active_control.update()
	active_control.active_effect_sprite.material.set("shader_parameter/texture_albedo", res.active_effect_sprite)
	
	available_upgrades = upgrades.filter(func(u): return not res.banned_upgrades.has(u))
	

		
func next_level():
	if versus != null and versus.next_board(): return      # 对战：接下来怎样由它定
	print("Level ", current_level_index, " : ", get_time() - start_time)
	start_time = get_time()
	current_deal = {}
	if is_endless():
		# 长夜没有通关：一直往下走。步数带过去、每更补一步，压力就在这儿
		current_level_index += 1
		if ruleset.endless_carry:
			moves_left = mini(moves_left + 1 + ruleset.moves_bonus, max_moves_left + ruleset.moves_cap_add)
		else:
			moves_left = max_moves_left
		update_moves_left()
		load_level(endless_level(current_level_index))
		reset_upgrades()
		load_character(Game.selected_character)
		return
	if current_level_index + 1 >= levels.size():
		Game.complete_run(Game.selected_character)
		end_game()
		final_score_control.game_over.set_visible(false)
		final_score_control.completed.set_visible(true)
		# 通关了：没有"再守"、也不用换难度
		over_note.visible = false
		over_stepper.visible = false
		combo = 10
		for tile in grid.tiles.values():
			tile.bump_strength = 10.0
		return
	current_level_index += 1
	if ruleset.moves_carry:
		# 步数带过去：过关补几步，最多比上限多出 moves_cap_add 步（都是 .tres 里的数）
		moves_left = mini(moves_left + ruleset.moves_bonus, max_moves_left + ruleset.moves_cap_add)
	else:
		moves_left = max_moves_left
	load_level(levels[current_level_index])
	reset_upgrades()
	load_character(Game.selected_character)

## 巡夜里一关没过：原地再来一次。分数和步数退回这一关的开头；灯还是原来那一局（练的就是它）
## 这关还能不能重来：能重来、而且没用完次数
func can_retry() -> bool:
	if is_endless() or ruleset == null or not ruleset.retry_level: return false
	if ruleset.retry_max > 0 and level_retries >= ruleset.retry_max: return false
	return true

func retry_level() -> void:
	if not can_retry(): return
	if current_level_index < 0 or current_level_index >= levels.size(): return
	final_score_control.set_visible(false)
	level_retries += 1
	score = level_start_score
	score_display = float(score)
	moves_left = maxi(level_start_moves, 1)
	reset_combo()
	current_deal = {}
	load_level(levels[current_level_index])
	reset_upgrades()
	load_character(Game.selected_character)

## 结算面板上最上面加一个"再守这一关"（巡夜、而且这一档允许重来的时侯才露面）。
## 按钮上只写这五个字：左下这一栏只有三百来像素宽，再长就压到右边的纪录列表上（困难档写过"（还剩 3 次）"，就压上了）。
## 还剩几次写在标题下面那行小字里（见 _over_note_text）
func _add_retry_button() -> void:
	var retry: Button = BUTTON.instantiate()
	retry.name = "RetryLevelButton"
	retry.text = "再守这一关"
	retry.pressed.connect(retry_level)
	final_score_control.buttons_container.add_child(retry)
	final_score_control.buttons_container.move_child(retry, 0)
	retry.visible = false

## 暂停菜单里"继续"底下加一行"难度 ‹ 中等 ›"：玩到一半想换难度，在这儿点一下就行，不用退回标题页
func _add_pause_stepper() -> void:
	pause_stepper = DifficultyStepper.new(54, true, true)
	pause_stepper.name = "PauseDifficulty"
	menu.buttons_container.add_child(pause_stepper)
	menu.buttons_container.move_child(pause_stepper, 1)
	# 多了一行：行间距从 35 收到 24，16:9 的画面（逻辑高度只有 648）里整列才放得下
	menu.buttons_container.add_theme_constant_override("separation", 24)
	pause_stepper.stepped.connect(_on_pause_stepped)
	# 对战的局不分难度（它自己的数在 resources/versus/ 里）：菜单里不放这一行
	pause_stepper.visible = versus == null
	# 换了难度以后这一关在菜单背后从头载入，说明等按了"继续"再弹（菜单开着的时候弹在棋盘上，被压暗的板子挡着看不见）
	menu.resume_game_button.pressed.connect(func() -> void:
		if _pending_note == "": return
		popup(_pending_note)
		_pending_note = ""
	)

## 没过的结算面板上：加减器一行（排在"再守这一关"后面），标题下面一行小字
func _add_over_panel_bits() -> void:
	# 左下这一栏只有三百来像素宽、右边紧挨着纪录列表：字小一号，"难度"两个字再小一号，箭头窄一点，都挤在一行里
	over_stepper = DifficultyStepper.new(40, true, false, 28, 46, 10)
	over_stepper.name = "OverDifficulty"
	final_score_control.buttons_container.add_child(over_stepper)
	final_score_control.buttons_container.move_child(over_stepper, 1)
	over_stepper.stepped.connect(_on_over_stepped)

	over_note = Label.new()
	over_note.name = "OverNote"
	# 标题（"灯火暗了"）占 y 33..126，小字紧挨在它下面，横着居中
	over_note.anchor_left = 0.5
	over_note.anchor_right = 0.5
	over_note.offset_left = -420.0
	over_note.offset_right = 420.0
	over_note.offset_top = 126.0
	over_note.offset_bottom = 166.0
	var settings := LabelSettings.new()
	settings.font = character_moves_font() if character_moves_font() != null else Tutorial.FONT
	settings.font_size = 28
	settings.font_color = Color(0.94, 0.96, 0.92)
	over_note.label_settings = settings
	over_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	over_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_note.visible = false
	final_score_control.add_child(over_note)


func _process(delta: float) -> void:
	camera_3d.global_position.x = lerp(camera_3d.global_position.x, camera_target_x(), delta * 2.0)
	score_display = lerp(score_display, float(score), delta * 5.0)
	score_label.text = str(int(ceil(score_display)))
	
	water_strength = lerp(water_strength, clamp(combo/10.0, 0.0, 1.0), delta)
	if not Game.visuals_value: water_strength = 0.0
	water.material_override.set("shader_parameter/amplitude", 0.3 + water_strength * 0.3)
	water.material_override.set("shader_parameter/speed", 1.0 + water_strength * 0.2)
	water.material_override.set("shader_parameter/frequency", 0.1 + water_strength * 0.2)

	# 暂停菜单开着的时候把顶上的关卡名藏起来：菜单里多了一行加减器，第一行"继续"正好压在它上面。
	# 菜单收回去、也没出结算面板的时侯再露出来（结算面板出来时它是藏着的，见 end_game）
	if menu.visible: level_label.visible = false
	elif not final_score_control.visible: level_label.visible = true

	# 夜巡：蜡在烧的时侯每秒短一截；烧完了最远的一盏灯灭掉，蜡重新长回一段。
	# 人没法玩的时侯蜡不烧（见 _candle_burning）
	if night_on and ruleset != null and _candle_burning():
		night_left -= delta
		if night_left <= 0.0:
			night_left = ruleset.night_every
			_night_extinguish()
	if rule_hud != null and ruleset != null and ruleset.night_watch:
		rule_hud.set_night(night_left / maxf(ruleset.night_seconds, 0.001))
	
func gain_score(value):
	score += value * (combo + 1.0)
	#score_label.text = str(score)
	on_score.emit()

func gain_combo(value):
	combo = clamp(combo + value, 0, max_combo)
	level_max_combo = maxf(level_max_combo, combo)
	combo_control.set_combo(combo)
	if combo > 1:
		var new_combo := COMBO.instantiate() as Combo
		add_child(new_combo)
		new_combo.set_combo(combo)
		new_combo.global_position = character.global_position
	on_combo.emit()
	
func reset_combo():
	combo = 0
	combo_control.clear()
	
func reset_active_charges():
	active_control.charges_control.charges = 0
	active_control.charges_control.update()
	active_control.update()

func update_tiles_color():
	var character_pos = Vector2(character.global_position.x, character.global_position.z)
	# 草鞋加的距离（level_reach_bonus）这一关一直算数
	var max_distance = min(combo * move_per_combo, max_combo_move_distance) + max_move_distance + 0.1 + temporary_mov_distance + level_reach_bonus
	# 刚离开的那个格子总是能跳回去：否则斜跳到一个没有相邻格子的空格上，连击一清零就被困死了
	var back_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	for tile in grid.tiles.values():
		# 格子上指着的灯节点已经不在了（收走以后释放的），这个引用一并清掉，免得别的代码再拿它当灯用
		if tile.object and not is_instance_valid(tile.object): tile.object = null
		var tile_pos = Vector2(tile.global_position.x, tile.global_position.z)
		# 有风向的规矩时顺风跳得远、逆风跳得近：朝这一格的方向能跳多远
		var in_reach = tile_pos.distance_to(character_pos) / grid.tile_size.x <= max_distance
		if wind_dir != Vector2i.ZERO:
			in_reach = tile_pos.distance_to(character_pos) / grid.tile_size.x <= reach_toward(character_pos, tile_pos)
		# 步数是 0 以后，只有不花步数的格子还能跳
		var affordable = free_moves or moves_left > 0 or step_is_free(tile)
		tile.is_available = tile.is_landable() and (not tile.object or tile.object.is_available()) and tile != character.target_tile and (in_reach or tile == back_tile) and affordable
		tile.update_color()
		tile.is_last_position = false
	if active_control.is_charged and Game.selected_character.active_effect == CharacterResource.ActiveEffect.ReturnToLastPosition:
		var tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
		if tile: tile.is_last_position = true
	if versus != null: versus.filter_tiles()
	if aiming != Aim.NONE:
		# 选目标：只有候选格子亮，其中方向键选中的那个最亮。别人一格都不亮
		aim_list = aim_candidates(aiming)
		aim_index = clampi(aim_index, 0, maxi(aim_list.size() - 1, 0))
		var chosen: Tile = aim_list[aim_index] if not aim_list.is_empty() else null
		for tile in grid.tiles.values():
			tile.is_available = aim_list.has(tile)
			tile.is_hovered = tile == chosen
			tile.aim_raise = 0.45 if tile == chosen else 0.0     # 选中的那一格抬起来、染成烛火色：一眼看出选的是哪个
			tile.aim_pick = tile == chosen

## 现在能跳多远（格）：连击、草鞋、纸伞都算上
func _reach_now() -> float:
	return min(combo * move_per_combo, max_combo_move_distance) + max_move_distance + 0.1 + temporary_mov_distance + level_reach_bonus

## 从 from 跳到 to 能跳多远（格），两个都是世界坐标里的 (x, z)。有风向的规矩时顺风远、逆风近；没有风就是 _reach_now()
func reach_toward(from: Vector2, to: Vector2) -> float:
	if wind_dir == Vector2i.ZERO or ruleset == null: return _reach_now()
	return BoardGen.wind_reach(_reach_now(), to - from, Vector2(wind_dir), ruleset.wind_bonus, ruleset.wind_penalty, ruleset.wind_floor)

## 现在从脚下跳到这一格够不够得着（不算"刚离开的格子总能跳回去"那一条）
func can_jump_to(tile: Tile) -> bool:
	var here := Vector2(character.global_position.x, character.global_position.z)
	var there := Vector2(tile.global_position.x, tile.global_position.z)
	return there.distance_to(here) / grid.tile_size.x <= reach_toward(here, there)

## 跳到这一格花不花步数：上面有东西（灯、道具、开了的水车）都不花，还没用过的补给格也不花
func step_is_free(tile: Tile) -> bool:
	if free_moves: return true
	if tile.object != null: return tile.object.is_available()
	if tile.is_spring_ready(): return true
	return portal_open_free()

## 水车开了、而且这一档允许：这以后踩空格不扣步、不清连击
func portal_open_free() -> bool:
	return ruleset != null and ruleset.portal_free and current_fish_count >= fish_before_end_portal

## 这一关的河灯是不是开局就摆好的
func lamps_dealt() -> bool:
	return ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.DEALT and not current_deal.is_empty()

func update_moves_left():
	character_moves_left_label.text = str(moves_left)
	
func handle_movement():
	if versus != null and versus.handle_landing(): return      # 对战：这个玩法自己处理落地
	var serial := level_serial        # 这一跳落下时是哪一关：踩到水车会直接换关
	temporary_mov_distance = 0.0

	# 刚离开的如果是脆格，它现在碎掉
	var left_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	if left_tile and left_tile != character.target_tile: left_tile.break_tile()

	character.target_tile.bump()
	# 夜巡：跳了一下，蜡长回一点（最长是一支蜡的长度）
	if night_on and ruleset != null:
		night_left = minf(night_left + ruleset.night_gain, ruleset.night_seconds)
	if Game.visuals_value:
		for tile in grid.tiles.values():
			tile.bump_strength = (1.0 - min(tile.global_position.distance_to(character.global_position) / 5.0, 1.0)) * ((combo / 10.0) * 2.0)

	if character.target_tile.object:
		var fish := character.target_tile.object as Fish
		handle_loot(fish)
		character.target_tile.object = null
		colors.base_color = fish.color if combo > 1 and fish else colors.default_color
	elif not is_free_move:
		if character.target_tile.is_spring_ready():
			# 补给格：不扣步数，反而加步数（最多超过上限两步）
			moves_left = mini(moves_left + character.target_tile.use_spring(), max_moves_left + 2)
			popup("补给：步数 +%d" % character.target_tile.spring_gain)
		elif portal_open_free():
			pass        # 水车开了：踩空格不算步，也不清连击
		elif shields > 0:
			shields -= 1
			popup("斗笠挡了一下")
		else:
			reset_combo()
			colors.base_color = colors.default_color
			moves_left = maxi(moves_left - 1, 0)
			level_missteps += 1
			tutorial.hint("nomoves" if moves_left == 0 else "empty")
			var heart_loss = HEART_LOSS.instantiate()
			add_child(heart_loss)
			heart_loss.global_position = character.global_position
			character_moves_left_label.scale = Vector3.ONE * 2.0
			character.damage_particles_3d.emitting = true

	# 踩到的是水车：上面 handle_loot 里已经换了关（next_level → load_level）或者通关了，这一关的格子马上就不是现在这些，
	# 后面"还有没有格子能跳"不能再拿旧棋盘算。非常困难档在这儿出过事：通关以后步数是 0、踩空格又要扣步，
	# 旧棋盘上一格能跳的都没有，被判成卡死，通关面板被盖成了"灯火暗了"（2026-11-26，自动试玩查出来的）
	if level_serial != serial or final_score_control.visible:
		is_free_move = false
		return

	update_moves_left()
	update_tiles_color()

	# 一步都走不了（步数是 0 的时侯连不花步数的格子都够不着），也没有正在恢复的脆格：只能结束。
	# 有脆格在恢复的话等一等就还能走，不算卡死
	if not grid.has_available_tile() and not grid.has_broken_tile():
		end_game()

	if not lamps_dealt() and not current_fish_count >= fish_before_end_portal:
		gain_credits()

	if versus != null: versus.after_landing()
	is_free_move = false



func gain_credits():
	var fish_count = grid.get_fish_tiles().size()
	if fish_count <= 2: credits += 1
	credits += credits_gain;
	if credits > 1.0:
		spend_credits()
	else:
		if grid.get_fish_tiles().size() <= 0:
			spawn_fish()
			credits += 5.0
			
## 收走一盏灯或一件道具。where 是它所在的那一格；不给就是主角脚下那一格（水车、钓竿隔空收走的时侯要给）
func handle_loot(fish: Fish, where: Tile = null):
	if not fish.resource: return;

	if fish.resource.effect == ObjectResource.ObjectEffect.None:
		current_fish_count += 1

	if fish.resource.effect: character.add_upgrade(fish.resource)

	last_color = fish.color if fish else colors.default_color

	if not fish: return

	# 放出去的灯被收走：上面已经算作"收了一盏"（水车要的就是这么多盏），但不给技能充能、不给分、不加连击——
	# 它是个落脚点，不是奖励。手里的灯不退
	var where_tile: Tile = where if where != null else character.target_tile
	var was_placed: bool = _placed.has(where_tile)
	if was_placed: _placed.erase(where_tile)

	if not end_portal_instance.is_active and not was_placed:
		active_control.charges_control.gain_charge(fish.resource.charge_gain)
		active_control.update()

	fish.loot()
	if was_placed: return
	if fish.resource.score: gain_score(fish.resource.score)
	if fish.resource.combo and combo < max_combo:
		gain_combo(1)
		combo_control.add_fish(fish)

	# 捡到东西时在头顶弹一行说明
	if fish.resource.description:
		var new_combo := COMBO.instantiate() as Combo
		add_child(new_combo)
		new_combo.set_description(fish.resource.description)
		new_combo.global_position = character.global_position

		if fish.is_portal:
			if level_missteps == 0 and level_max_combo >= 10.0:
				new_combo.set_description("一步未错，连击满堂！")
				gain_score(8)
				on_wooow.emit()
			elif level_missteps == 0:
				new_combo.set_description("一步未错！")
				gain_score(5)
				on_flawless.emit()
				on_perfect.emit()
			elif not lamps_dealt() and grid.get_fish_tiles().size() <= 0:
				new_combo.set_description("一盏不剩！")
				gain_score(3)
				on_perfect.emit()
			else:
				new_combo.set_description("错了 %d 步" % level_missteps)

	match fish.resource.effect:
		ObjectResource.ObjectEffect.SpawnFishes:
			for i in range(0, int(fish.resource.value)):
				spawn_fish(true)
				await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		ObjectResource.ObjectEffect.TemporaryMoveDistance:
			# 纸伞：下一跳加距离（落地下一步就清零，见 handle_movement 开头）
			temporary_mov_distance += fish.resource.value
		ObjectResource.ObjectEffect.GainCombo:
			gain_combo(fish.resource.value)
		ObjectResource.ObjectEffect.AttractFishes:
			for i in range(0, int(fish.resource.value)):
				attract_fishes()
				await get_tree().create_timer(0.5).timeout
		ObjectResource.ObjectEffect.CollectFarestFishes:
			for i in range(0, int(fish.resource.value)):
				var tiles = grid.get_fish_tiles()
				if not tiles.size(): break;
				tiles.shuffle()
				tiles.sort_custom(func(a,b): return a.global_position.distance_to(character.global_position) > b.global_position.distance_to(character.global_position))
				collect_remote(tiles[0])
			update_tiles_color()
		ObjectResource.ObjectEffect.ReachUp:
			# 草鞋：这一关之后每一跳都更远
			level_reach_bonus += fish.resource.value
			update_tiles_color()
		ObjectResource.ObjectEffect.Shield:
			shields += int(fish.resource.value)
		ObjectResource.ObjectEffect.CollectNear:
			# 水车：卷走身边 value 格内的灯
			var here: Tile = character.target_tile
			var reach: float = grid.tile_size.x * fish.resource.value + 0.01
			for tile in grid.tiles.values():
				if tile == here or tile.object == null or not is_instance_valid(tile.object): continue
				var lamp: Fish = tile.object as Fish
				if lamp != null and lamp.is_fish and tile.global_position.distance_to(here.global_position) <= reach:
					collect_remote(tile)
			update_tiles_color()
		ObjectResource.ObjectEffect.RegainMovesLeft:
			moves_left = mini(moves_left + int(fish.resource.value), max_moves_left)
			update_moves_left()
			update_tiles_color()
		ObjectResource.ObjectEffect.AddMoves:
			# 食盒：步数 +value（最多超过上限 3 步）
			moves_left = mini(moves_left + int(fish.resource.value), max_moves_left + 3)
			update_moves_left()
			update_tiles_color()
		ObjectResource.ObjectEffect.SpawnItems:
			# 铜钱：身边刷出 value 件道具。规矩"手里的灯"打开的时侯，手里再多 hold_per_coin 盏
			held_lamps += ruleset.hold_per_coin if ruleset != null else 0
			character.set_held(held_lamps)
			for i in range(0, int(fish.resource.value)):
				spawn_item_near()
				await get_tree().create_timer(0.15).timeout
		ObjectResource.ObjectEffect.EndLevel:
			next_level()

## 不走过去，把那一格上的灯收过来（钓竿、水车用）
func collect_remote(tile: Tile) -> void:
	var fish := tile.object as Fish
	if fish == null: return
	tile.object = null
	handle_loot(fish, tile)
	if not lamps_dealt() and not end_portal_instance.is_active:
		gain_credits()

## 在主角身边刷一件道具（铜钱用）。不再刷出铜钱，免得一个变两个、两个变四个
func spawn_item_near() -> void:
	var pool: Array = available_upgrades.filter(func(u): return u.effect != ObjectResource.ObjectEffect.SpawnItems)
	if pool.is_empty(): return
	var fish := spawn_fish(true)
	if fish == null: return
	fish.load_resource(pool.pick_random())
	fish.is_upgrade = true

## 在主角头顶弹一行字
func popup(text: String) -> void:
	var c := COMBO.instantiate() as Combo
	add_child(c)
	c.set_description(text)
	c.global_position = character.global_position


func spend_credits_spaced():
	while credits >= 1.0:
		spawn_random_spaced_fish()
		credits -= 1.0
		await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		
func spawn_random_spaced_fish():
	var fish = spawn_spaced_fish()
	if fish:
		if upgrade_random.pick():
			fish.load_resource(available_upgrades.pick_random())
			fish.is_upgrade = true
			upgrade_random.reset()
		else:
			fish.load_resource(fishes[min(floor(randf() * fish_level), fishes.size()-1)])
	return fish
	
func spawn_spaced_fish():
	var tiles = grid.tiles.values()
	for tile in tiles: tile.fish_weight = 0.0
	var fish_tiles = tiles.filter(func(a): return a.object)
	for tile in fish_tiles:
		for ntile in grid.get_tile_neighbours(tile):
			ntile.fish_weight += 1.0
			
	#for tile in tiles: tile.label_3d.text = str(tile.fish_weight)
		
	var empty_tiles = tiles.filter(func(a): return not a.object and a != character.target_tile and a.is_landable())
	empty_tiles.shuffle()
	empty_tiles.sort_custom(func(a,b):
		return a.fish_weight < b.fish_weight and randf() < 0.5
	)
	
	if not empty_tiles.size(): return;
	
	var tile : Tile = empty_tiles[0]
	
	var new_fish := FISH.instantiate() as Fish
	add_child(new_fish)
	tile.object = new_fish
	new_fish.global_position = tile.global_position
	return new_fish

func spend_credits():
	while credits >= 1.0:
		spawn_random_fish()
		credits -= 1.0
		await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		
func spawn_object_at_position(resource: ObjectResource, pos:Vector3):
	var tile = grid.tiles[grid.world_to_grid_position(pos)]
	if not tile: return;
	var new_fish := FISH.instantiate() as Fish
	new_fish.global_position = tile.global_position
	add_child(new_fish)
	tile.object = new_fish
	new_fish.load_resource(resource)
	return new_fish
	
## 挑一个空格子放东西。near = true：只在主角现在够得着的格子里挑（技能刷出来的灯、铜钱买来的道具，得拿得到才有用）；
## 否则按档来：边收边刷的玩法里多半挨着灯刷（新的灯接得上），最早的玩法纯随机。没有空格子返回 null
func pick_empty_tile(near: bool = false) -> Tile:
	var here: Tile = character.target_tile
	if here == null: return null
	var empty: Array = []
	var near_tiles: Array = []
	var chain: Array = []
	for tile in grid.tiles.values():
		if tile.object or tile == here or not tile.is_landable(): continue
		empty.append(tile)
		# 够不够得着按风向算：刷出来的东西得真拿得到才有用
		if _reach_between(here, tile):
			near_tiles.append(tile)
		if _next_to_lamp(tile):
			chain.append(tile)
	if near and not near_tiles.is_empty():
		return near_tiles.pick_random()
	if not lamps_dealt() and ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.FLOW and not chain.is_empty() and randf() < ruleset.lamp_flow_chain:
		return chain.pick_random()
	if empty.is_empty(): return null
	return empty.pick_random()

func _next_to_lamp(tile: Tile) -> bool:
	for ntile in grid.get_tile_neighbours(tile):
		if ntile.object and ntile.object.is_fish: return true
	return false

## 刷一盏河灯（放在哪个格子见 pick_empty_tile），返回它；没有空格子返回 null
func spawn_fish(near: bool = false) -> Fish:
	var tile := pick_empty_tile(near)
	if tile == null: return null
	var new_fish := FISH.instantiate() as Fish
	add_child(new_fish)
	tile.object = new_fish
	new_fish.global_position = tile.global_position
	return new_fish

## 边收边刷的玩法里：开局的灯里没有一盏在起点旁边的，就挪一盏过来（第一步总得有灯可收）
func guarantee_opening_lamp() -> void:
	var here: Tile = character.target_tile
	for ntile in grid.get_tile_neighbours(here):
		if ntile.object and ntile.object.is_fish: return
	var lamp: Fish = null
	for tile in grid.tiles.values():
		if tile.object and tile.object.is_fish:
			lamp = tile.object
			break
	if lamp == null: return
	var sides: Array = grid.get_tile_neighbours(here).filter(func(t): return not t.object and t.is_landable())
	if sides.is_empty(): return
	var side: Tile = sides.pick_random()
	grid.get_tile(grid.world_to_grid_position(lamp.global_position)).object = null
	side.object = lamp
	lamp.global_position = side.global_position


func spawn_random_fish()-> Fish:
	var fish = spawn_fish()
	if fish:
		if upgrade_random.pick():
			fish.load_resource(available_upgrades.pick_random())
			fish.is_upgrade = true
		else:
			fish.load_resource(fishes[min(floor(randf() * fish_level), fishes.size()-1)])
	return fish

func reset_upgrades():
	# Upgrades
	max_combo = 10.0
	max_move_distance = base_reach()
	max_combo_move_distance = BASE_MAX_COMBO_DISTANCE
	move_per_combo = BASE_MOVE_PER_COMBO
	magnet_power = 0.0
	temporary_mov_distance = 0.0
	credits_gain = BASE_CREDITS_GAIN
	upgrade_chance = BASE_UPGRADE_CHANCE


func load_level(level: LevelResource):
	upgrade_random.rate = upgrade_chance
	level_serial += 1
	level_ready = false
	_update_hud_return_visibility()

	current_level = level
	if versus != null: level_label.text = versus.title()
	elif is_endless(): level_label.text = str("长夜 · 第 ", current_level_index + 1, " 更")
	else: level_label.text = str("第 ", current_level_index + 1, " 关 · ", level.level_name)

	final_score_control.set_visible(false)
	level_label.visible = true

	await SceneManager.scene_transition_control.open()

	# 棋盘：无尽模式现生成，主线用字符画
	if is_endless():
		grid.load_generated(BoardGen.generate(current_level_index, endless_rng))
	else:
		grid.load_map(current_level.map)

	colors.base_color = level.base_color
	fish_before_end_portal = maxi(1, int(round(level.fish_before_end_portal * ruleset.lamp_scale)))
	credits = level.starting_credits * 1.0

	current_fish_count = 0
	reset_combo()
	last_color = colors.default_color
	# 道具的效果、踩空的次数都从这一关重新算
	level_reach_bonus = 0.0
	held_lamps = ruleset.hold_lamps if ruleset != null else 0
	_placed.clear()
	if held_lamps > 0:
		character.make_held_label(character_moves_font())
	# 这一档手里没有灯的时侯也要写一回：上一个难度留下的"灯 ×N"得擦掉（半路换了难度就会碰到）
	character.set_held(held_lamps)
	shields = 0
	level_missteps = 0
	level_max_combo = 0.0
	level_start_score = score
	level_start_moves = moves_left
	current_deal = {}
	_roll_wind()
	night_on = false
	night_left = ruleset.night_seconds if ruleset != null else 0.0

	# 起点：关卡指定了就用指定的，否则在一个周围至少有三个格子的空格里随机挑一个
	var tile: Tile = grid.start_tile
	if not tile:
		var empty_tiles = grid.get_empty_tiles().filter(func(t):
			return grid.get_tile_neighbours(t).size() > 2
		)
		tile = empty_tiles.pick_random()
	character.set_tile(tile)
	fit_camera()
	camera_3d.global_position.x = camera_target_x()

	# 河灯：开局摆好的一局。摆不出来（不该发生）就退回边收边刷
	var dealt := false
	if (versus == null or versus.uses_deal()) and ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.DEALT:
		dealt = await place_deal(level)

	update_tiles_color()
	update_moves_left()

	water_strength = 0.0

	await SceneManager.scene_transition_control.close()

	if not dealt and (versus == null or versus.uses_deal()):
		# 边收边刷：步数没带满进来的话放一个蒸笼；再按关卡里的资源数刷灯
		if moves_left < max_moves_left:
			var heart_tile = grid.get_empty_tiles().pick_random()
			var heart := HEART.instantiate() as Fish
			add_child(heart)
			heart_tile.object = heart
			heart.global_position = heart_tile.global_position
		await spend_credits()
		if ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.FLOW:
			guarantee_opening_lamp()
		update_tiles_color()

	on_enter_level.emit()
	if versus != null:
		versus.on_level_ready()          # 对战：摆对手、开始计时。平时那套玩法说明不弹
	else:
		# 第一次进游戏：关卡载入完了，先把玩法讲一遍（之后不再弹）
		tutorial.maybe_show_rules()
	level_ready = true
	_update_hud_return_visibility()
	if versus == null:
		# 这几条规矩各提示一次（手里的灯、步数带过关、风向、夜巡），看没看过记在存档里。对战的局没有这些规矩
		tutorial.rule_hints()
		if ruleset != null and ruleset.night_watch: night_on = true

## 现在棋盘上的格子，整理成 BoardGen 认的样子（格子坐标是整数，从 0 起）。
## 顺带记下每个坐标对应哪个 Tile，摆完东西好往格子上放
func current_board() -> Dictionary:
	var lo := Vector2(1e9, 1e9)
	for pos in grid.tiles:
		lo.x = minf(lo.x, pos.x)
		lo.y = minf(lo.y, pos.y)
	# 格子的坐标可能都是整数，也可能都带半个（棋盘的宽或高是单数时整体错开半格）：先把小数部分对齐
	_cell_parity = Vector2i(absi(roundi(lo.x * 2.0)) % 2, absi(roundi(lo.y * 2.0)) % 2)
	var cells: Dictionary = {}
	_cell_tiles = {}
	for pos in grid.tiles:
		var t: Tile = grid.tiles[pos]
		var cell := Vector2i(int((roundi(pos.x * 2.0) - _cell_parity.x) / 2.0), int((roundi(pos.y * 2.0) - _cell_parity.y) / 2.0))
		cells[cell] = t.tile_type
		_cell_tiles[cell] = t
	return {"cells": cells, "portal": to_cell(character.target_tile.global_position) if false else to_cell(end_portal_instance.global_position), "start": to_cell(character.target_tile.global_position)}

## 格子坐标 → 那一格的 Tile（current_board 记下的对应关系）
func tile_at_cell(cell: Vector2i) -> Tile:
	return _cell_tiles.get(cell)

## 世界坐标 → 格子坐标（current_board 用的那一套）
func to_cell(world: Vector3) -> Vector2i:
	var g := grid.world_to_grid_position(world)
	return Vector2i(int((roundi(g.x * 2.0) - _cell_parity.x) / 2.0), int((roundi(g.y * 2.0) - _cell_parity.y) / 2.0))

## 角色本身能跳多远（不算连击、道具）：游戏里原来的那个数，加上这一档给加的（Ruleset.reach_add，简单档是 0.7）。
## 真跳的时候（reset_upgrades）和摆棋的时候（deal_options）用的都是它，摆出来的路线才真的是人跳得到的
func base_reach() -> float:
	return BASE_MAX_MOVE_DISTANCE + (ruleset.reach_add if ruleset != null else 0.0)

## 这一关怎么摆：按关卡进度定出基础的难度，再按难度的规矩加减；再按角色能跳多远算
func deal_options(lamps: int) -> Dictionary:
	var n := maxi(1, int(round(lamps * ruleset.lamp_scale)))
	var opt: Dictionary = BoardGen.endless_opt(current_level_index, n) if is_endless() else BoardGen.campaign_opt(current_level_index, n)
	# 难度里的几条规矩怎么改摆法（风向、贴极限、道具件数、最后一跳够不够得着水车）都在 BoardGen.ruleset_opt 里，
	# 算过关率的 tools/tier_rates.gd 用的也是它
	opt = BoardGen.ruleset_opt(opt, ruleset, wind_dir)
	var ch := Game.selected_character
	opt.reach = BoardGen.reach_params(base_reach() + ch.max_move_distance, BASE_MOVE_PER_COMBO * ch.move_per_combo, BASE_MAX_COMBO_DISTANCE + ch.max_combo_move_distance)
	if versus != null: versus.tune_deal(opt)          # 对战：摆法按它的规矩改
	return opt

## 摆一局河灯：巡夜里每一关是固定的一局（练的就是它），长夜每次现摆。摆好了返回 true
func place_deal(level: LevelResource) -> bool:
	var board := current_board()
	var seed_value := _level_seed(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := maxi(1, int(round(level.fish_before_end_portal * ruleset.lamp_scale)))
	var base: Dictionary = BoardGen.endless_opt(current_level_index, n) if is_endless() else BoardGen.campaign_opt(current_level_index, n)
	if versus != null: versus.tune_deal(base)      # 对战：灯数、道具、带沟的道具、贴极限、绕路都按它自己的规矩改（数在 resources/versus/）
	# 摆一局，有风向的规矩时连风向一起定：头一个方向摆不出来就换一个方向（见 BoardGen.deal_tiered）。
	# 挑头一个方向要避开上一关头一个试的方向，换方向的时侯尽量避开上一关最后刮的风，都从记下来的表里取
	var picked := BoardGen.deal_tiered(board, base, ruleset, seed_value, _wind_initial.get(current_level_index - 1, Vector2i.ZERO),
		_wind_by_level.get(current_level_index - 1, Vector2i.ZERO))
	var d: Dictionary = picked.deal
	# 规矩"补给格"：按档增减。先按原样摆一次棋拿到路线，再动路线以外的格子——路线上的格子一个都不碰，
	# 那条"一步不错就能收齐"的路才还是原来的样子
	if ruleset != null and ruleset.spring_add != 0 and not d.is_empty():
		_adjust_springs(ruleset.spring_add, d.route, rng)
	if d.is_empty():
		push_warning("这一关摆不出河灯，改用边收边刷：%s" % BoardGen.last_fail)
		return false
	# 风向定了：记下来，旗子转过去
	wind_dir = picked.wind
	_wind_by_level[current_level_index] = wind_dir
	if rule_hud != null: rule_hud.show_wind(wind_dir)
	fish_before_end_portal = int(d.lamps)
	var route: Array = d.route
	var kinds: Array = d.kinds
	var fallback: ObjectResource = _thing_resources.get(BoardGen.Thing.BOX, _thing_resources.get(BoardGen.Thing.LAMP))
	# 一件隔一帧落下：落灯的水声是一串，不是一声响。幕布这时是全遮住的，摆的过程看不见，所以只隔一帧不再多等
	#（原来隔 0.05 秒，最大的一关要多等一秒多）
	for i in route.size():
		var tile: Tile = _cell_tiles.get(route[i])
		if tile == null: continue
		var res: ObjectResource = _thing_resources.get(kinds[i], fallback)
		if res == null: continue
		var fish := FISH.instantiate() as Fish
		add_child(fish)
		fish.global_position = tile.global_position
		tile.object = fish
		fish.load_resource(res)
		fish.is_upgrade = res.effect != ObjectResource.ObjectEffect.None
		await get_tree().process_frame
	current_deal = d
	# 步数没带满进来：在路线以外的空格子上放一个蒸笼
	if moves_left < max_moves_left:
		var free: Array = grid.get_empty_tiles().filter(func(t): return not route.has(to_cell(t.global_position)))
		if not free.is_empty():
			var heart := HEART.instantiate() as Fish
			add_child(heart)
			free[0].object = heart
			heart.global_position = free[0].global_position
	return true

## 按档增减补给格（规矩"补给格"）。delta 大于 0：把路线以外的普通格改成补给格；小于 0：把路线以外的补给格改回普通格。
## 只动 Tile 节点自己的类型；摆棋用的那张表（current_board() 每次现读格子）不用单独同步
func _adjust_springs(delta: int, route: Array, rng: RandomNumberGenerator) -> void:
	var pool: Array = []
	for cell in _cell_tiles:
		var t: Tile = _cell_tiles[cell]
		if cell == to_cell(end_portal_instance.global_position) or route.has(cell): continue
		if t == null or t.object != null: continue
		if (delta > 0 and t.tile_type == Tile.TileType.NORMAL) or (delta < 0 and t.tile_type == Tile.TileType.SPRING):
			pool.append(t)
	# 用这一关自己的随机数打乱，不用全局的：巡夜每一关是固定的一局，补给格也得每次都在同一个地方
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Tile = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var n := mini(absi(delta), pool.size())
	for i in n:
		pool[i].tile_type = Tile.TileType.SPRING if delta > 0 else Tile.TileType.NORMAL
		pool[i].update_color()

## 摆棋时路线上每样东西用哪个资源。斗笠的资源文件还不存在的时侯，摆到斗笠的那一格放食盒
func _load_thing_resources() -> void:
	var paths := {
		BoardGen.Thing.LAMP: "res://resources/fishes/fish.tres",
		BoardGen.Thing.BIG: "res://resources/fishes/big_fish.tres",
		BoardGen.Thing.LOTUS: "res://resources/upgrades/combooo.tres",
		BoardGen.Thing.UMBRELLA: "res://resources/upgrades/umbrella.tres",
		BoardGen.Thing.SHOE: "res://resources/upgrades/shoe.tres",
		BoardGen.Thing.HAT: "res://resources/upgrades/hat.tres",
		BoardGen.Thing.BOX: "res://resources/upgrades/chest.tres",
		BoardGen.Thing.WHEEL: "res://resources/upgrades/portal.tres",
		BoardGen.Thing.COIN: "res://resources/upgrades/clover.tres",
	}
	for kind in paths:
		if ResourceLoader.exists(paths[kind]):
			_thing_resources[kind] = load(paths[kind])




func restart():
	if versus != null: versus.restart_match()      # 对战：先把上一局的胜负清掉
	score = 0
	score_display = 0.0
	current_level_index = 0
	_wind_initial.clear()         # 新的一局：风从第一关重新刮
	_wind_by_level.clear()
	run_ruleset = ruleset         # 新的一局：成绩记在现在这一档名下
	moves_left = max_moves_left
	upgrade_random.reset()
	update_moves_left()
	reset_upgrades()
	load_level(first_level())
	load_character(Game.selected_character)
	reset_active_charges()


## 现在能选哪些格子。PLACE 是身边够得着的空格子；COLLECT 是场上摆着的灯
func aim_candidates(kind: Aim) -> Array:
	if kind == Aim.COLLECT: return grid.get_fish_tiles()
	var out: Array = []
	var here: Tile = character.target_tile
	for tile in grid.tiles.values():
		if tile == here or tile.object or not tile.is_landable(): continue
		if not can_jump_to(tile): continue       # 够不够得着连风向一起算（有风向的规矩时顺风远、逆风近）：放下去得真跳得到
		out.append(tile)
	return out

## 进入选目标。能选的不止一格才进（只有一格没什么可挑的，也照样让玩家确认一下）；一格都没有返回 false
func begin_aim(kind: Aim, count: int) -> bool:
	aim_list = aim_candidates(kind)
	if aim_list.is_empty(): return false
	aiming = kind
	aim_left = count
	aim_index = 0
	_aim_hint()
	update_tiles_color()
	return true

## 方向键在候选之间挪（按到边界就绕回去）
func aim_step(delta: int) -> void:
	if aim_list.size() <= 1: return
	aim_index = posmod(aim_index + delta, aim_list.size())
	update_tiles_color()

func aim_confirm() -> void:
	if aiming == Aim.NONE or aim_list.is_empty(): return
	aim_pick(aim_list[clampi(aim_index, 0, aim_list.size() - 1)])

## 取消：不消耗充能（选的时候本来就没扣）
func aim_cancel() -> void:
	if aiming == Aim.NONE: return
	popup("取消了")
	_finish_aim(false)

## 选中一格：放灯，或者把那盏灯收过来
func aim_pick(tile: Tile) -> void:
	if aiming == Aim.NONE or tile == null or not aim_list.has(tile): return
	if aiming == Aim.PLACE:
		var fish := FISH.instantiate() as Fish
		add_child(fish)
		fish.global_position = tile.global_position
		tile.object = fish
		fish.load_resource(fishes[min(floor(randf() * fish_level), fishes.size() - 1)])
		popup("点了一盏灯")
	else:
		collect_remote(tile)
		popup("收了一盏灯")
	aim_left -= 1
	aim_list = aim_candidates(aiming)
	aim_index = clampi(aim_index, 0, maxi(aim_list.size() - 1, 0))
	if aim_left <= 0 or aim_list.is_empty():
		_finish_aim(true)
	else:
		_aim_hint()
		update_tiles_color()

## 选完了：用掉充能；关掉提示
func _finish_aim(used: bool) -> void:
	aiming = Aim.NONE
	aim_list = []
	if used: reset_active_charges()
	if _aim_label != null: _aim_label.visible = false
	for tile in grid.tiles.values():
		tile.aim_raise = 0.0
		tile.aim_pick = false
	update_tiles_color()

## 选目标时屏幕下方那行提示
func _aim_hint() -> void:
	if _aim_label == null:
		_aim_label = Tutorial.make_label(28, Color(1, 1, 1))
		_aim_label.name = "AimHint"
		_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_aim_label.label_settings.outline_size = 9
		_aim_label.label_settings.outline_color = Color(0.04, 0.06, 0.07)
		_aim_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_aim_label.offset_left = -420.0
		_aim_label.offset_right = 420.0
		_aim_label.offset_top = -232.0
		_aim_label.offset_bottom = -186.0
		$CanvasLayer/Control.add_child(_aim_label)
	var what := "点灯的格子" if aiming == Aim.PLACE else "要收的灯"
	_aim_label.text = "选%s：方向键换，空格/A 确认，Esc/B 取消（还能选 %d 个）" % [what, aim_left]
	_aim_label.visible = true

## 放一盏手里的灯。没给格子：鼠标（接手柄时是光标）正指着哪一格就放哪一格，没指着就挑最能把路接上的一格（见 _place_target）
func place_lamp(tile: Tile = null) -> void:
	if held_lamps <= 0 or character.is_jumping or ruleset == null: return
	# 放一盏要花几步。步数是 0 的时侯放不了（没有步数可花）
	if moves_left < ruleset.hold_cost or ruleset.hold_cost <= 0 and moves_left <= 0:
		popup("步数不够，放不了灯")
		return
	if tile == null: tile = _place_target()
	if tile == null:
		popup("身边没有能放灯的空格")
		return
	if not place_lamp_on(tile):
		popup("这儿放不了灯")

## 把一盏手里的灯放到 tile 上，花 hold_cost 步。放上去的灯踩到算"有灯"（不扣步、不清连击），捡起来算收了一盏，
## 可不给分、不加连击——它是个落脚点，不是奖励。格子得是现在够得着的空格（刚离开的那一格也算）。返回放没放成。
## 自动试玩的机器人也走这一个（它自己挑格子）
func place_lamp_on(tile: Tile) -> bool:
	if held_lamps <= 0 or tile == null or ruleset == null: return false
	var back_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	if tile.object != null or tile == character.target_tile or not tile.is_landable(): return false
	if not tile.is_available and tile != back_tile: return false
	held_lamps -= 1
	character.set_held(held_lamps)
	moves_left = maxi(moves_left - ruleset.hold_cost, 0)
	var lamp := FISH.instantiate() as Fish
	add_child(lamp)
	lamp.global_position = tile.global_position
	tile.object = lamp
	lamp.load_resource(_thing_resources.get(BoardGen.Thing.LAMP))
	_placed[tile] = lamp
	popup("放了一盏灯（还剩 %d 盏）" % held_lamps)
	update_moves_left()
	update_tiles_color()
	return true

## 没指着哪一格的时侯，手里的灯往哪放：现在够得着的空格里，放上去以后"够得着的灯"多出来最多的那一格
##（放下去下一跳就接得上灯的最好）；一样多就放得离脚下近一点
func _place_target() -> Tile:
	var best: Tile = null
	var best_key := Vector2(-1e9, -1e9)
	var back_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	for t in grid.tiles.values():
		if t.object != null or t == character.target_tile or not t.is_landable(): continue
		if not t.is_available and t != back_tile: continue
		if t.is_hovered: return t
		var gain := 0.0
		for u in grid.tiles.values():
			if u.object == null or not u.object.is_fish: continue
			if not can_jump_to(u) and _reach_between(t, u): gain += 1.0
		var key := Vector2(gain, -t.global_position.distance_to(character.global_position))
		if key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y):
			best_key = key
			best = t
	return best

## 站在 from 上（连击、草鞋都和现在一样）跳到 to 够不够得着
func _reach_between(from: Tile, to: Tile) -> bool:
	var a := Vector2(from.global_position.x, from.global_position.z)
	var b := Vector2(to.global_position.x, to.global_position.z)
	return b.distance_to(a) / grid.tile_size.x <= reach_toward(a, b)

## 这一关摆河灯用的随机种子：巡夜里每一关是固定的一局（关卡文件里写了就用它，没写按序号来），长夜每次现抽
func _level_seed(level: LevelResource) -> int:
	if is_endless(): return endless_rng.randi()
	return level.deal_seed if level.deal_seed != 0 else 7000 + current_level_index * 37

## 这一关头一个试的风向（规矩"风向"）：只跟这一关的种子和上一关头一个试的方向有关（BoardGen.level_initial_wind），
## 连着两关不刮同一种风。每一关的都记在这一局里：重来这一关、测试里直接跳到某一关，算出来的都是同一个风。
## 摆河灯的时侯这个方向摆不出来会换一个方向（BoardGen.deal_tiered），换过的记在 _wind_by_level 里，旗子照它转
func _roll_wind() -> void:
	wind_dir = Vector2i.ZERO
	if ruleset != null and ruleset.wind:
		# 前面几关还没算过的（新的一局、或者测试里直接跳到了后面某一关）：从第一关挨个算过来
		for i in range(0, current_level_index + 1):
			if _wind_initial.has(i): continue
			var seed_value: int = endless_rng.randi() if is_endless() else _seed_of(i)
			_wind_initial[i] = BoardGen.level_initial_wind(seed_value, _wind_initial.get(i - 1, Vector2i.ZERO))
			if is_endless(): break
		wind_dir = _wind_by_level.get(current_level_index, _wind_initial[current_level_index])
	if rule_hud != null: rule_hud.show_wind(wind_dir)

## 第 i 关（从 0 数起）摆河灯的种子：关卡文件里写了就用它，没写按序号来
func _seed_of(i: int) -> int:
	var level: LevelResource = levels[i]
	return level.deal_seed if level.deal_seed != 0 else 7000 + i * 37

## 棋盘上还亮着几盏灯（够得着够不着的都算，水车不算）
func _lamps_left() -> int:
	var n := 0
	for tile in grid.tiles.values():
		if tile.object != null and is_instance_valid(tile.object) and tile.object.is_fish: n += 1
	return n

## 还能不能弄出新的灯来：手里还有，或者守夜人的技能充满了（点灯会在身边落下两盏）
func _can_light_lamps() -> bool:
	if held_lamps > 0: return true
	return active_control.is_charged and Game.selected_character.active_effect == CharacterResource.ActiveEffect.SpawnFishes

## 现在夜巡的蜡烛该不该烧：这一关载入完了、人在玩、没有别的东西挡在前面。
## 暂停菜单并不真的暂停游戏（原版就是这样），开着菜单调音量的时侯蜡不能烧；正弹着提示条的时侯也不烧（头一回玩的人要先看提示）。
## 教程卡片开着、结算面板出来了的时侯 night_on 本来就是假的
func _candle_burning() -> bool:
	if night_hold: return false
	if not level_ready or final_score_control.visible: return false
	if tutorial != null and (tutorial.card_open() or tutorial.hinting()): return false
	if menu != null and menu.visible: return false
	return true

## 夜巡：蜡烛烧完了。离主角最远的那盏灯灭掉。河灯是摆好的一局、水车要的盏数不变：剩下的灯不够了，
## 手里也没有、技能也点不出来，这一关就守不住了
func _night_extinguish() -> void:
	var far: Tile = null
	var fd := -1.0
	for tile in grid.tiles.values():
		if tile.object == null or not is_instance_valid(tile.object) or not tile.object.is_fish: continue
		var d: float = tile.global_position.distance_to(character.global_position)
		if d > fd:
			fd = d
			far = tile
	if far == null: return
	var lamp := far.object as Fish
	far.object = null
	_placed.erase(far)
	lamp.go_out()
	popup("夜巡：最远的那盏灯灭了")
	if current_fish_count + _lamps_left() < fish_before_end_portal and not _can_light_lamps():
		night_on = false
		_night_fail()

## 灯灭了、这一关守不住了：等那盏灯灭完（看清楚是哪一盏），再出结算。这中间换了关或者已经结算了就不重复出
func _night_fail() -> void:
	var serial := level_serial
	await get_tree().create_timer(0.9).timeout
	if level_serial != serial or final_score_control.visible: return
	if is_inside_tree(): end_game()

## 左上角的旗子（风向）和蜡烛（夜巡）。放在界面层的最底下：教程卡片压暗的时侯它们也一起暗下去
func _add_rule_hud() -> void:
	rule_hud = RuleHud.new()
	rule_hud.name = "RuleHud"
	$CanvasLayer/Control.add_child(rule_hud)
	$CanvasLayer/Control.move_child(rule_hud, 0)
	var button_rect := hud_return_button.get_rect()
	rule_hud.position = Vector2(button_rect.end.x + 4.0, button_rect.get_center().y)
	rule_hud.setup(ruleset)
	rule_hud.show_wind(wind_dir)

func trigger_active_effect():
	if character.is_jumping: return;
	if not active_control.is_charged: return;
	var ch := Game.selected_character
	# 要在棋盘上挑格子的技能：先进"选目标"，选够了才用掉（选的时候取消不消耗）。
	# 没有能选的格子（身边没空位、场上没灯）就退回原来那样，直接放
	var aiming_skill := false
	if ch.active_effect == CharacterResource.ActiveEffect.SpawnFishes:
		aiming_skill = begin_aim(Aim.PLACE, maxi(int(ch.value), 1))
	elif ch.active_effect == CharacterResource.ActiveEffect.LootFishesForMaxMoves:
		aiming_skill = begin_aim(Aim.COLLECT, maxi(int(ch.value), 1))
	if aiming_skill:
		active_control.trigger_effect_audio.play()
		update_moves_left()
		return
	active_control.trigger_effect_audio.play()
	update_moves_left()

	reset_active_charges()
	match ch.active_effect:
		CharacterResource.ActiveEffect.AddCombo:
			gain_combo(ch.value)
			update_tiles_color()
		CharacterResource.ActiveEffect.SpawnUpgrade:
			credits = 0
			# 货郎：从担子里取一件道具，落在身边够得着的地方
			var fish = spawn_fish(true)
			if fish:
				var upgrade = available_upgrades.pick_random() if not ch.spawned_upgrades.size() else ch.spawned_upgrades.pick_random()
				fish.load_resource(upgrade)
				fish.is_upgrade = true
		CharacterResource.ActiveEffect.SpawnFishes:
			# 守夜人：点灯，两盏新的河灯落在身边够得着的地方
			for i in range(0, int(ch.value)):
				var fish = spawn_fish(true)
				if fish: fish.load_resource(fishes[min(floor(randf() * fish_level), fishes.size()-1)])
				await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		CharacterResource.ActiveEffect.AttractFishes:
			for i in range(0, int(ch.value)):
				attract_fishes()
				await get_tree().create_timer(0.5).timeout
		CharacterResource.ActiveEffect.TemporaryMovementIncrease:
			temporary_mov_distance += ch.value
			combo = floor(combo/2.0)
			combo_control.set_combo(combo)
			update_tiles_color()
		CharacterResource.ActiveEffect.LootFishesForMaxMoves:
			var tiles = grid.get_fish_tiles()
			if tiles.size():
				tiles.shuffle()
				tiles.sort_custom(func(a,b): return a.global_position.distance_to(character.global_position) > b.global_position.distance_to(character.global_position))
				for i in range(0, mini(int(ch.value), tiles.size())):
					var tile = tiles[i]
					if tile and tile.object:
						collect_remote(tile)
				reset_active_charges()
				update_tiles_color()

		CharacterResource.ActiveEffect.ReturnToLastPosition:
			var pos = grid.world_to_grid_position(character.last_position)
			var tile = grid.get_tile(pos)
			is_free_move = true
			character.move_to(tile)



func character_moves_font() -> Font:
	return character_moves_left_label.font if character_moves_left_label != null else null

func get_time():
	return Time.get_ticks_msec() / 1000.0

signal on_enter_level()
signal on_combo()
signal on_score()
signal on_flawless()
signal on_perfect()
signal on_wooow()

func bind_character_unlocks():
	var characters = Game.get_locked_characters()
	for c in characters:
		match c.unlock_type:
			CharacterResource.UnlockType.Level: 
				on_enter_level.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					if current_level_index >= c.unlock_value: unlock_character(c)
				)
			CharacterResource.UnlockType.Combo:
				on_combo.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					if combo >= c.unlock_value: unlock_character(c)
				)
			CharacterResource.UnlockType.Score:
				on_score.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					if score >= c.unlock_value: unlock_character(c)
				)
			CharacterResource.UnlockType.Flawless: 
				on_flawless.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					unlock_character(c)
				)
			CharacterResource.UnlockType.Perfect: 
				on_perfect.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					unlock_character(c)
				)
			CharacterResource.UnlockType.Wooow: 
				on_wooow.connect(func():
					if not current_level_index >= c.unlock_min_level: return;
					if c.unlock_with_character and c.unlock_with_character != Game.selected_character: return;
					unlock_character(c)
				)
			#CharacterResource.UnlockType.FishCount: pass
			#CharacterResource.UnlockType.TotalFishCount: pass
			
func unlock_character(cr: CharacterResource):
	if Game.unlocked_characters.has(cr): return;
	unlock_control_container.display_unlock(cr)
	Game.unlock_character(cr)

func end_game():
	moves_left = 0
	night_on = false

	# 不再上传到网上的排行榜，只和本机的最好成绩比。半路调过难度的，记在这一局用过的最低一档名下
	var run_key := "" if versus != null else Game.record_run(Game.selected_character, score, current_level_index + 1, run_ruleset)

	final_score_control.set_visible(true)
	# 结算的标题（灯火熄了 / 守到天明）和左上角的关卡标签在同一个位置，叠在一起看不清：出结算的时候把关卡标签藏起来
	level_label.visible = false
	final_score_control.game_over.set_visible(true)
	final_score_control.completed.set_visible(false)
	if is_endless(): final_score_control.game_over.text = str("长夜未尽
守到了第 ", current_level_index + 1, " 更")
	else: final_score_control.game_over.text = "灯火暗了"
	_fill_game_over()
	if versus != null:
		# 对战的局：标题换成它的输赢，也不放难度那一行小字和加减器（下面的"再守这一关"也不放）
		final_score_control.game_over.text = versus.result_text()
		over_note.visible = false
		over_stepper.visible = false
	final_score_control.animate()

	# 巡夜里、方案允许的时侯：这一关可以原地再来
	var retry: Node = final_score_control.buttons_container.get_node_or_null("RetryLevelButton")
	if retry: retry.visible = versus == null and not is_endless() and ruleset != null and ruleset.retry_level
	leader_board_container_control.update()
	leader_board_container_control.set_current(run_key)

## 结算面板上跟着难度走的东西："再守这一关"在不在、标题下面那行小字、加减器。
## 出结算的时侯填一遍；结算面板上换了难度（调高一档）再填一遍
func _fill_game_over() -> void:
	var retry: Node = final_score_control.buttons_container.get_node_or_null("RetryLevelButton")
	if retry:
		# 巡夜里、这一档允许、而且次数没用完：这一关可以原地再来
		retry.visible = can_retry()
	over_note.visible = true
	over_note.text = _over_note_text()
	over_stepper.visible = true
	over_stepper.refresh()

## 标题下面那行小字：现在的难度；重来次数有限的档，再说一句还剩几次
func _over_note_text() -> String:
	if ruleset == null: return ""
	var text := "难度　%s" % ruleset.title
	if can_retry() and ruleset.retry_max > 0:
		text += "　　再守这一关还剩 %d 次" % (ruleset.retry_max - level_retries)
	return text

## 换一档难度：delta 是 +1（高一档）或 -1（低一档）。记进存档（下一局也用它），左上角的旗子、蜡烛跟着换。
## 到头了（已经是最高或最低一档）就什么都不做，返回 false。这一关要不要从头来由调用的人决定
func change_difficulty(delta: int) -> bool:
	var i := Game.rulesets.find(ruleset)
	if i < 0: return false
	var j := clampi(i + delta, 0, Game.rulesets.size() - 1)
	if j == i: return false
	var r: Ruleset = Game.rulesets[j]
	Game.select_ruleset(r)
	ruleset = r
	# 步数上限跟着难度的加减变（和 _ready 里一样算）
	max_moves_left = maxi(Game.selected_character.max_moves_left + r.moves_add, 1)
	if r.tier < run_ruleset.tier: run_ruleset = r
	rule_hud.setup(r)
	pause_stepper.refresh()
	over_stepper.refresh()
	return true

## 这一关按现在的难度从头来：分数退回这一关的开头；步数按新难度的规矩给
##（带过关的档带着这一关开头带的步数，最多到它的上限；别的档是满步数）。
## 换了难度用这个，不是 retry_level：那个会把重来次数加一，步数也还是旧难度的
func restart_level_under(r: Ruleset) -> void:
	if is_endless():
		if current_level_index < 0: return
	elif current_level_index < 0 or current_level_index >= levels.size():
		return
	final_score_control.set_visible(false)
	score = level_start_score
	score_display = float(score)
	reset_combo()
	moves_left = mini(level_start_moves, max_moves_left + r.moves_cap_add) if r.moves_carry else max_moves_left
	moves_left = maxi(moves_left, 1)
	current_deal = {}
	if is_endless(): load_level(endless_level(current_level_index))
	else: load_level(levels[current_level_index])
	reset_upgrades()
	load_character(Game.selected_character)

## 暂停菜单里点了箭头：这一关马上按新难度从头来，菜单不收（想一次换两档就接着点）
func _on_pause_stepped(delta: int) -> void:
	# 这一关还在载入、主角正在跳、或者结算面板已经出来了：不换。连点两下会让两次载入搅在一起
	if not level_ready or character.is_jumping or final_score_control.visible: return
	if not change_difficulty(delta): return
	restart_level_under(ruleset)
	_pending_note = "难度换成%s，这一关从头来" % ruleset.title

## 没过的结算面板上点了箭头。点 ‹：调低一档，马上按新难度重来这一关（到这儿来的人就是觉得难）；
## 点 ›：只换过去，面板刷新（"再守这一关"还在不在按新难度来），等玩家自己选重来还是再守
func _on_over_stepped(delta: int) -> void:
	if not change_difficulty(delta): return
	if delta < 0 and can_retry():
		restart_level_under(ruleset)
	else:
		_fill_game_over()


func attract_fishes():
	var char_pos = grid.world_to_grid_position(character.global_position)
	var tiles = grid.get_fish_tiles()
	if tiles.size():
		tiles.shuffle()
		tiles.sort_custom(func(a,b): return a.global_position.distance_to(character.global_position) < b.global_position.distance_to(character.global_position))
		for tile in tiles:
			var f := tile.object as Fish
			if not f: continue
			f.move_toward_grid_position(char_pos)
			#await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout

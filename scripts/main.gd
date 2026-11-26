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

var ruleset: Ruleset                 # 这局用的玩法方案（标题页里选的）
var current_deal: Dictionary = {}    # 开局摆好的那一局（河灯摆好的方案里用）；空 = 这一关是边收边刷的
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
var is_free_move := false
var tutorial: Tutorial           # 新手教程（放在界面层的最上面）

var start_time := 0.0
var water_strength := 0.0

func _ready() -> void:
	upgrade_random = FixedRandom.new()
	ruleset = Game.ruleset
	if ruleset == null: ruleset = Ruleset.new()
	_load_thing_resources()
	# 新手教程放在界面层的最后面，画在所有界面之上
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.main = self
	$CanvasLayer/Control.add_child(tutorial)
	hud_return_button.pressed.connect(SceneManager.load_title)
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
	load_level(first_level())
	reset_upgrades()
	load_character(Game.selected_character)
	reset_active_charges()
	bind_character_unlocks()
	get_viewport().size_changed.connect(fit_camera)
	_add_retry_button()

	start_time = get_time()


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
	if event.is_action_pressed("Power"):
		trigger_active_effect()
		
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
	print("Level ", current_level_index, " : ", get_time() - start_time)
	start_time = get_time()
	current_deal = {}
	if is_endless():
		# 长夜没有通关：一直往下走。步数带过去、每更补一步，压力就在这儿
		current_level_index += 1
		if ruleset.endless_carry:
			moves_left = mini(moves_left + 1 + ruleset.moves_bonus, max_moves_left + 2)
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
		combo = 10
		for tile in grid.tiles.values():
			tile.bump_strength = 10.0
		return
	current_level_index += 1
	if ruleset.moves_carry:
		moves_left = mini(moves_left + ruleset.moves_bonus, max_moves_left + 2)   # 步数带过去的方案：过关补几步
	else:
		moves_left = max_moves_left
	load_level(levels[current_level_index])
	reset_upgrades()
	load_character(Game.selected_character)

## 巡夜里一关没过：原地再来一次。分数和步数退回这一关的开头；灯还是原来那一局（练的就是它）
func retry_level() -> void:
	if is_endless() or ruleset == null or not ruleset.retry_level: return
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

## 结算面板上最上面加一个"再守这一关"（巡夜、而且方案允许重来的时侯才露面）
func _add_retry_button() -> void:
	var retry: Button = BUTTON.instantiate()
	retry.name = "RetryLevelButton"
	retry.text = "再守这一关"
	retry.pressed.connect(retry_level)
	final_score_control.buttons_container.add_child(retry)
	final_score_control.buttons_container.move_child(retry, 0)
	retry.visible = false


func _process(delta: float) -> void:
	camera_3d.global_position.x = lerp(camera_3d.global_position.x, camera_target_x(), delta * 2.0)
	score_display = lerp(score_display, float(score), delta * 5.0)
	score_label.text = str(int(ceil(score_display)))
	
	water_strength = lerp(water_strength, clamp(combo/10.0, 0.0, 1.0), delta)
	if not Game.visuals_value: water_strength = 0.0
	water.material_override.set("shader_parameter/amplitude", 0.3 + water_strength * 0.3)
	water.material_override.set("shader_parameter/speed", 1.0 + water_strength * 0.2)
	water.material_override.set("shader_parameter/frequency", 0.1 + water_strength * 0.2)
	
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
		var in_reach = tile_pos.distance_to(character_pos) / grid.tile_size.x <= max_distance
		# 步数是 0 以后，只有不花步数的格子还能跳
		var affordable = moves_left > 0 or step_is_free(tile)
		tile.is_available = tile.is_landable() and (not tile.object or tile.object.is_available()) and tile != character.target_tile and (in_reach or tile == back_tile) and affordable
		tile.update_color()
		tile.is_last_position = false
	if active_control.is_charged and Game.selected_character.active_effect == CharacterResource.ActiveEffect.ReturnToLastPosition:
		var tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
		if tile: tile.is_last_position = true

## 现在能跳多远（格）：连击、草鞋、纸伞都算上
func _reach_now() -> float:
	return min(combo * move_per_combo, max_combo_move_distance) + max_move_distance + 0.1 + temporary_mov_distance + level_reach_bonus

## 跳到这一格花不花步数：上面有东西（灯、道具、开了的水车）都不花，还没用过的补给格也不花
func step_is_free(tile: Tile) -> bool:
	if tile.object != null: return tile.object.is_available()
	if tile.is_spring_ready(): return true
	return portal_open_free()

## 水车开了、而且方案允许：这以后踩空格不扣步、不清连击
func portal_open_free() -> bool:
	return ruleset != null and ruleset.portal_free and current_fish_count >= fish_before_end_portal

## 这一关的河灯是不是开局就摆好的
func lamps_dealt() -> bool:
	return ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.DEALT and not current_deal.is_empty()

func update_moves_left():
	character_moves_left_label.text = str(moves_left)
	
func handle_movement():
	temporary_mov_distance = 0.0

	# 刚离开的如果是脆格，它现在碎掉
	var left_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	if left_tile and left_tile != character.target_tile: left_tile.break_tile()

	character.target_tile.bump()
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

	update_moves_left()
	update_tiles_color()

	# 一步都走不了（步数是 0 的时侯连不花步数的格子都够不着），也没有正在恢复的脆格：只能结束。
	# 有脆格在恢复的话等一等就还能走，不算卡死
	if not grid.has_available_tile() and not grid.has_broken_tile():
		end_game()

	if not lamps_dealt() and not current_fish_count >= fish_before_end_portal:
		gain_credits()

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
			
func handle_loot(fish: Fish):
	if not fish.resource: return;

	if fish.resource.effect == ObjectResource.ObjectEffect.None:
		current_fish_count += 1

	if fish.resource.effect: character.add_upgrade(fish.resource)

	last_color = fish.color if fish else colors.default_color

	if not fish: return

	if not end_portal_instance.is_active:
		active_control.charges_control.gain_charge(fish.resource.charge_gain)
		active_control.update()

	fish.loot()
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
			# 铜钱：身边刷出 value 件道具
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
	handle_loot(fish)
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
## 否则按方案来：流水方案里多半挨着灯刷（新的灯接得上），旧方案纯随机。没有空格子返回 null
func pick_empty_tile(near: bool = false) -> Tile:
	var here: Tile = character.target_tile
	if here == null: return null
	var empty: Array = []
	var near_tiles: Array = []
	var chain: Array = []
	var reach_now: float = min(combo * move_per_combo, max_combo_move_distance) + max_move_distance + 0.1 + temporary_mov_distance + level_reach_bonus
	for tile in grid.tiles.values():
		if tile.object or tile == here or not tile.is_landable(): continue
		empty.append(tile)
		if tile.global_position.distance_to(here.global_position) / grid.tile_size.x <= reach_now:
			near_tiles.append(tile)
		if _next_to_lamp(tile):
			chain.append(tile)
	if near and not near_tiles.is_empty():
		return near_tiles.pick_random()
	if not lamps_dealt() and ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.FLOW and not chain.is_empty() and randf() < ruleset.flow_chain:
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

## 流水方案：开局的灯里没有一盏在起点旁边的，就挪一盏过来（第一步总得有灯可收）
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
	max_move_distance = BASE_MAX_MOVE_DISTANCE
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
	if is_endless(): level_label.text = str("长夜 · 第 ", current_level_index + 1, " 更")
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
	fish_before_end_portal = maxi(1, int(round(level.fish_before_end_portal * ruleset.lamps_scale)))
	credits = level.starting_credits * 1.0

	current_fish_count = 0
	reset_combo()
	last_color = colors.default_color
	# 道具的效果、踩空的次数都从这一关重新算
	level_reach_bonus = 0.0
	shields = 0
	level_missteps = 0
	level_max_combo = 0.0
	level_start_score = score
	level_start_moves = moves_left
	current_deal = {}

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
	if ruleset != null and ruleset.lamp_mode == Ruleset.LampMode.DEALT:
		dealt = await place_deal(level)

	update_tiles_color()
	update_moves_left()

	water_strength = 0.0

	await SceneManager.scene_transition_control.close()

	if not dealt:
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
	# 第一次进游戏：关卡载入完了，先把玩法讲一遍（之后不再弹）
	tutorial.maybe_show_rules()
	level_ready = true
	_update_hud_return_visibility()

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

## 这一关怎么摆：按关卡进度定出基础的难度，再按方案加减；再按角色能跳多远算
func deal_options(lamps: int) -> Dictionary:
	var n := maxi(1, int(round(lamps * ruleset.lamps_scale)))
	var opt: Dictionary = BoardGen.endless_opt(current_level_index, n) if is_endless() else BoardGen.campaign_opt(current_level_index, n)
	opt.gap = clampf(float(opt.gap) + ruleset.gap_add, 0.0, 0.95)
	opt.detour = clampf(float(opt.detour) + ruleset.detour_add, 0.0, 0.8)
	opt.items = maxi(0, int(opt.items) + ruleset.items_add)
	opt.gates = mini(int(opt.gates), int(opt.items))
	var ch := Game.selected_character
	opt.reach = BoardGen.reach_params(BASE_MAX_MOVE_DISTANCE + ch.max_move_distance, BASE_MOVE_PER_COMBO * ch.move_per_combo, BASE_MAX_COMBO_DISTANCE + ch.max_combo_move_distance)
	return opt

## 摆一局河灯：巡夜里每一关是固定的一局（练的就是它），长夜每次现摆。摆好了返回 true
func place_deal(level: LevelResource) -> bool:
	var board := current_board()
	var rng := RandomNumberGenerator.new()
	if is_endless():
		rng.seed = endless_rng.randi()
	else:
		rng.seed = level.deal_seed if level.deal_seed != 0 else 7000 + current_level_index * 37
	var opt := deal_options(level.fish_before_end_portal)
	var d := BoardGen.deal(board, opt, rng)
	if d.is_empty():
		push_warning("这一关摆不出河灯，改用边收边刷：%s" % BoardGen.last_fail)
		return false
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
	score = 0
	score_display = 0.0
	current_level_index = 0
	moves_left = max_moves_left
	upgrade_random.reset()
	update_moves_left()
	reset_upgrades()
	load_level(first_level())
	load_character(Game.selected_character)
	reset_active_charges()


func trigger_active_effect():
	if character.is_jumping: return;
	if not active_control.is_charged: return;
	active_control.trigger_effect_audio.play()
	update_moves_left()

	reset_active_charges()

	var ch := Game.selected_character
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

	# 不再上传到网上的排行榜，只和本机的最好成绩比
	var run_key := Game.record_run(Game.selected_character, score, current_level_index + 1)

	final_score_control.set_visible(true)
	# 结算的标题（灯火熄了 / 守到天明）和左上角的关卡标签在同一个位置，叠在一起看不清：出结算的时候把关卡标签藏起来
	level_label.visible = false
	final_score_control.game_over.set_visible(true)
	final_score_control.completed.set_visible(false)
	if is_endless(): final_score_control.game_over.text = str("长夜未尽
守到了第 ", current_level_index + 1, " 更")
	else: final_score_control.game_over.text = "灯火暗了"
	final_score_control.animate()

	# 巡夜里、方案允许的时侯：这一关可以原地再来
	var retry: Node = final_score_control.buttons_container.get_node_or_null("RetryLevelButton")
	if retry: retry.visible = not is_endless() and ruleset != null and ruleset.retry_level

	leader_board_container_control.update()
	leader_board_container_control.set_current(run_key)


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

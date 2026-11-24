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
@onready var leader_board_container_control: LeaderBoardContainerControl = $CanvasLayer/Control/FinalScoreControl/LeaderBoardContainerControl
@onready var water: MeshInstance3D = $Water

const FISH = preload("res://scenes/fish.tscn")
const COMBO = preload("res://scenes/combo.tscn")
const HEART = preload("res://scenes/heart.tscn")
const HEART_LOSS = preload("res://scenes/heart_loss.tscn")

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
	# 新手教程放在界面层的最后面，画在所有界面之上
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.main = self
	$CanvasLayer/Control.add_child(tutorial)
	endless_rng.randomize()
	character.moved.connect(handle_movement)
	
	active_control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
			trigger_active_effect()
	)
	
	max_moves_left = Game.selected_character.max_moves_left
	moves_left = max_moves_left
	setup_camera()
	load_level(first_level())
	reset_upgrades()
	load_character(Game.selected_character)
	reset_active_charges()
	bind_character_unlocks()
	get_viewport().size_changed.connect(fit_camera)

	start_time = get_time()
	
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
	if is_endless():
		# 无尽模式没有通关：一直往下走，每过一关补一步
		current_level_index += 1
		moves_left = mini(moves_left + 1, max_moves_left + 2)
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
	load_level(levels[current_level_index])
	reset_upgrades()
	load_character(Game.selected_character)
	
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
	var max_distance = min(combo * move_per_combo, max_combo_move_distance) + max_move_distance + 0.1 + temporary_mov_distance
	# 刚离开的那个格子总是能跳回去：否则斜跳到一个没有相邻格子的空格上，连击一清零就被困死了
	var back_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	for tile in grid.tiles.values():
		var tile_pos = Vector2(tile.global_position.x, tile.global_position.z)
		var in_reach = tile_pos.distance_to(character_pos) / grid.tile_size.x <= max_distance
		tile.is_available = tile.is_landable() and (not tile.object or tile.object.is_available()) and tile != character.target_tile and (in_reach or tile == back_tile)
		tile.update_color()
		tile.is_last_position = false
	if active_control.is_charged and Game.selected_character.active_effect == CharacterResource.ActiveEffect.ReturnToLastPosition:
		var tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
		if tile: tile.is_last_position = true
func update_moves_left():
	character_moves_left_label.text = str(moves_left)
	
func handle_movement():
	temporary_mov_distance = 0.0
	
	# 刚离开的如果是脆格，它现在碎掉
	var left_tile: Tile = grid.get_tile(grid.world_to_grid_position(character.last_position))
	if left_tile and left_tile != character.target_tile: left_tile.break_tile()
	
	#for tile in grid.tiles.values():
		#tile.label_3d.text = str(floor(character.global_position.distance_to(tile.global_position) / grid.tile_size.x * 10.0) / 10.0)
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
			# 补给格：不扣步数，反而加步数
			moves_left = mini(moves_left + character.target_tile.use_spring(), max_moves_left + 2)
		else:
			reset_combo()
			colors.base_color = colors.default_color
			moves_left -= 1
			tutorial.hint("empty")
			var heart_loss = HEART_LOSS.instantiate()
			add_child(heart_loss)
			heart_loss.global_position = character.global_position
			character_moves_left_label.scale = Vector3.ONE * 2.0
			character.damage_particles_3d.emitting = true
			if moves_left <= 0:
				end_game()
			
	update_moves_left()
	update_tiles_color()

	# 一步都走不了、也没有正在恢复的脆格：只能结束。有脆格在恢复的话等一等就还能走，不算卡死
	if moves_left > 0 and not grid.has_available_tile() and not grid.has_broken_tile():
		end_game()
	
	if not current_fish_count >= fish_before_end_portal:
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
		
	# upgrade
	if fish.resource.description:
		var new_combo := COMBO.instantiate() as Combo
		add_child(new_combo)
		new_combo.set_description(fish.resource.description)
		new_combo.global_position = character.global_position
		
		if fish.is_portal:
			if grid.get_fish_tiles().size() <= 0 and moves_left >= max_moves_left:
				new_combo.set_description("完美无缺！")
				gain_score(5)
				on_wooow.emit()
			elif grid.get_fish_tiles().size() <= 0:
				new_combo.set_description("一盏不剩！")
				gain_score(3)
				on_perfect.emit()
			elif moves_left >= max_moves_left:
				new_combo.set_description("步数满格！")
				gain_score(3)
				on_flawless.emit()
	
	match fish.resource.effect:
		ObjectResource.ObjectEffect.SpawnFishes:
			for i in range(0, fish.resource.value):
				var fishh = spawn_fish()
				if fishh: fishh.load_resource(fishes[min(floor(randf() * fish_level), fishes.size()-1)])
				await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		ObjectResource.ObjectEffect.TemporaryMoveDistance:
			temporary_mov_distance += fish.resource.value
		ObjectResource.ObjectEffect.GainCombo:
			gain_combo(fish.resource.value)
		ObjectResource.ObjectEffect.AttractFishes:
			for i in range(0, fish.resource.value):
				attract_fishes()
				await get_tree().create_timer(0.5).timeout
		ObjectResource.ObjectEffect.CollectFarestFishes:
			for i in range(0, fish.resource.value):
				var tiles = grid.get_fish_tiles()
				if not tiles.size(): break;
				tiles.shuffle()
				tiles.sort_custom(func(a,b): return a.global_position.distance_to(character.global_position) > b.global_position.distance_to(character.global_position))
				var tile = tiles[0]
				if tile and tile.object:
					handle_loot(tile.object)
					tile.object = null
					update_tiles_color()
					if not end_portal_instance.is_active:
						gain_credits()
					#await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
				else: break
			update_moves_left()
		ObjectResource.ObjectEffect.RegainMovesLeft:
			moves_left = min(moves_left + fish.resource.value, max_moves_left)
			update_moves_left()
		ObjectResource.ObjectEffect.MoreUpgrades:
			# 这之后更容易刷出升级道具（每一关开始时恢复默认）
			upgrade_chance = minf(upgrade_chance + fish.resource.value, 0.5)
			upgrade_random.rate = upgrade_chance
		ObjectResource.ObjectEffect.EndLevel:
			next_level()
			
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
	
func spawn_fish() -> Fish:
	var tiles = grid.tiles.values()
	for tile in tiles: tile.fish_weight = 0.0
	var fish_tiles = tiles.filter(func(a): return a.object)
	for tile in fish_tiles:
		for ntile in grid.get_tile_neighbours(tile):
			ntile.fish_weight += 1.0
		
	var empty_tiles = tiles.filter(func(a): return not a.object and a != character.target_tile and a.is_landable())
	empty_tiles.shuffle()
	empty_tiles.sort_custom(func(a,b):
		return (a.fish_weight > b.fish_weight and randf() < magnet_power)
	)
	
	if not empty_tiles.size(): return;
	
	var tile : Tile = empty_tiles[0]
	
	var new_fish := FISH.instantiate() as Fish
	add_child(new_fish)
	tile.object = new_fish
	new_fish.global_position = tile.global_position
	return new_fish
	
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
	max_move_distance = 1.0
	max_combo_move_distance = 2.0
	move_per_combo = 0.2
	magnet_power = 0.0
	temporary_mov_distance = 0.0
	credits_gain = 0.6
	upgrade_chance = 0.1

func load_level(level: LevelResource):
	upgrade_random.rate = upgrade_chance
	
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
	fish_before_end_portal = level.fish_before_end_portal
	credits = level.starting_credits * 1.0

	current_fish_count = 0
	reset_combo()
	last_color = colors.default_color
	
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
	
	if moves_left < max_moves_left:
		var heart_tile = grid.get_empty_tiles().pick_random()
		var heart := HEART.instantiate() as Fish
		add_child(heart)
		heart_tile.object = heart
		heart.global_position = heart_tile.global_position
		
	update_tiles_color()
	update_moves_left()
	
	
	water_strength = 0.0
	
	await SceneManager.scene_transition_control.close()
	
	
	await spend_credits()
	#await spend_credits_spaced()
	
	on_enter_level.emit()
	# 第一次进游戏：关卡载入完了，先把玩法讲一遍（之后不再弹）
	tutorial.maybe_show_rules()
	


func restart():
	score = 0
	score_label.text = str(score)
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
			var fish = spawn_fish()
			if fish: 
				var upgrade = available_upgrades.pick_random() if not ch.spawned_upgrades.size() else ch.spawned_upgrades.pick_random()
				fish.load_resource(upgrade)
				fish.is_upgrade = true
		CharacterResource.ActiveEffect.SpawnFishes:
			for i in range(0, ch.value):
				var fish = spawn_fish()
				if fish: fish.load_resource(fishes[min(floor(randf() * fish_level), fishes.size()-1)])
				await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
		CharacterResource.ActiveEffect.AttractFishes:
			for i in range(0, ch.value):
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
				for i in range(0, ch.value):
					if i >= tiles.size(): break
					var tile = tiles[i]
					if tile and tile.object:
						handle_loot(tile.object)
						tile.object = null
						update_tiles_color()
						if not end_portal_instance.is_active:
							gain_credits()
						#await get_tree().create_timer(randf_range(1.0, 2.0) * 0.1).timeout
					else: break
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
	if is_endless(): final_score_control.game_over.text = str("长夜未尽\n守到了第 ", current_level_index + 1, " 更")
	else: final_score_control.game_over.text = "灯火熄了"
	final_score_control.animate()
	
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

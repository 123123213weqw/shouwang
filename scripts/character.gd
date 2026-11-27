class_name Character extends Node3D

@onready var main: Main = $/root/Main
@onready var sprite_container: Node3D = $SpriteContainer
@onready var shadow: Sprite3D = $Shadow
@onready var body_sprite: Sprite3D = $SpriteContainer/BodySprite
@onready var head_sprite: Sprite3D = $SpriteContainer/HeadSprite
@onready var character_moves_left_label: Label3D = $SpriteContainer/CharacterMovesLeftLabel
var held_label: Label3D               # 手里的灯还剩几盏（规矩"手里的灯"）：挂在步数标签旁边，比它小一号
@onready var jump_launch_audio: AudioStreamPlayer3D = $JumpLaunchAudio
@onready var jump_land_audio: AudioStreamPlayer3D = $JumpLandAudio
@onready var damage_particles_3d: GPUParticles3D = $SpriteContainer/DamageParticles3D

var last_jump: float
var jump_life: float
@export var jump_duration: float = 0.3
@export var jump_height: float = 1.0
var target_position: Vector3
var start_jump_position: Vector3
var target_tile: Tile
var flip_sprites := false
var last_position: Vector3

var is_jumping: float:
	get: return jump_life <  1.0

var upgrades_list : Dictionary[ObjectResource, int]

func _input(event: InputEvent) -> void:
	if is_jumping: return;
	if event is InputEventKey:
		var movement = Vector2.ZERO
		if event.is_action_pressed("MoveForward"): movement += Vector2.UP
		if event.is_action_pressed("MoveBack"): movement += Vector2.DOWN
		if event.is_action_pressed("MoveLeft"): movement += Vector2.LEFT
		if event.is_action_pressed("MoveRight"): movement += Vector2.RIGHT
		
		var current_position = main.grid.world_to_grid_position(target_position)
		var new_target = main.grid.get_tile(current_position + movement)
		
		if not new_target or not new_target.is_available: return;
		if target_tile != new_target:
			move_to(new_target)

func move_to(tile: Tile):
	if is_jumping: return;
	# 步数是 0 以后只还能跳到不花步数的格子（有灯、有道具、开了的水车、补给格）
	if main.moves_left <= 0 and not main.step_is_free(tile): return
	last_position = global_position
	jump_launch_audio.play()
	target_tile = tile
	target_position = tile.global_position
	last_jump = Time.get_ticks_msec() / 1000.0
	start_jump_position = global_position
	sprite_container.scale = Vector3(1.0 / 1.2, 1.2, 1.0)
	var signn = sign(tile.global_position.x - global_position.x)
	if signn != 0.0:
		flip_sprites = signn < 0
	
func set_tile(tile: Tile):
	target_tile = tile
	target_position = tile.global_position
	global_position = target_tile.global_position
	jump_life = 1.0

func _process(delta: float) -> void:
	var jlife = (main.get_time() - last_jump) / jump_duration
	if target_tile and is_jumping and jlife >= 1.0:
		global_position = target_tile.global_position
		moved.emit()
		jump_land_audio.play()
		
	head_sprite.rotation.y = lerp(head_sprite.rotation.y, PI if flip_sprites else 0.0, delta * 10.0)
	body_sprite.rotation.y = lerp(body_sprite.rotation.y, PI if flip_sprites else 0.0, delta * 10.0)
	jump_life = jlife

	
	if is_jumping:
		global_position = lerp(start_jump_position, target_position, jump_life)
		sprite_container.position.y = sin(jump_life * TAU / 2.0) * jump_height
		shadow.scale = Vector3.ONE * cos(jump_life * TAU / 2.0) * 0.8
	else:
		global_position = target_position
		
	sprite_container.scale = lerp(sprite_container.scale, Vector3.ONE, delta * 5.0)
	character_moves_left_label.scale = lerp(character_moves_left_label.scale, Vector3.ONE, delta * 5.0)
	body_sprite.material_override.set("shader_parameter/color", main.colors.current_color.darkened(0.5).lightened(min(main.combo / 10.0 / 5.0, 0.5)))

## 建那个"手里还剩几盏灯"的标签。这一档没有这条规矩的时侯不建
func make_held_label(font: Font) -> void:
	if held_label != null or font == null: return
	held_label = Label3D.new()
	held_label.font = font
	# 样子照着步数标签抄（字体、像素大小、描边、朝向），只是字小一号、位置在它上面一点。
	# 挂在步数标签的同一个父节点下，和它用同一个坐标系
	var src := character_moves_left_label
	held_label.font_size = int(src.font_size * 0.7)
	held_label.billboard = src.billboard
	held_label.no_depth_test = src.no_depth_test
	held_label.pixel_size = src.pixel_size
	held_label.modulate = Color(src.modulate.r, src.modulate.g * 0.86, src.modulate.b * 0.55)
	held_label.outline_size = src.outline_size
	held_label.outline_modulate = src.outline_modulate
	held_label.position = src.position + Vector3(0.0, 0.62, 0.0)
	held_label.text = ""
	src.get_parent().add_child(held_label)

func set_held(n: int) -> void:
	if held_label == null: return
	held_label.text = "" if n <= 0 else "灯 ×%d" % n

func load_resource(res: CharacterResource):
	head_sprite.material_override.set("shader_parameter/texture_albedo", res.head_sprite)
	# 身子有自己的图就用它；没有的话不动，身子还是场景里摆的那张（原版的做法）
	if res.body_sprite:
		body_sprite.material_override.set("shader_parameter/texture_albedo", res.body_sprite)

func add_upgrade(upgrade: ObjectResource):
	if not upgrades_list.has(upgrade): upgrades_list[upgrade] = 0
	upgrades_list[upgrade] += 1

signal moved

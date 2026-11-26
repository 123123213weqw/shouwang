class_name Tile extends Area3D

@onready var main: Main = $/root/Main
@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var label_3d: Label3D = $Label3D
@onready var algae_sprite: Sprite3D = $AlgaeSprite
@onready var csg_box_3d: CSGBox3D = $CSGBox3D
@onready var cube: MeshInstance3D = $TileModel/Cube
@onready var last_position_sprite: Sprite3D = $LastPositionSprite

@export var color: Color
@export var available_color: Color
@export var hover_color: Color

@export var algae_sprites : Array[CompressedTexture2D]

## 格子的类型：
##   NORMAL   普通格
##   CRUMBLE  脆格：离开后碎掉，过 regrow_delay 秒重新长出来
##   BLOCKED  障碍：不能落上去，鱼也不会刷在上面
##   SPRING   补给格：踩上去不扣步数，反而加 spring_gain 步；每格每关只能用一次
enum TileType { NORMAL, CRUMBLE, BLOCKED, SPRING }

# 特殊格的配色只是临时用的，为的是一眼能分辨出不同的格子，等换素材的时候一起定。
# 特殊格不跟着关卡的配色走，这样每一关里脆格、补给格、障碍长得都一样；
# 够得着的时候亮、够不着的时候暗，和普通格的明暗规则一致
const BLOCKED_COLOR := Color(0.70, 0.66, 0.62)   # 浅灰：比暗水面和够不着的暗格子都亮，靠"又高又亮"认出来
const CRUMBLE_COLOR := Color(0.74, 0.42, 0.18)      # 赭石
const CRUMBLE_DIM_COLOR := Color(0.33, 0.17, 0.06)
const SPRING_COLOR := Color(0.82, 0.92, 0.84)      # 月白
const SPRING_DIM_COLOR := Color(0.30, 0.44, 0.38)

@export var tile_type: TileType = TileType.NORMAL
@export var spring_gain := 2
@export var regrow_delay := 2.5
var spring_used := false
var broken_until := -1.0

var object: Node3D

var rseed := 0.0
var fish_weight := 0.0
var is_hovered := false
var is_available := false
var is_last_position := false
var current_color: Color
var target_color: Color

var pos_y := 0.0
var bump_strength := 0.0
var aim_raise := 0.0        ## 选技能目标的时候，选中的那一格抬起来这么高
var aim_pick := false       ## 选技能目标的时候，这一格是不是当前选中的：是就染成烛火色
const AIM_COLOR := Color(1.0, 0.84, 0.55)
func _ready() -> void:
	rseed = randf()
	mouse_entered.connect(func():
		is_hovered = true
		update_color()
	)
	mouse_exited.connect(func():
		is_hovered = false
		update_color()
	)
	algae_sprite.set_visible(randf() < 0.2)
	# 每个格子从几种装饰里随机长一种。原版把这行注释掉了，结果只会长场景里默认的那一种；
	# 这个材质每个格子各有一份（resource_local_to_scene），所以逐个改不会串
	if algae_sprites.size() > 0:
		algae_sprite.material_override.set("shader_parameter/texture_albedo", algae_sprites.pick_random())

func _input(event: InputEvent) -> void:
	if not is_available or not is_hovered: return;
	if event is InputEventMouseButton:
		if event.is_pressed() and event.button_index == 1:
			# 正在选技能的目标：点这一格就是选它，人不跟着跳过去
			if main.aiming != Main.Aim.NONE:
				main.aim_pick(self)
			else:
				main.character.move_to(self)

func _process(delta):
	update_color()
	last_position_sprite.set_visible(is_last_position)

	if is_broken() and main.get_time() >= broken_until:
		broken_until = -1.0
	# 碎掉的脆格沉到水面以下；障碍比别的格子高出一截，看上去就是不能踩的东西
	var rest_height := pos_y - (0.9 if is_broken() else 0.0) + (0.8 if is_blocked() else 0.0)

	current_color = lerp(current_color, target_color, delta * 5.0)
	sprite_3d.material_override.set("shader_parameter/color", current_color)
	last_position_sprite.material_override.set("shader_parameter/color", current_color)
	algae_sprite.material_override.set("shader_parameter/color", current_color.lightened(0.4))
	# 障碍的侧面也要是看得清的灰色：压得太暗会和那些够不着的格子混在一起
	cube.material_override.set("albedo_color", current_color.darkened(0.2 if is_blocked() else 0.6))

	scale = lerp(scale, Vector3.ONE, delta * 5.0)

	bump_strength = lerp(bump_strength, 0.0, delta)
	global_position.y = lerp(global_position.y, rest_height + aim_raise + sin(main.get_time() * TAU + global_position.x) * 0.2 * bump_strength, delta * 5.0)

	if object: object.global_position.y = global_position.y
	if main.character.target_tile == self: main.character.global_position.y = global_position.y

func bump(size:=1.2):
	scale = Vector3(size, 1.0/size, size);
	global_position.y -= size / 5.0
	bump_strength = size;

func is_blocked() -> bool:
	return tile_type == TileType.BLOCKED

func is_broken() -> bool:
	return broken_until >= 0.0

## 现在能不能落上去（障碍和碎掉的脆格不能）
func is_landable() -> bool:
	return not is_blocked() and not is_broken()

func is_spring_ready() -> bool:
	return tile_type == TileType.SPRING and not spring_used

## 用掉这一格的补给，返回加的步数
func use_spring() -> int:
	spring_used = true
	return spring_gain

func break_tile():
	if tile_type == TileType.CRUMBLE:
		broken_until = main.get_time() + regrow_delay

func get_color() -> Color:
	if aim_pick: return AIM_COLOR          # 选技能目标：选中的那一格是烛火色，一眼看得出
	if is_blocked(): return BLOCKED_COLOR
	if not is_available:
		# 脆格和补给格够不着的时候也保留自己的色调，只是暗一些
		if tile_type == TileType.CRUMBLE: return CRUMBLE_DIM_COLOR
		if is_spring_ready(): return SPRING_DIM_COLOR
		return main.colors.current_color.darkened(0.8)
	if is_hovered: return hover_color
	if tile_type == TileType.CRUMBLE: return CRUMBLE_COLOR
	if is_spring_ready(): return SPRING_COLOR
	return available_color if main.combo < 1 else main.colors.current_color

func update_color():
	target_color = get_color()
	sprite_3d.shaded = not (is_available and is_hovered)

func get_player_directions_tiles():
	var player_pos = main.grid.world_to_grid_position(main.character.global_position)
	var directions = []
	var horizontal = main.character.global_position.x - global_position.x
	var horizontal_direction = Vector2.LEFT if horizontal > 0 else Vector2.RIGHT
	var vertical =  main.character.global_position.y - global_position.y
	var vertical_direction = Vector2.UP if horizontal > 0 else Vector2.DOWN
	
	if abs(vertical) > abs(horizontal): directions = [horizontal_direction, vertical_direction]
	else: directions = [vertical_direction, horizontal_direction]
	if horizontal == 0.0: directions.erase(horizontal)
	if vertical == 0.0: directions.erase(vertical)
	
	directions = directions.map(func(d): return main.grid.get_tile(player_pos + d)).filter(func(a): return a and not a.object)
	return directions

func is_empty():
	return not object and self != main.character.target_tile and is_landable()

class_name Grid extends Node3D

@onready var main: Main = $/root/Main

@export var tile_size: Vector2
@export var tile_height_variation: float

var tiles: Dictionary[Vector2, Tile]

const TILE = preload("res://scenes/tile.tscn")
# 传送门场景不在这里 preload：它一路依赖回这个脚本，预加载会循环加载失败。搭棋盘时再用 load()

var level: Level
# 这关指定的起点所在的格子；关卡没有指定起点时为空
var start_tile: Tile

func clear():
	tiles.clear()
	start_tile = null
	if level:
		for tile in level.tiles_container.get_children():
			if tile.object: tile.object.free()
		level.queue_free()
		level = null

## 用字符画摆出来的棋盘（格式见 BoardGen.parse_map）
func load_map(rows: Array[String]):
	var board := BoardGen.parse_map(rows)
	build(board.cells, board.portal, board.start)

## 无尽模式：board 是 BoardGen.generate() 的结果
func load_generated(board: Dictionary):
	build(board.cells, board.portal, board.start)

## 用一张"格子坐标 → 格子类型"的表搭出棋盘。portal_cell 上放终点传送门；
## start_cell 是起点所在的格子，x 为负表示没有指定起点
func build(cells: Dictionary, portal_cell: Vector2i, start_cell: Vector2i):
	clear()
	level = Level.new()
	var container := Node3D.new()
	container.name = "TilesContainer"
	level.add_child(container)
	for cell in cells:
		var tile := TILE.instantiate() as Tile
		tile.name = str("Tile ", cell.x, ",", cell.y)
		tile.position = Vector3(cell.x, 0, cell.y)
		tile.tile_type = cells[cell]
		container.add_child(tile)
	var portal := load("res://scenes/end_portal.tscn").instantiate() as Node3D
	portal.name = "EndPortal"
	portal.position = Vector3(portal_cell.x, 0, portal_cell.y)
	level.add_child(portal)
	place_level(level, Vector2(start_cell.x, start_cell.y))

## 把搭好的关卡节点放进场景：格子按棋盘的大小居中，记录每个格子的位置，放好传送门
func place_level(level_node: Level, start_cell: Vector2):
	level = level_node
	main.add_child(level)

	var positions = level.tiles_container.get_children().map(func(a): return a.position)
	positions.sort_custom((func(a,b): return a.x < b.x))
	var horizontal = Vector2(positions[0].x, positions[-1].x)
	positions.sort_custom((func(a,b): return a.z < b.z))
	var vertical = Vector2(positions[0].z, positions[-1].z)
	var width = abs(horizontal.x - horizontal.y)
	var height = abs(vertical.x - vertical.y)
	var offset := Vector2(width, height) / 2.0

	for tile in level.tiles_container.get_children():
		var pos = Vector2(tile.position.x, tile.position.z) - offset
		tile.pos_y = randf_range(0, tile_height_variation)
		tile.global_position = Vector3(pos.x * tile_size.x, tile.pos_y, pos.y * tile_size.y)
		tiles[pos] = tile

	var portal_pos = Vector2(level.end_portal.position.x, level.end_portal.position.z) - offset
	var portal_tile = get_tile(portal_pos)
	level.end_portal.global_position = Vector3(portal_pos.x * tile_size.x, portal_tile.position.y, portal_pos.y * tile_size.y)
	portal_tile.object = level.end_portal
	main.end_portal_instance = level.end_portal

	# 没有指定起点时 start_cell.x 为负，查不到格子，start_tile 就是空的
	if start_cell.x >= 0.0:
		start_tile = get_tile(start_cell - offset)

func get_tile_neighbours(tile):
	var ns = []
	var ntile = get_tile(world_to_grid_position(tile.position) + Vector2.LEFT)
	if ntile: ns.append(ntile)
	ntile = get_tile(world_to_grid_position(tile.position) + Vector2.UP)
	if ntile: ns.append(ntile)
	ntile = get_tile(world_to_grid_position(tile.position) + Vector2.RIGHT)
	if ntile: ns.append(ntile)
	ntile = get_tile(world_to_grid_position(tile.position) + Vector2.DOWN)
	if ntile: ns.append(ntile)
	return ns

func world_to_grid_position(world_position: Vector3) -> Vector2:
	# 格子坐标都是 0.5 的整数倍：先乘 2 取整再除回去，免得浮点误差让查找落空
	return ((Vector2(world_position.x, world_position.z) / tile_size) * 2.0).round() / 2.0

func grid_to_world_position(grid_position: Vector2):
	var tile = get_tile(grid_position)
	if not tile: return;
	return Vector3(grid_position.x * tile_size.x, tile.position.y, grid_position.y * tile_size.y)

func get_tile(pos: Vector2):
	return tiles[pos] if tiles.has(pos) else null

func get_fish_tiles():
	return tiles.values().filter(func(a: Tile): return a.object and not a.object.is_upgrade and not a.object.is_portal)

func get_empty_tiles():
	return tiles.values().filter(func(a: Tile): return a.is_empty())

## 现在有没有格子能跳过去
func has_available_tile():
	for tile in tiles.values():
		if tile.is_available: return true
	return false

## 有没有碎掉后正在恢复的脆格（有的话等一等就还能走）
func has_broken_tile():
	for tile in tiles.values():
		if tile.is_broken(): return true
	return false

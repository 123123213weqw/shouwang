class_name VersusTerritory extends VersusBase
## 夺岸：不摆河灯。你踩过的格子上会点起一盏灯（玉色）；对手是熄灯人，走到哪儿就把身边一圈的灯吹灭。
## 不花步数；亮着的灯越多跳得越远。限时之内让七成格子同时亮着就赢，时间到了就是输。

const BOARD := 6              # 用巡夜第 7 关"碑林"那张棋盘
const TIME := 60.0
const SHARE := 0.7            # 要让几成格子同时亮着
const FOE_PACE := 2.4         # 熄灯人几秒挪一步
const FOE_REACH := 1.7        # 它一步够多远（格）
const MY_PACE := 1.0          # 演示的时侯主角几秒跳一下

var lit: Dictionary = {}      # 格子 → 那一格上的灯（拿河灯的小图当标记，不算"格子上的东西"）
var landable := 0             # 棋盘上一共几格能踩
var goal := 0                 # 要同时亮几盏
var put_out := 0              # 被吹灭过几盏
var foe_clock := 2.5
var my_clock := 1.0

func _ready() -> void:
	super()
	main.free_moves = true

func title() -> String:
	return "夺岸"

func first_level() -> LevelResource:
	return campaign_level(BOARD, 0)

func uses_deal() -> bool:
	return false               # 不摆河灯：灯是你踩出来的

func uses_portal() -> bool:
	return false               # 亮够七成就分胜负，不走水车

func ready_level() -> void:
	main.current_board()
	for tile in lit.keys():                    # 上一局点亮的灯是真节点，重开的时候要真的释放掉
		var old: Fish = lit[tile]
		if is_instance_valid(old): old.queue_free()
	lit.clear()
	put_out = 0
	landable = 0
	for tile in main.grid.tiles.values():
		if tile.is_landable() and not tile.object: landable += 1
	goal = ceili(SHARE * landable)
	spawn_foe(farthest_tile(main.character.target_tile), FOE_COLOUR)
	time_left = TIME
	foe_clock = 2.5

func refresh_hud() -> void:
	hud.text = "亮着 %d / %d 盏 · 熄灯人灭了 %d 盏 · 剩 %d 秒" % [lit.size(), goal, put_out, ceili(time_left)]

func handle_landing() -> bool:
	_light(main.character.target_tile)
	if not over:
		# 亮着的灯越多跳得越远。封在 9：连击到了上限（10）河面会换成彩色，那是平时"连击满堂"的彩头，这儿不要
		main.combo = mini(lit.size(), int(REACH_CAP) - 1)
		main.update_tiles_color()
	return true

## 在 tile 上点一盏灯
func _light(tile: Tile) -> void:
	if over or tile == null or lit.has(tile): return
	var lamp := FISH.instantiate() as Fish
	main.add_child(lamp)
	lamp.global_position = tile.global_position
	lamp.set_color(YOUR_COLOUR)
	lit[tile] = lamp
	main.score = lit.size()
	if lit.size() >= goal:
		finish(true, "岸是你的了\n同时亮着 %d 盏灯，占了七成" % lit.size())

func _on_foe_landed() -> void:
	if over: return
	var here: Tile = foe.target_tile
	var n := 0
	for tile in lit.keys():
		if tile.global_position.distance_to(here.global_position) <= main.grid.tile_size.x * 1.01:
			_snuff(tile)
			n += 1
	if n > 0: pop(foe.global_position, "熄灯人灭了 %d 盏" % n)
	if not over: main.update_tiles_color()
	super()

func _snuff(tile: Tile) -> void:
	var lamp: Fish = lit[tile]
	lit.erase(tile)
	if is_instance_valid(lamp): lamp.queue_free()
	put_out += 1
	main.score = lit.size()

func _process(delta: float) -> void:
	common_tick()
	if over or not main.level_ready: return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		finish(false, "天快亮了，岸没守住\n同时亮着 %d 盏，还差 %d 盏" % [lit.size(), maxi(goal - lit.size(), 0)])
		return
	if auto:
		my_clock -= delta
		if my_clock <= 0.0 and not main.character.is_jumping:
			my_clock = MY_PACE
			_mine()
	foe_clock -= delta
	if foe_clock <= 0.0 and not foe.is_jumping:
		foe_clock = FOE_PACE
		foe_jump(_foes_pick())

## 演示用的主角：够得着的空格里挑一个离熄灯人最远的踩；都亮了就朝最近的空格走一步
func _mine() -> void:
	var here: Tile = main.character.target_tile
	var reach := reach_of(lit.size())
	var best: Tile = null
	var best_d := -1.0
	for t in jumpable(here, reach, foe.target_tile):
		if lit.has(t): continue
		var d: float = t.global_position.distance_to(foe.target_tile.global_position)
		if d > best_d:
			best_d = d
			best = t
	if best == null: best = first_step(here, _unlit(), reach, foe.target_tile)
	if best != null: main.character.move_to(best)

func _unlit() -> Array:
	var out: Array = []
	for tile in main.grid.tiles.values():
		if tile.is_landable() and not tile.object and not lit.has(tile): out.append(tile)
	return out

## 熄灯人去哪：够得着的格子里，挑身边灯最多的那格；够得着的格子身边一盏灯都没有，就朝最近的灯走一步
func _foes_pick() -> Tile:
	var here: Tile = foe.target_tile
	var best: Tile = null
	var best_n := -1
	for t in jumpable(here, FOE_REACH, main.character.target_tile):
		var n := _lit_near(t)
		if n > best_n:
			best_n = n
			best = t
	if best == null or best_n <= 0:
		var next: Tile = first_step(here, lit.keys(), FOE_REACH, main.character.target_tile)
		if next != null: return next
	return best

func _lit_near(tile: Tile) -> int:
	var n := 0
	for other in lit.keys():
		if other.global_position.distance_to(tile.global_position) <= main.grid.tile_size.x * 1.01: n += 1
	return n

## 排查用：亮着几盏、目标是几盏
func debug_state() -> String:
	return "%s｜能踩的格子 %d 个" % [hud.text, landable]

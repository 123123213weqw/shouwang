class_name VersusDuel extends VersusBase
## 对弈：一张棋盘，和对手轮流跳，一次一跳。踩到的灯归自己，留在原地上自己的颜色，以后谁也不能再落在那格上。
## 不花步数；自己的灯越多跳得越远（对手另算两盏，你先手）。谁踩了空格，对手就连跳一次。
## 灯分完，灯多的人赢。

const BOARD := 7              # 用巡夜第 8 关"鼓亭"那张棋盘
const LAMPS := 10
const FOE_THINK := 0.7        # 对手轮到它以后想几秒
const MY_THINK := 0.9         # 演示的时侯主角想几秒
const FOE_EDGE := 2           # 对手的跳跃距离按"多收了两盏"算：你先手，它得占点便宜才拉得平（两个都是随手玩的机器人时 7 比 3）

var mine := 0
var theirs := 0
var total := 0
var claimed: Dictionary = {}  # 已经有主的灯所在的格子 → true
var my_turn := true           # 现在是不是你的回合
var foe_again := 0            # 你踩过空：对手还要连跳几次
var me_again := 0             # 对手踩过空：你还能再跳一次
var foe_clock := 0.0
var my_clock := 0.0
var stuck_for := 0.0          # 轮到你却没处可跳，已经等了几秒

func _ready() -> void:
	super()
	main.free_moves = true

func title() -> String:
	return "对弈"

func first_level() -> LevelResource:
	var level := campaign_level(BOARD, LAMPS)
	level.deal_seed = randi() % 100000 + 1        # 每开一局换一张棋盘（重来也是新的）
	return level

func uses_portal() -> bool:
	return false               # 灯分完就分胜负，不走水车

func tune_deal(opt: Dictionary) -> void:
	opt.lamps = LAMPS
	opt.items = 0
	opt.gates = 0
	opt.detour = 0.3
	opt.gap = 0.05

func ready_level() -> void:
	main.current_board()
	mine = 0
	theirs = 0
	total = 0
	claimed.clear()
	for tile in lamp_tiles():
		(tile.object as Fish).set_color(BLANK_COLOUR)
		total += 1
	spawn_foe(foe_start(), FOE_COLOUR)
	my_turn = true
	foe_again = 0
	me_again = 0
	my_clock = MY_THINK
	stuck_for = 0.0
	main.update_tiles_color()

func refresh_hud() -> void:
	hud.text = "你 %d ： %d 对手 · %s" % [mine, theirs, "轮到你" if my_turn else "对手在想"]

## 轮不到你的时侯你哪儿都不能跳；有主的灯和对手站着的格子，谁也不能落
func filter_tiles() -> void:
	for tile in main.grid.tiles.values():
		if not my_turn or (is_instance_valid(foe) and tile == foe.target_tile) or claimed.has(tile):
			tile.is_available = false

func handle_landing() -> bool:
	var tile: Tile = main.character.target_tile
	var got := _claim(tile, true)
	if over: return true
	if not got:
		foe_again += 1
		pop(main.character.global_position, "踩空：对手连跳")
	if me_again > 0:
		me_again -= 1
		my_clock = MY_THINK          # 对手刚才踩过空：你连跳
		pop(main.character.global_position, "再跳一步")
	else:
		my_turn = false
		foe_clock = FOE_THINK
	main.update_tiles_color()
	return true

func _on_foe_landed() -> void:
	if over: return
	var got := _claim(foe.target_tile, false)
	if not got:
		me_again += 1
		pop(foe.global_position, "对手踩空：你连跳")
	if over: return
	if foe_again > 0:
		foe_again -= 1
		foe_clock = FOE_THINK          # 你踩过空：它连跳
	else:
		my_turn = true
		my_clock = MY_THINK
		stuck_for = 0.0
	main.update_tiles_color()
	super()

## 把 tile 上的灯判给 me 这一方。那一格上没有没主的灯就返回 false
func _claim(tile: Tile, me: bool) -> bool:
	if tile == null or claimed.has(tile): return false
	var lamp := tile.object as Fish
	if lamp == null or not lamp.is_fish: return false
	claimed[tile] = true
	lamp.set_color(YOUR_COLOUR if me else FOE_COLOUR)
	if me:
		mine += 1
		main.score = mine
		gain_my_reach()                # 自己的灯越多跳得越远
	else:
		theirs += 1
	if mine + theirs >= total: _settle()
	return true

func _settle() -> void:
	if mine > theirs: finish(true, "你赢了\n%d 比 %d" % [mine, theirs])
	elif theirs > mine: finish(false, "对手赢了\n%d 比 %d" % [mine, theirs])
	else: finish(false, "平手\n%d 比 %d" % [mine, theirs])

func _process(delta: float) -> void:
	common_tick()
	if over or not main.level_ready: return
	if my_turn:
		if not main.character.is_jumping:
			# 轮到你却没处可跳（也没在等对手连跳）：让一步
			if main.grid.has_available_tile():
				stuck_for = 0.0
				if auto:
					my_clock -= delta
					if my_clock <= 0.0:
						my_clock = MY_THINK
						var tile := _pick(main.character.target_tile, reach_of(mine), foe.target_tile)
						if tile != null: main.character.move_to(tile)
			else:
				stuck_for += delta
				if stuck_for > 1.0:
					stuck_for = 0.0
					pop(main.character.global_position, "你没处可跳，让了一步")
					my_turn = false
					foe_clock = FOE_THINK
					main.update_tiles_color()
		return
	foe_clock -= delta
	if foe_clock <= 0.0 and not foe.is_jumping:
		var tile := _pick(foe.target_tile, reach_of(theirs + FOE_EDGE), main.character.target_tile)
		if tile == null:
			my_turn = true             # 对手没处可去：让一步
			my_clock = MY_THINK
			pop(foe.global_position, "对手让了一步")
			main.update_tiles_color()
		else:
			foe_jump(tile)

## from 这一格的人下一步跳哪：够得着的没主的灯里挑最近的；都够不着，就朝最近的那盏走一步。
## from 是对手站的格子时就是替对手挑
func _pick(from: Tile, reach: float, block: Tile) -> Tile:
	var free: Array = []
	for tile in lamp_tiles():
		if not claimed.has(tile): free.append(tile)
	var best: Tile = null
	var best_d := 1e9
	for t in jumpable(from, reach, block, _open):
		if free.has(t):
			var d: float = t.global_position.distance_to(from.global_position)
			if d < best_d:
				best_d = d
				best = t
	if best == null: best = first_step(from, free, reach, block, _open)
	if best == null:
		# 一盏灯都走不到：随便踩个空格（这就算踩空，对手连跳）
		var spare: Array = jumpable(from, reach, block, _open).filter(func(t: Tile) -> bool: return t.object == null)
		if not spare.is_empty(): best = spare.pick_random()
	return best

## 这能不能落：有主的灯那一格不行
func _open(tile: Tile) -> bool:
	return not claimed.has(tile)

## 排查用：谁的回合、各几盏
func debug_state() -> String:
	return "%s｜灯 %d/%d 盏有主" % [hud.text, mine + theirs, total]

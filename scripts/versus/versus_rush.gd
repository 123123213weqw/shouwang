class_name VersusRush extends VersusBase
# 这套玩法的数（棋盘、灯数、时限、对手多快……）在 resources/versus/rush.tres 里，见 versus_rules.gd
## 抢灯：一张棋盘上两个人同时跳。灯谁先踩到就归谁，踩到的灯留在原地上自己的颜色。
## 不花步数；收得越多跳得越远。灯抢完了（或者一分钟到了），灯多的人赢。


var mine := 0
var theirs := 0
var total := 0
var foe_clock := 0.5
var my_clock := 1.0

func _ready() -> void:
	id = "rush"
	super()
	main.free_moves = true

func title() -> String:
	return "抢灯"

func first_level() -> LevelResource:
	var level := campaign_level(cfg.board_index, cfg.lamps)
	level.deal_seed = randi() % 100000 + 1        # 每开一局换一张棋盘（重来也是新的）
	return level

func uses_portal() -> bool:
	return false               # 灯抢完就分胜负，不走水车

func tune_deal(opt: Dictionary) -> void:
	opt.lamps = cfg.lamps
	opt.items = cfg.items               # 只要灯，不要道具
	opt.gates = 0
	opt.detour = cfg.detour
	opt.gap = cfg.gap

func ready_level() -> void:
	main.current_board()
	mine = 0
	theirs = 0
	total = 0
	for tile in lamp_tiles():
		(tile.object as Fish).set_color(BLANK_COLOUR)        # 还没主的灯是月白的
		total += 1
	spawn_foe(foe_start(), FOE_COLOUR)
	time_left = cfg.time_limit
	foe_clock = 0.6

func handle_landing() -> bool:
	_take(main.character.target_tile, true)
	if not over: main.update_tiles_color()
	return true

func _on_foe_landed() -> void:
	_take(foe.target_tile, false)
	super()

func refresh_hud() -> void:
	hud.text = "你 %d ： %d 对手    剩 %d 秒" % [mine, theirs, ceili(time_left)]

func _take(tile: Tile, me: bool) -> void:
	if over or tile == null: return
	var lamp := tile.object as Fish
	if lamp == null or not lamp.is_fish: return
	tile.object = null                     # 归了主的灯留在原地上色，不再算"格子上的东西"
	lamp.set_color(YOUR_COLOUR if me else FOE_COLOUR)
	if me:
		mine += 1
		main.score = mine
		gain_my_reach()                    # 收得越多跳得越远
	else:
		theirs += 1
	if mine + theirs >= total: _settle()

func _settle() -> void:
	if mine > theirs: finish(true, "你赢了\n%d 比 %d" % [mine, theirs])
	elif theirs > mine: finish(false, "对手赢了\n%d 比 %d" % [mine, theirs])
	else: finish(false, "平手\n%d 比 %d" % [mine, theirs])

func _process(delta: float) -> void:
	common_tick()
	if over or not main.level_ready: return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_settle()
		return
	if auto:
		my_clock -= delta
		if my_clock <= 0.0 and not main.character.is_jumping:
			my_clock = cfg.my_pace
			_go(main.character.target_tile, reach_of(mine), foe.target_tile)
	foe_clock -= delta
	if foe_clock <= 0.0 and not foe.is_jumping:
		foe_clock = cfg.foe_pace * randf_range(0.9, 1.15)
		_go(foe.target_tile, reach_of(theirs), main.character.target_tile)

## 从 from 出发去抢灯：够得着的灯里挑最近的；都够不着，就朝最近的那盏走一步。
## from 是对手站的格子时跳的是对手，否则是主角（演示用）
func _go(from: Tile, reach: float, block: Tile) -> void:
	var best: Tile = null
	var best_d := 1e9
	for t in jumpable(from, reach, block):
		if t.object is Fish and (t.object as Fish).is_fish:
			var d: float = t.global_position.distance_to(from.global_position)
			if d < best_d:
				best_d = d
				best = t
	if best == null: best = first_step(from, lamp_tiles(), reach, block)
	if best == null: return
	if from == foe.target_tile: foe_jump(best)
	else: main.character.move_to(best)

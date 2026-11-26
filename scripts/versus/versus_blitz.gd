class_name VersusBlitz extends VersusBase
## 轮战：还是平时的规则，但对手是一炷香。香一共 45 秒，连着过棋盘：过一张，香接长 15 秒，马上换下一张新摆的。
## 香烧完为止。过的棋盘越多、收的灯越多，分越高。

const BOARD := 0              # 用巡夜第 1 关"石步"那张棋盘：小，过得快，中间没有水隔着
const LAMPS := 5              # 一张棋盘几盏灯
const START_TIME := 45.0
const BONUS := 15.0           # 过一张棋盘，香接长几秒
const MY_PACE := 0.85         # 演示的时侯主角几秒跳一下

var boards := 0               # 过了几张
var my_clock := 1.0
var sim: BoardSim

func title() -> String:
	return "轮战 · 第 %d 张棋盘" % (boards + 1)

func first_level() -> LevelResource:
	var level := campaign_level(BOARD, LAMPS)
	level.deal_seed = 1000 + boards * 7919 + randi() % 600       # 每一张都是新摆的一局
	return level

func tune_deal(opt: Dictionary) -> void:
	opt.lamps = LAMPS
	opt.items = 1
	opt.gates = 0
	opt.gap = 0.0               # 连击断了也够得着：比的是快，不是难
	opt.detour = 0.3

func ready_level() -> void:
	sim = null
	if boards == 0: time_left = START_TIME

func refresh_hud() -> void:
	hud.text = "第 %d 张棋盘 · 香还剩 %d 秒 · 过一张接 %d 秒" % [boards + 1, ceili(time_left), int(BONUS)]

## 进水车了：数过一张，香接长一截，换下一张
func next_board() -> bool:
	boards += 1
	time_left += BONUS
	main.moves_left = main.max_moves_left
	main.update_moves_left()
	pop(main.character.global_position, "过了一张：香 +15 秒")
	var level := first_level()
	main.load_level(level)
	main.reset_upgrades()
	main.load_character(Game.selected_character)
	return true

func _process(delta: float) -> void:
	common_tick()
	if over or not main.level_ready: return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		finish(false, "香烧完了\n过了 %d 张棋盘" % boards)
		return
	if auto:
		my_clock -= delta
		if my_clock <= 0.0 and not main.character.is_jumping:
			my_clock = MY_PACE
			sim = bot_step(sim, LAMPS)

## 排查用：第几张、香还剩多长
func debug_state() -> String:
	return "%s｜过了 %d 张" % [hud.text, boards]

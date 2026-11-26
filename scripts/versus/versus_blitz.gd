class_name VersusBlitz extends VersusBase
# 这套玩法的数（棋盘、灯数、时限、对手多快……）在 resources/versus/blitz.tres 里，见 versus_rules.gd
## 轮战：还是平时的规则，但对手是一炷香。香一共 45 秒，连着过棋盘：过一张，香接长 15 秒，马上换下一张新摆的。
## 香烧完为止。过的棋盘越多、收的灯越多，分越高。


var boards := 0               # 过了几张
var my_clock := 1.0
var sim: BoardSim

func _ready() -> void:
	id = "blitz"
	super()

func title() -> String:
	return "轮战 · 第 %d 张棋盘" % (boards + 1)

func first_level() -> LevelResource:
	var level := campaign_level(cfg.board_index, cfg.lamps)
	level.deal_seed = 1000 + boards * 7919 + randi() % 600       # 每一张都是新摆的一局
	return level

func tune_deal(opt: Dictionary) -> void:
	opt.lamps = cfg.lamps
	opt.items = cfg.items
	opt.gates = 0
	opt.gap = cfg.gap               # 连击断了也够得着：比的是快，不是难
	opt.detour = cfg.detour

func ready_level() -> void:
	sim = null
	if boards == 0: time_left = cfg.time_limit

## 重来：从第一张棋盘、一炷新香重新开始
func restart_match() -> void:
	super()
	boards = 0
	time_left = cfg.time_limit

func refresh_hud() -> void:
	hud.text = "第 %d 张棋盘 · 香还剩 %d 秒 · 过一张接 %d 秒" % [boards + 1, ceili(time_left), int(cfg.bonus_time)]

## 进水车了：数过一张，香接长一截，换下一张
func next_board() -> bool:
	boards += 1
	time_left += cfg.bonus_time
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
			my_clock = cfg.my_pace
			sim = bot_step(sim, cfg.lamps)

## 排查用：第几张、香还剩多长
func debug_state() -> String:
	return "%s｜过了 %d 张" % [hud.text, boards]

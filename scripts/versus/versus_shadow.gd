class_name VersusShadow extends VersusBase
## 追影：还是平时的规则（花步数、连击、道具），但身后多了个影子——它沿着这一局摆好的那条路线
## （一步不错就能收齐灯的那条）匀速往前走，不抢灯，只赶路。
## 它甩开你三盏灯（它走过的步数比你收的灯多三）你就输了；你先进水车就赢，赢得越早分越高。

const BOARD := 3             # 用巡夜第 4 关"十字河"那张棋盘
const LAMPS := 6
const PACE := 1.5            # 影子几秒走一步
const LEAD := 3              # 影子甩开你几盏灯就输
const MY_PACE := 0.9         # 演示的时侯主角几秒跳一下

var route: Array = []        # 影子要走的路线（格子坐标，依次踩过去）
var shadow_step := 0         # 影子已经走到路线上的第几格
var clock := 0.0
var my_clock := 1.2
var sim: BoardSim

func _ready() -> void:
	super()
	foe_colour = INK_COLOUR

func title() -> String:
	return "追影"

func first_level() -> LevelResource:
	var level := campaign_level(BOARD, LAMPS)
	level.deal_seed = randi() % 100000 + 1        # 每开一局换一张棋盘（重来也是新的）
	return level

func ready_level() -> void:
	route = main.current_deal.get("route", [])
	shadow_step = 0
	clock = 2.5                # 先让你走两步
	sim = null
	spawn_foe(main.character.target_tile, INK_COLOUR, Game.selected_character)    # 影子长着你的脸

func refresh_hud() -> void:
	hud.text = "影子第 %d 步 · 你收了 %d 盏 · 被它甩开 %d 盏就输" % [shadow_step, main.current_fish_count, LEAD]

func after_landing() -> void:
	_check()
	if over: return
	# 平时那一套判了你没处可走（步数用完又够不着灯）：对影子来说，就是你停下了
	if main.final_score_control.visible:
		finish(false, "影子等着你\n你没处可跳了")

func next_board() -> bool:
	finish(true, "你赢了\n比影子先进水车，领先 %d 步" % (route.size() - shadow_step))
	return true

func _on_foe_landed() -> void:
	shadow_step += 1
	_check()
	super()

func _check() -> void:
	if shadow_step - main.current_fish_count >= LEAD:
		finish(false, "影子把你甩开了\n它走了 %d 步，你才收了 %d 盏灯" % [shadow_step, main.current_fish_count])

func _process(delta: float) -> void:
	common_tick()
	if over or not main.level_ready: return
	if auto:
		my_clock -= delta
		if my_clock <= 0.0 and not main.character.is_jumping:
			my_clock = MY_PACE
			sim = bot_step(sim, LAMPS)
	clock -= delta
	if clock <= 0.0 and not foe.is_jumping and shadow_step < route.size():
		var tile: Tile = main.tile_at_cell(route[shadow_step])
		if tile == null or tile == main.character.target_tile:
			clock = 0.2         # 你正站在它要去的格子上：等一等
		else:
			clock = PACE
			foe_jump(tile)

## 排查用：影子走到哪、你收了几盏
func debug_state() -> String:
	return "%s｜路线 %d 格，影子在第 %d 格，主角%s" % [hud.text, route.size(), shadow_step, "正跳着" if main.character.is_jumping else "站着"]

class_name VersusBase extends Node
## 对战类的玩法：跟一个对手（或者跟时间）争胜负。一共五种，各管自己的规则，都在 scripts/versus/ 里：
##   rush       抢灯   一张棋盘上两个人同时跳，灯谁先踩到归谁
##   shadow     追影   平时的规则，身后有个影子沿着一步不错的路线匀速走
##   territory  夺岸   踩过的格子点灯，对手是走到哪灭到哪的熄灯人
##   blitz      轮战   一炷香里连着过棋盘，过一张香接长一截
##   duel       对弈   一张棋盘轮流跳，踩到的灯归自己
##
## 这一份是它们共用的东西：对手这个角色、头顶那一行战况、计时、谁赢了怎么说、给演示用的找路。
##
## 进了对战的局（Game.versus 是上面某个 id），Main 就建一个对应的玩法挂在身上。游戏原来那一套（载入关卡、
## 跳格子、结算面板）照用，只在几个关键的地方问这个玩法一句。下面这些函数每种玩法按需要改：
##   first_level()      第一关用哪张棋盘
##   uses_deal()        要不要照平时那样把河灯摆好
##   tune_deal(opt)     摆法要不要改（比如不要道具）
##   ready_level()      关卡载入完了：摆对手、开始计时、把这一局的数清零
##   uses_portal()      靠不靠水车分胜负（不靠的玩法把水车藏起来）
##   handle_landing()   主角落地了。返回 true 就是这个玩法自己处理了，不走平时那一套（收灯、扣步数）
##   after_landing()    走了平时那一套之后再告诉它一声
##   filter_tiles()     最后过一遍"哪些格子能跳"（比如对手站着的那格不行）
##   next_board()       进水车了。返回 true 就由它决定接下来怎样
##   result_text()      结算面板上写什么

const IDS := ["rush", "shadow", "territory", "blitz", "duel"]
const NAMES := {"rush": "抢灯", "shadow": "追影", "territory": "夺岸", "blitz": "轮战", "duel": "对弈"}
const SUMMARIES := {
	"rush": "一张棋盘，两个人同时跳。灯谁先踩到就归谁，踩到的灯染上自己的颜色。\n限时一分钟，灯多的人赢。",
	"shadow": "还是平时的规则，但身后多了个影子：它沿着一条一步不错的路线匀速往前走。\n它甩开你三盏灯你就输了。先进水车，你赢。",
	"territory": "你踩过的格子上会点起一盏灯。对手是熄灯人，走到哪儿就把身边的灯吹灭。\n限时之内让七成格子同时亮着，岸就是你的。",
	"blitz": "一炷香，连着过棋盘：过一张，香接长一截。\n香烧完为止，看你能过几张。",
	"duel": "一张棋盘，和对手轮流跳，一次一跳，踩到的灯归自己。\n踩了空格，对手就连跳一次。灯分完，灯多的人赢。",
}

const CHARACTER := preload("res://scenes/character.tscn")
const COMBO := preload("res://scenes/combo.tscn")
const FISH := preload("res://scenes/fish.tscn")

const YOUR_COLOUR := Color(0.42, 0.88, 0.74)      # 你的灯：玉色
const FOE_COLOUR := Color(0.96, 0.40, 0.24)       # 对手的灯和身子：朱砂
const BLANK_COLOUR := Color(0.84, 0.87, 0.80)     # 还没主的灯：月白
const INK_COLOUR := Color(0.17, 0.19, 0.23)       # 影子的身子：墨
const REACH_BASE := 1.1                           # 够得着多远（格）：和平时一样是 1.1，每多收一盏灯加 0.2
const REACH_PER := 0.2
const REACH_CAP := 10.0

var main: Main
var id := ""                       # 是哪种玩法（"rush" 这样）。各个子类在 _ready 开头写上
var cfg: VersusRules               # 这套玩法的数（resources/versus/<id>.tres）
var foe: Character                 # 对手。没有对手的玩法（轮战）一直是空
var foe_colour := FOE_COLOUR
var hud: Label                     # 关卡名底下那一行战况
var time_left := 0.0               # 还剩几秒。不靠时间分胜负的玩法一直是 0
var over := false                  # 这一局分出胜负了
var won := false
var auto := false                  # 演示用：主角也交给机器人打（自动测试、录预览视频）

static func create(id: String) -> VersusBase:
	if not IDS.has(id): return null
	var script: GDScript = load("res://scripts/versus/versus_%s.gd" % id)
	return script.new() if script != null else null

## 收了 count 盏灯（或者点亮了 count 盏）的人，现在够得着多远
static func reach_of(count: int) -> float:
	return REACH_BASE + REACH_PER * minf(float(count), REACH_CAP)

func _ready() -> void:
	main = get_parent() as Main
	cfg = VersusRules.load_for(id)
	auto = Game.versus_auto
	process_priority = 50          # 排在两个角色的后面：角色每一帧会把自己的身子染回玩家的颜色，我随后再染一遍
	hud = Tutorial.make_label(28, Color(1, 1, 1))
	hud.name = "VersusHud"
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 描一圈边：主角跳到棋盘上排的时侯，"连击 ×N"的飘字会飘到这一行上来，没描边就看不清了
	hud.label_settings.outline_size = 9
	hud.label_settings.outline_color = Color(0.04, 0.06, 0.07)
	hud.anchor_left = 0.0
	hud.anchor_right = 1.0
	hud.offset_left = 0.0
	hud.offset_right = 0.0
	hud.offset_top = 98.0
	hud.offset_bottom = 140.0
	main.get_node("CanvasLayer/Control").add_child(hud)
	main.leader_board_container_control.visible = true     # 原地重开（同一次进游戏）的时候上一局把它藏起来了

# ================================================================ 每种玩法按需要改的

func title() -> String:
	return "对战"

func first_level() -> LevelResource:
	return main.levels[0]

func uses_deal() -> bool:
	return true

func tune_deal(_opt: Dictionary) -> void:
	pass

## 关卡载入完了。先让这种玩法把自己的东西摆好，再收拾两样在对战里多余的东西：
## 不靠水车分胜负的玩法，把水车藏起来（那一格照样不能落）；不花步数的玩法，把主角头顶的步数藏起来
## 重来一局（结算面板上的"重来"）：把上一局的胜负清掉。不清的话新的一局一上来就是"已经结束"，
## 画面上什么都不动（2026-11-26 的毛病）
func restart_match() -> void:
	over = false
	won = false
	hud.visible = true
	main.leader_board_container_control.visible = true

func on_level_ready() -> void:
	over = false
	won = false
	hud.visible = true
	ready_level()
	if is_instance_valid(main.end_portal_instance): main.end_portal_instance.visible = uses_portal()
	main.character_moves_left_label.visible = not main.free_moves

func ready_level() -> void:
	pass

func uses_portal() -> bool:
	return true

func handle_landing() -> bool:
	return false

func after_landing() -> void:
	pass

func filter_tiles() -> void:
	pass

func next_board() -> bool:
	return false

func result_text() -> String:
	return ""

func refresh_hud() -> void:
	pass

## 排查用：一行这一局的状况
func debug_state() -> String:
	return hud.text

# ================================================================ 共用的

## 每一帧最后做的事：把对手染成它自己的颜色，再刷一遍战况。各种玩法的 _process 开头先调它
func common_tick() -> void:
	if is_instance_valid(foe):
		foe.body_sprite.material_override.set("shader_parameter/color", foe_colour)
	refresh_hud()

## 用巡夜的某张棋盘当这一局的棋盘：地图、配色照搬，河灯的数量换成 lamps 盏
func campaign_level(index: int, lamps: int) -> LevelResource:
	var src: LevelResource = main.levels[clampi(index, 0, main.levels.size() - 1)]
	var res := LevelResource.new()
	res.level_name = src.level_name
	res.map = src.map
	res.base_color = src.base_color
	res.max_moves_left = src.max_moves_left
	res.starting_credits = src.starting_credits
	res.fish_before_end_portal = lamps
	return res

## 摆一个对手。at 是它出发的格子；colour 是它身子的颜色； face 给了就用那位角色的头（不给就挑一位不是主角的）
func spawn_foe(at: Tile, colour: Color, face: CharacterResource = null) -> void:
	if is_instance_valid(foe): foe.queue_free()        # 原地重开的时侯，上一局的对手还在
	foe = CHARACTER.instantiate() as Character
	main.add_child(foe)
	foe.set_process_input(false)                       # 键盘、手柄只管主角
	for sprite: Sprite3D in [foe.head_sprite, foe.body_sprite]:
		sprite.material_override = sprite.material_override.duplicate()    # 两个角色默认共用一份材质，要各染各的，先各留一份
	foe.set_tile(at)
	foe.load_resource(face if face != null else other_face())
	# 脸也染一层淡淡的同色：第二章的配色下主角的身子本来就偏红，只靠身子分不出谁是谁
	foe.head_sprite.material_override.set("shader_parameter/color", colour.lerp(Color.WHITE, 0.45))
	foe.character_moves_left_label.visible = false
	foe.jump_launch_audio.volume_db = -60.0
	foe.jump_land_audio.volume_db = -60.0
	foe.moved.connect(_on_foe_landed)
	foe_colour = colour

func _on_foe_landed() -> void:
	refresh_hud()

## 主角的连击加一（跳得更远），不弹"连击 ×N"的飘字：那行字会飘到头顶的战况上去，比分战况里已经有了
func gain_my_reach() -> void:
	main.combo += 1
	main.combo_control.set_combo(main.combo)

## 让对手跳到 tile。它正跳着的时侯、那一格是任一方站着的格子，都不跳
func foe_jump(tile: Tile) -> void:
	if tile == null or over or foe.is_jumping: return
	if tile == foe.target_tile or tile == main.character.target_tile: return
	foe.move_to(tile)

## 挑一位不是主角的角色当对手的脸
func other_face() -> CharacterResource:
	var list: Array = Game.characters
	if list.is_empty(): return null
	var i := list.find(Game.selected_character)
	return list[(i + 1) % list.size()] if i >= 0 else list[0]

## 分出胜负：亮出结算面板，标题换成这一局的说法
func finish(win: bool, text: String) -> void:
	if over: return
	over = true
	won = win
	if not main.final_score_control.visible: main.end_game()
	main.final_score_control.game_over.text = text
	hud.visible = false                                  # 结算面板的标题就写在这儿，别叠着
	main.leader_board_container_control.visible = false    # 对战不记本机成绩，排行榜不亮出来

## 在 at 的头顶弹一行字
func pop(at: Vector3, text: String) -> void:
	var c := COMBO.instantiate() as Combo
	main.add_child(c)
	c.set_description(text)
	c.global_position = at

func cell(tile: Tile) -> Vector2i:
	return main.to_cell(tile.global_position)

## 现在棋盘上摆着河灯的格子
func lamp_tiles() -> Array:
	var out: Array = []
	for tile in main.grid.tiles.values():
		if tile.object is Fish and (tile.object as Fish).is_fish: out.append(tile)
	return out

## from 这一格现在够得着、能落上去的格子。block 是不能落的一格（另一方站着的那格）；
## can_land 给了的话，它说不行的格子也不算
func jumpable(from: Tile, reach: float, block: Tile, can_land := Callable()) -> Array:
	var out: Array = []
	for tile in main.grid.tiles.values():
		if tile == from or tile == block or not tile.is_landable(): continue
		if tile.object and not tile.object.is_available(): continue
		if can_land.is_valid() and not can_land.call(tile): continue
		if tile.global_position.distance_to(from.global_position) / main.grid.tile_size.x > reach: continue
		out.append(tile)
	return out

## 朝 targets 里最近的一个走：先跳到一个现在够得着的格子，之后一格一格走过去。踩空最少的路优先，一样多的总步数最少的优先。
## 返回第一步跳哪一格；走不到返回 null。找路的讲究和 BoardSim._step_toward 一样：不能按直线距离裁断。
## 第一步必须是现在够得着的格子；之后每一步按同样的距离跳
func first_step(from: Tile, targets: Array, reach: float, block: Tile, can_land := Callable()) -> Tile:
	var best: Tile = null
	var best_key := Vector2(99999, 99999)
	for first in jumpable(from, reach, block, can_land):
		var queue: Array = [[first, 0 if first.object else 1, 1]]
		var seen := {cell(first): true, cell(from): true}
		while not queue.is_empty():
			var item: Array = queue.pop_front()
			var t: Tile = item[0]
			if targets.has(t):
				var key := Vector2(float(item[1]), float(item[2]))
				if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
					best_key = key
					best = first
				break
			for o in ring_offsets(reach):
				var n: Tile = main.tile_at_cell(cell(t) + o)
				if n == null or seen.has(cell(n)) or not n.is_landable(): continue
				if can_land.is_valid() and not can_land.call(n): continue
				seen[cell(n)] = true
				queue.append([n, int(item[1]) + (0 if n.object else 1), int(item[2]) + 1])
	return best

## 离原点不超过 reach 的那几个方向（原点自己不算）：找路的每一步都按现在够得着多远跳，隔着水的对岸也找得到路
static func ring_offsets(reach: float) -> Array:
	var out: Array = []
	var k := ceili(reach)
	for x in range(-k, k + 1):
		for y in range(-k, k + 1):
			var o := Vector2i(x, y)
			if o == Vector2i.ZERO: continue
			if Vector2(o).length() <= reach - 0.02: out.append(o)
	return out

## 对手的起点：路线尽头那一格旁边的空格子。灯是沿着路线从主角脚下摆出去的，让它从最远的那盏旁边出发，
## 离灯才和你一样近（从离你最远的格子出发的话，它得踩好几步空格才够得着灯，一边倒）。
## 没有路线（或者尽头旁边没有空格子）就退回离你最远的空格子
func foe_start() -> Tile:
	var route: Array = main.current_deal.get("route", [])
	for i in range(route.size() - 1, -1, -1):
		var end: Tile = main.tile_at_cell(route[i])
		if end == null: continue
		for n in main.grid.get_tile_neighbours(end):
			if n.is_landable() and not n.object and n != main.character.target_tile: return n
	return farthest_tile(main.character.target_tile)

## 离 from 最远的空格子（一格一格走过去最远的那个）
func farthest_tile(from: Tile) -> Tile:
	var dist := {cell(from): 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var t: Tile = queue.pop_front()
		for n in main.grid.get_tile_neighbours(t):
			if not n.is_landable() or dist.has(cell(n)): continue
			dist[cell(n)] = int(dist[cell(t)]) + 1
			queue.append(n)
	var best: Tile = null
	for t in main.grid.tiles.values():
		if t == from or t.object or not dist.has(cell(t)): continue
		if best == null or int(dist[cell(t)]) > int(dist[cell(best)]): best = t
	return best if best != null else from

## 演示用的主角：照 BoardSim 的贪心打法走一步（够得着的灯里挑最近的）。sim 记着它自己以为的棋盘，第一次用时照这一局摆好的那一套建。
## 只给"平时那一套规则"的玩法用（追影、轮战）
func bot_step(sim: BoardSim, lamps: int) -> BoardSim:
	if sim == null:
		var opt: Dictionary = main.deal_options(lamps)
		sim = BoardSim.from_deal(main.current_board(), main.current_deal, main.moves_left, opt.reach, main.portal_open_free())
	sim.moves = main.moves_left
	var t: Vector2i = sim.next_move()
	if t == sim.pos: return sim
	var tile: Tile = main.tile_at_cell(t)
	if tile == null or tile == main.character.target_tile: return sim
	main.character.move_to(tile)
	sim.land(t)
	return sim

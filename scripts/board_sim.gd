class_name BoardSim extends RefCounted
## 在一张棋盘上按"随手玩"的打法走一遍。纯逻辑，不开游戏。两处用：
##   1. 自动测试和调平衡（tools/test_boards.gd、tools/tier_rates.gd）：一个随手玩的玩家能过多少局、平均踩空几次
##   2. 游戏里的自动试玩（scripts/autoload/pad_adapter.gd 的 debug_autoplay）：贪心机器人每一步问它"下一格跳哪"
## 打法（贪心）：够得着的灯里挑最近的（一样近就挑离水车近的）；没有灯，够得着的道具顺手拿；
## 都够不着，就朝最近的灯走一步（踩空，扣一步）；水车开了就过去。
## 这是最省脑子的打法，真人只要比它多想一步就比它强，所以它的成绩是"下限"。
## 难度四档的几条规矩它都照着算（和 main.gd 里的道理一样，数从 Ruleset 来）：
##   手里的灯   眼前的灯都够不着、走过去要踩好几个空格的时侯，放一盏接过去（见 _best_placement）
##   风向       顺风跳得远、逆风跳得近（can_reach）
##   夜巡       每走一步算它想了 think 秒；蜡烛烧完最远的一盏灯灭掉，灯不够了就是没过（_tick）
##   步数带过关、水车开了走回去还要花步数、补给格、蒸笼，也都算
## 不模拟脆格碎掉（当成普通格），也不模拟角色的主动技能（所以有技能的真人比它还能多撑一阵）。

const HEART := 99                     # 蒸笼：步数没带满进关时棋盘上多出来的那一个，踩上去 +1 步（不超过上限）
const SPRING_GAIN := 2                # 补给格：踩上去加几步（和 Tile.spring_gain 一样）

var cells: Dictionary = {}            # Vector2i -> 格子类型（BoardGen.NORMAL / CRUMBLE / BLOCKED / SPRING）
var things: Dictionary = {}           # Vector2i -> 路线上放的东西（BoardGen.Thing，蒸笼是 HEART）
var pos: Vector2i
var back: Vector2i = Vector2i(-99, -99)   # 刚离开的格子（游戏里它总是能跳回去）
var portal: Vector2i
var need: int = 0                     # 收够几盏灯水车才开
var got: int = 0
var combo: float = 0.0
var shoe: float = 0.0
var dash: float = 0.0
var shields: int = 0
var moves: int = 5
var max_moves := 5                    # 步数上限：蒸笼加步数不超过它，食盒、补给格可以多出两三步
var rp: Dictionary = BoardGen.BASE_REACH
var portal_free: bool = true          # 水车开了以后踩空格不扣步
var spawns_lamps: bool = false        # 边收边刷的玩法：踩一下空格子才有新的灯刷出来（摆好的一局里不设）
var springs_used: Dictionary = {}     # 用过的补给格（每格每关只能用一次）

# 规矩"手里的灯"：开局手里有几盏、放一盏花几步。0 是没有这条规矩
var held := 0
var hold_cost := 1
var placed := 0                       # 这一局放了几盏（记下来看机器人用没用）
var placed_cells: Dictionary = {}     # 自己放下去的灯在哪些格子上：踩到算收了一盏，可不加连击
var last_placed := Vector2i(-99, -99) # 最近一盏放在哪一格（真机上的机器人每一步都新建一个 BoardSim，靠它知道该往哪放）

# 规矩"风向"：风往哪边吹（零是没有风）、顺风多跳多远、逆风少跳多远
var wind := Vector2i.ZERO
var wind_bonus := 0.0
var wind_penalty := 0.0
var wind_floor := 1.0                 # 逆风最少也还能跳这么远

# 规矩"夜巡"：night 是不是点着。think 是玩家每走一步想多久（秒）。蜡烛烧完一盏灯就灭，灯不够了就是没过
var night := false
var night_seconds := 30.0             # 一支蜡烧多久（秒），也是蜡最长能长回多少
var night_every := 6.0                # 灭了一盏以后，蜡重新长回这么长
var night_gain := 3.0                 # 每走一步蜡长回几秒
var night_left := 0.0                 # 蜡还能烧多久
var think := 0.0
var night_out := 0                    # 灭了几盏
var night_lost := false               # 是不是灯灭了才没过的

var missteps: int = 0
var steps: int = 0
var max_combo: float = 0.0
var items_taken: int = 0
var finished: bool = false
var won: bool = false
var stuck_at: Vector2i = Vector2i(-99, -99)   # 照路线走却走不到的那一格（没卡住时是 -99,-99）

## 用一局摆好的棋开一局
static func from_deal(board: Dictionary, d: Dictionary, moves_left: int, reach: Dictionary, free_portal: bool) -> BoardSim:
	var sim := BoardSim.new()
	sim.cells = board.cells
	sim.portal = board.portal
	sim.pos = board.start
	sim.need = int(d.lamps)
	sim.moves = moves_left
	sim.max_moves = moves_left
	sim.rp = reach
	sim.portal_free = free_portal
	var route: Array = d.route
	var kinds: Array = d.kinds
	for i in route.size():
		sim.things[route[i]] = kinds[i]
	return sim

func reach() -> float:
	return BoardGen.reach_of(combo, shoe, dash, rp)

## 从 a 跳到 b 够不够得着：按现在的连击能跳多远；有风的时侯再按方向算（顺风远、逆风近）
func can_reach(a: Vector2i, b: Vector2i) -> bool:
	return BoardGen.dist(a, b) <= BoardGen.wind_reach(reach(), Vector2(b - a), Vector2(wind), wind_bonus, wind_penalty, wind_floor) - BoardGen.REACH_MARGIN

func portal_open() -> bool:
	return got >= need

func landable(t: Vector2i) -> bool:
	return cells.has(t) and cells[t] != BoardGen.BLOCKED

func lamp_at(t: Vector2i) -> bool:
	return things.has(t) and BoardGen.LAMP_THINGS.has(things[t])

## 这一格是不是还没用过的补给格
func spring_ready(t: Vector2i) -> bool:
	return cells.get(t, -1) == BoardGen.SPRING and not springs_used.has(t)

## 棋盘上还亮着几盏灯
func lamps_left() -> int:
	var n := 0
	for t in things:
		if lamp_at(t): n += 1
	return n

## 跳到这一格花不花步数：上面有东西（灯、道具、开了的水车）、还没用过的补给格都不花
func step_free(t: Vector2i) -> bool:
	if things.has(t): return true
	if spring_ready(t): return true
	if t == portal and portal_open(): return true
	return portal_free and portal_open()

## 现在能跳到哪些格子。步数是 0 的时候，只有不花步数的格子还能跳
func available() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if c == pos or not landable(c): continue
		if c == portal and not portal_open(): continue
		# 刚离开的格子总是能跳回去（游戏里也是）：逆风的时侯靠它才不至于被困住
		if c != back and not can_reach(pos, c): continue
		if moves <= 0 and not step_free(c): continue
		out.append(c)
	return out

## 点上夜巡的蜡烛。seconds 是一支蜡烧多久、every 是灭一盏以后蜡长回多长、gain 是每走一步长回几秒、think_sec 是每步想多久
func enable_night(seconds: float, every: float, gain: float, think_sec: float) -> void:
	night = seconds > 0.0
	night_seconds = seconds
	night_every = every
	night_gain = gain
	think = think_sec
	night_left = seconds

## 跳到 t 并落地
func land(t: Vector2i) -> void:
	steps += 1
	back = pos
	pos = t
	dash = 0.0
	if t == portal and portal_open():
		finished = true
		won = true
		return
	if things.has(t):
		_take(t)
	elif spring_ready(t):
		springs_used[t] = true
		moves = mini(moves + SPRING_GAIN, max_moves + 2)
	elif not (portal_open() and portal_free):
		if shields > 0:
			shields -= 1
		else:
			moves = maxi(moves - 1, 0)
			combo = 0.0
			missteps += 1
	_tick()
	if finished: return
	if available().is_empty():
		finished = true
		won = false

## 夜巡的蜡烛烧掉一截：走这一步想了 think 秒，落地蜡长回 night_gain 秒（最长 night_seconds）。
## 烧完了：离主角最远的那盏灯灭掉，蜡重新长回 night_every 秒。
## 河灯是摆好的一局，水车要的盏数不因为灯灭了而少：剩下的灯（加上手里的）不够了，这一局就过不了了
func _tick() -> void:
	if not night: return
	night_left = minf(night_left + night_gain - think, night_seconds)
	if night_left > 0.0: return
	night_left = night_every
	night_out += 1
	var far := Vector2i(-99, -99)
	var fd := -1.0
	for t in things:
		if lamp_at(t) and BoardGen.dist(pos, t) > fd:
			fd = BoardGen.dist(pos, t)
			far = t
	if fd < 0.0: return
	things.erase(far)
	placed_cells.erase(far)
	if lamps_left() + held < need - got:
		finished = true
		won = false
		night_lost = true

## 捡起 t 上的东西
func _take(t: Vector2i) -> void:
	var kind: int = things[t]
	things.erase(t)
	# 自己放下去的灯：算收了一盏（水车要的盏数它也顶），可不加连击——它是个落脚点，不是奖励
	if placed_cells.has(t):
		placed_cells.erase(t)
		got += 1
		return
	match kind:
		BoardGen.Thing.LAMP, BoardGen.Thing.BIG:
			got += 1
			combo = minf(combo + 1.0, float(rp.cap))
		BoardGen.Thing.LOTUS:
			combo = minf(combo + BoardGen.LOTUS_COMBO, float(rp.cap))
		BoardGen.Thing.SHOE:
			shoe += BoardGen.SHOE_REACH
		BoardGen.Thing.UMBRELLA:
			dash = BoardGen.UMBRELLA_DASH
		BoardGen.Thing.HAT:
			shields += 1
		BoardGen.Thing.BOX:
			moves = mini(moves + 3, max_moves + 3)
		HEART:
			moves = mini(moves + 1, max_moves)
		BoardGen.Thing.WHEEL:
			# 卷走身边两格内的灯
			for u in things.keys():
				if lamp_at(u) and BoardGen.dist(u, t) <= 2.01:
					things.erase(u)
					placed_cells.erase(u)
					got += 1
					combo = minf(combo + 1.0, float(rp.cap))
		BoardGen.Thing.COIN:
			# 身边刷出两件道具
			var empty: Array = []
			for c in cells:
				if c != pos and c != portal and landable(c) and not things.has(c) and BoardGen.dist(c, t) <= 1.5:
					empty.append(c)
			for i in mini(2, empty.size()):
				things[empty[i]] = BoardGen.PLAIN_THINGS[(steps + i) % BoardGen.PLAIN_THINGS.size()]
	if not BoardGen.LAMP_THINGS.has(kind):
		items_taken += 1
	max_combo = maxf(max_combo, combo)

## 放灯：把一盏手里的灯放到 t 上（之后它就是一格"有灯"的格子）。放灯花 hold_cost 步，不扣连击。返回放没放成
func place(t: Vector2i) -> bool:
	if held <= 0 or moves < hold_cost: return false
	if t == pos or things.has(t) or not landable(t): return false
	things[t] = BoardGen.Thing.LAMP
	placed_cells[t] = true
	last_placed = t
	held -= 1
	moves -= hold_cost
	placed += 1
	steps += 1
	_tick()
	if available().is_empty() and not finished:
		finished = true
		won = false
	return true

## 贪心打法：下一格跳哪。没处可去返回现在的位置。
## 手里有灯、眼前的灯却都够不着的时侯，这一拍可能只放灯不跳（也返回现在的位置；放没放看 placed）
func next_move() -> Vector2i:
	var av := available()
	if portal_open():
		if av.has(portal): return portal
		return _step_toward([portal], av)
	var lamps: Array[Vector2i] = []
	var items: Array[Vector2i] = []
	for t in av:
		if lamp_at(t): lamps.append(t)
		elif things.has(t): items.append(t)
		# 步数不多了，够得着的补给格也顺手踩一下
		elif spring_ready(t) and moves * 2 <= max_moves: items.append(t)
	if not lamps.is_empty():
		var best := lamps[0]
		var best_key := Vector2(BoardGen.dist(best, pos), BoardGen.dist(best, portal))
		for t in lamps:
			var key := Vector2(BoardGen.dist(t, pos), BoardGen.dist(t, portal))
			if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
				best = t
				best_key = key
		return best
	if not items.is_empty():
		var best_item := items[0]
		var best_d := BoardGen.dist(best_item, pos)
		for t in items:
			if BoardGen.dist(t, pos) < best_d:
				best_item = t
				best_d = BoardGen.dist(t, pos)
		return best_item
	var targets: Array[Vector2i] = []
	for t in things:
		if lamp_at(t): targets.append(t)
	if targets.is_empty(): return _empty_step(av) if spawns_lamps else pos
	# 手里有灯：看看放一盏接过去划不划算。划算就放，这一拍只放灯不跳
	if held > 0 and moves >= hold_cost:
		var p := _best_placement(targets, av)
		if p != pos:
			place(p)
			return pos
	var next := _step_toward(targets, av)
	# 灯都在、可是一盏也走不到（比如隔着一道要斜跳才过得去的口子，连击又不够）：踩一个空格，等新的灯刷出来
	if next == pos and spawns_lamps: next = _empty_step(av)
	return next

## 手里有灯的时侯，放在哪一格最划算。要有灯现在够不着才放（都够得着就不用放）。
## 候选是现在够得着的空格。对每一格算两笔账：从脚下直接走过去要踩几个空格（before），
## 从这一格走过去还要踩几个（after）。放一盏花 hold_cost 步、不清连击：
##   花得比踩空少，才放；放完下一跳就够得着灯的时侯，只要不比踩空多花也放（连击保住了）。
## 一格一格走不到灯（隔着一道要跳远才过得去的口子）：那就只要有一格放得下去、放完走得到，就放。
## 没有划算的返回现在的位置
func _best_placement(targets: Array[Vector2i], av: Array[Vector2i]) -> Vector2i:
	var before := _plan_cost([pos], targets)
	if before == 0: return pos            # 现在就够得着灯
	if before < 0: before = 999            # 走不到：只要放完能走到就划算
	var best := pos
	var best_key := Vector2(1e9, 1e9)
	for p in av:
		if things.has(p) or p == portal: continue
		var after := _plan_cost([p], targets)
		if after < 0: continue             # 从这儿也走不到灯
		if not (hold_cost + after < before or (after == 0 and hold_cost <= before)): continue
		var key := Vector2(hold_cost + after, BoardGen.dist(p, pos))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = p
	return best

## 从 starts 里哪一格出发、一格一格走（不经过主角脚下，逆风的格子按风向算够不够得着），
## 到 targets 里最近的一个要踩几个空格。starts 自己那一格算它自己的（有东西就不算踩空）。走不到返回 -1
func _plan_cost(starts: Array[Vector2i], targets: Array[Vector2i]) -> int:
	for s in starts:
		if targets.has(s): return 0
	var queue: Array = []
	var seen: Dictionary = {}
	for s in starts:
		queue.append([s, 0 if step_free(s) else 1])
		seen[s] = true
	var best := -1
	var head := 0
	while head < queue.size():
		var item: Array = queue[head]
		head += 1
		var t: Vector2i = item[0]
		var cost: int = item[1]
		if targets.has(t):
			if best < 0 or cost < best: best = cost
			continue
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = t + d
			if n == pos or seen.has(n) or not landable(n): continue
			if n == portal and not portal_open(): continue
			if not can_reach(t, n): continue
			seen[n] = true
			queue.append([n, cost + (0 if step_free(n) else 1)])
	return best

## 边收边刷的玩法里，新的灯要踩一下空格子才刷得出来：踩一个空格。
## 刚离开的格子最稳妥，没有就挑离水车最近的。这里不模拟刷灯，只是别让真人试玩的时侯机器人干等
func _empty_step(av: Array[Vector2i]) -> Vector2i:
	if av.has(back): return back
	var best := pos
	var best_d := 1e9
	for t in av:
		if things.has(t) or t == portal: continue
		var d := BoardGen.dist(t, portal)
		if d < best_d:
			best_d = d
			best = t
	return best

## 朝 targets 里最近的一个走：第一步必须是现在够得着的格子，之后一格一格走。要踩的空格最少的路优先；
## 一样多的，走过去总步数最少的优先。走不到返回现在的位置。
## 找路的三处讲究：
##   不能按"离目标的直线距离"裁断：水车躲在障碍后面的时侯，直线距离近的那一格其实绕不过去，机器人会在两格之间来回踱步；
##   先只按上下左右找，找不到路才让它第一步斜跳或者远跳（荷塘那张图两块水面之间要斜着跳一步才过得去；连击 2 起就能斜跳）。
##   一上来就许它跳远，它专挑看着近、其实更险的路，成绩反而差；
##   跳远只算第一步：之后踩了空格连击清零，只能一格一格走。水车开了以后踩空格不清连击，才一直按现在的距离跳。
## 有风的时侯每一跳都按方向算够不够得着（连贴着走一格，逆着风也可能跳不了）
func _step_toward(targets: Array[Vector2i], av: Array[Vector2i]) -> Vector2i:
	var best_first := pos
	var best_cost := 99999
	var best_len := 99999
	var far: Array = _ring(reach())
	var near: Array = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var keep_far := portal_open() and portal_free
	for attempt in 2:
		var found := false
		for first in av:
			var first_cost := 0 if step_free(first) else 1
			var queue: Array = [[first, first_cost, 1]]
			var seen: Dictionary = {first: true}
			while not queue.is_empty():
				var item: Array = queue.pop_front()
				var t: Vector2i = item[0]
				var cost: int = item[1]
				var steps: int = item[2]
				if t in targets:
					if cost < best_cost or (cost == best_cost and steps < best_len):
						best_cost = cost
						best_len = steps
						best_first = first
					found = true
					break
				var nbrs: Array = far if (keep_far or (attempt == 1 and steps == 1)) else near
				for d in nbrs:
					var n: Vector2i = t + d
					if n == pos or seen.has(n) or not landable(n): continue
					if n == portal and not portal_open(): continue
					if not can_reach(t, n): continue
					seen[n] = true
					queue.append([n, cost + (0 if step_free(n) else 1), steps + 1])
		if found: break
	return best_first

## 现在能一下跳到的方向：离原点不超过 r 的所有偏移（原点自己不算）
static func _ring(r: float) -> Array:
	var out: Array = []
	var k := int(ceil(r))
	for x in range(-k, k + 1):
		for y in range(-k, k + 1):
			var d := Vector2i(x, y)
			if d == Vector2i.ZERO: continue
			if Vector2(d).length() <= r - BoardGen.REACH_MARGIN: out.append(d)
	return out

## 照着摆棋的那条路线走一遍：路线上的东西被别的道具提前收走的格子（比如水车卷走的灯）跳过去不踩。
## 用来核对"这一局一步不错就能过"。返回和 run() 一样的结果
func follow(route: Array, limit: int = 500) -> Dictionary:
	for t in route:
		if finished or steps >= limit: break
		if not things.has(t): continue
		if not available().has(t):
			finished = true
			won = false
			stuck_at = t
			return result()
		land(t)
		if finished and not won:
			stuck_at = t
			return result()
	# 灯收齐了：水车开了以后走过去不花步数，照着贪心打法走过去就行
	var guard := 0
	while not finished and guard < 200:
		guard += 1
		var t := next_move()
		if t == pos:
			stuck_at = pos
			break
		land(t)
	if not finished:
		finished = true
		won = false
	return result()

## 从头走到结束（过了、步数用完又没处去、灯灭了、或者走得比 limit 步还多）
func run(limit: int = 500) -> Dictionary:
	while not finished and steps < limit:
		var before := steps
		var t := next_move()
		if t == pos:
			# 刚放了一盏灯（步数记了），不是卡住，接着走
			if steps != before: continue
			finished = true
			won = false
			break
		land(t)
	return result()

## 这一局的结果
func result() -> Dictionary:
	return {"won": won, "missteps": missteps, "steps": steps, "max_combo": max_combo, "items": items_taken,
		"placed": placed, "night_out": night_out, "night_lost": night_lost, "moves": moves, "got": got}

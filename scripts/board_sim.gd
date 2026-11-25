class_name BoardSim extends RefCounted
## 在一张棋盘上按"随手玩"的打法走一遍。纯逻辑，不开游戏。两处用：
##   1. 自动测试和调平衡（tools/test_boards.gd）：一个随手玩的玩家能过多少局、平均踩空几次
##   2. 游戏里的自动试玩（scripts/autoload/pad_adapter.gd 的 debug_autoplay）：贪心机器人每一步问它"下一格跳哪"
## 打法（贪心）：够得着的灯里挑最近的（一样近就挑离水车近的）；没有灯，够得着的道具顺手拿；
## 都够不着，就朝最近的灯走一步（踩空，扣一步）；水车开了就过去。
## 这是最省脑子的打法，真人只要比它多想一步就比它强，所以它的成绩是"下限"。
## 不模拟脆格碎掉（当成普通格）。

var cells: Dictionary = {}            # Vector2i -> 格子类型（BoardGen.NORMAL / CRUMBLE / BLOCKED / SPRING）
var things: Dictionary = {}           # Vector2i -> 路线上放的东西（BoardGen.Thing）
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
var rp: Dictionary = BoardGen.BASE_REACH
var portal_free: bool = true          # 水车开了以后踩空格不扣步
var spawns_lamps: bool = false        # 边收边刷的玩法：踩一下空格子才有新的灯刷出来（摆好的一局里不设）

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
	sim.rp = reach
	sim.portal_free = free_portal
	var route: Array = d.route
	var kinds: Array = d.kinds
	for i in route.size():
		sim.things[route[i]] = kinds[i]
	return sim

func reach() -> float:
	return BoardGen.reach_of(combo, shoe, dash, rp)

func portal_open() -> bool:
	return got >= need

func landable(t: Vector2i) -> bool:
	return cells.has(t) and cells[t] != BoardGen.BLOCKED

func lamp_at(t: Vector2i) -> bool:
	return things.has(t) and BoardGen.LAMP_THINGS.has(things[t])

## 跳到这一格花不花步数：上面有东西（灯、道具、开了的水车）都不花
func step_free(t: Vector2i) -> bool:
	if things.has(t): return true
	if t == portal and portal_open(): return true
	return portal_free and portal_open()

## 现在能跳到哪些格子。步数是 0 的时候，只有不花步数的格子还能跳
func available() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := reach()
	for c in cells:
		if c == pos or not landable(c): continue
		if c == portal and not portal_open(): continue
		if BoardGen.dist(pos, c) > r - BoardGen.REACH_MARGIN and c != back: continue
		if moves <= 0 and not step_free(c): continue
		out.append(c)
	return out

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
	elif not (portal_open() and portal_free):
		if shields > 0:
			shields -= 1
		else:
			moves = maxi(moves - 1, 0)
			combo = 0.0
			missteps += 1
	if available().is_empty():
		finished = true
		won = false

## 捡起 t 上的东西
func _take(t: Vector2i) -> void:
	var kind: int = things[t]
	things.erase(t)
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
			moves += 3
		BoardGen.Thing.WHEEL:
			# 卷走身边两格内的灯
			for u in things.keys():
				if lamp_at(u) and BoardGen.dist(u, t) <= 2.01:
					things.erase(u)
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

## 贪心打法：下一格跳哪。没处可去返回现在的位置
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
	var next := _step_toward(targets, av)
	# 灯都在、可是一盏也走不到（比如隔着一道要斜跳才过得去的口子，连击又不够）：踩一个空格，等新的灯刷出来
	if next == pos and spawns_lamps: next = _empty_step(av)
	return next

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
##   跳远只算第一步：之后踩了空格连击清零，只能一格一格走。水车开了以后踩空格不清连击，才一直按现在的距离跳
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
			return {"won": false, "missteps": missteps, "steps": steps, "max_combo": max_combo, "items": items_taken}
		land(t)
		if finished and not won:
			stuck_at = t
			return {"won": false, "missteps": missteps, "steps": steps, "max_combo": max_combo, "items": items_taken}
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
	return {"won": won, "missteps": missteps, "steps": steps, "max_combo": max_combo, "items": items_taken}

## 从头走到结束（过了、步数用完又没处去、或者走得比 limit 步还多）
func run(limit: int = 500) -> Dictionary:
	while not finished and steps < limit:
		var t := next_move()
		if t == pos:
			finished = true
			won = false
			break
		land(t)
	return {"won": won, "missteps": missteps, "steps": steps, "max_combo": max_combo, "items": items_taken}

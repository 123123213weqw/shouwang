class_name BoardGen extends RefCounted
## 棋盘的纯逻辑：解析字符画棋盘，以及给无尽模式生成随机棋盘。
## 这个脚本不依赖任何场景和游戏流程，可以脱离游戏单独测试（tools/test_boards.gd）。
##
## 一张棋盘用 {cells, portal, start} 表示：
##   cells  Dictionary[Vector2i, int]  每个格子及其类型（见下面四个常数）
##   portal Vector2i  终点传送门所在的格子
##   start  Vector2i  起点所在的格子；没有指定起点时 start.x 为 -1
## 格子坐标都是整数，x 向右、z 向下。

# 格子类型。顺序必须和 Tile.TileType 一致，搭棋盘时直接按整数赋值
const NORMAL := 0
const CRUMBLE := 1
const BLOCKED := 2
const SPRING := 3

# 跳跃范围：基础 1.0 加 0.1 的余量，再加满连击的 2.0，最远约 3.1 格（平方）
const MAX_JUMP2 := 3.1 * 3.1

static func params(n: int) -> Dictionary:
	var k := maxi(n, 0)
	return {
		"width": clampi(5 + int(k / 2.0), 5, 11),              # 棋盘越来越宽
		"height": clampi(4 + int(k / 3.0), 4, 8),              # 越来越高
		"ground_ratio": clampf(0.96 - k * 0.03, 0.6, 0.96),    # 留下的格子比例越来越低，洞越来越多
		"crumble_ratio": clampf((k - 2) * 0.04, 0.0, 0.3),     # 第 3 关起出现脆格
		"blocked_ratio": clampf((k - 4) * 0.03, 0.0, 0.2),     # 第 5 关起出现障碍
		"spring_ratio": 0.07,                                  # 少量补给格
		"fish": mini(6 + k, 25),                               # 开传送门要吃的鱼
		"credits": clampi(5 + int(k / 3.0), 5, 9),             # 起始资源
	}


## 把字符画解析成 {cells, portal, start}。一行一个字符串，x 向右、z 向下：
##   . 普通格   空格 水   S 起点   P 终点传送门   c 脆格   x 障碍   s 补给格
static func parse_map(rows: Array[String]) -> Dictionary:
	var cells: Dictionary = {}
	var portal := Vector2i.ZERO
	var start := Vector2i(-1, -1)
	for z in rows.size():
		var row: String = rows[z]
		for x in row.length():
			var cell := Vector2i(x, z)
			match row[x]:
				".": cells[cell] = NORMAL
				"c": cells[cell] = CRUMBLE
				"x": cells[cell] = BLOCKED
				"s": cells[cell] = SPRING
				"P":
					cells[cell] = NORMAL
					portal = cell
				"S":
					cells[cell] = NORMAL
					start = cell
				" ": pass
	return {"cells": cells, "portal": portal, "start": start}


## 无尽模式第 n 关（从 0 数起）的一张随机棋盘。rng 是随机数来源，固定它就能复现。
static func generate(n: int, rng: RandomNumberGenerator) -> Dictionary:
	var p := params(n)
	for attempt in 60:
		# 先铺满，再一个一个地挖洞、放障碍。每拿掉一个格子都保证剩下的还能走成一片，
		# 所以最后剩多少格子是定下来的，不会因为砍掉不连通的部分而忽大忽小
		var cells: Dictionary = {}
		for x in p.width:
			for y in p.height:
				cells[Vector2i(x, y)] = NORMAL
		take_out(cells, int(round(p.width * p.height * (1.0 - p.ground_ratio))), -1, rng)
		take_out(cells, int(round(cells.size() * p.blocked_ratio)), BLOCKED, rng)
		var walkable: Dictionary = {}
		for k in cells:
			if cells[k] != BLOCKED:
				walkable[k] = cells[k]
		if walkable.size() < 7: continue

		# 起点选在能走的格子里，传送门放在离起点最远的格子上
		var start := pick_start(walkable, rng)
		var dist := distances(walkable, start)
		var portal := start
		var far := -1
		for k in dist:
			if dist[k] > far or (dist[k] == far and rng.randf() < 0.5):
				portal = Vector2i(k)
				far = dist[k]
		if far < 3 and attempt < 50: continue

		assign_special(cells, start, portal, p, rng)
		return {"cells": cells, "portal": portal, "start": start}
	return fallback(p)


## 从棋盘上拿掉 count 个格子：as_type 小于 0 是直接删掉（挖洞），否则改成那种类型（放障碍）。
## 格子打乱后挨个试，只有拿掉它之后剩下的能走的格子还连成一片才拿；都试完了还不够数就算了
static func take_out(cells: Dictionary, count: int, as_type: int, rng: RandomNumberGenerator) -> void:
	var candidates: Array = cells.keys()
	shuffled(candidates, rng)
	var taken := 0
	for c in candidates:
		if taken >= count: return
		var cell: Vector2i = c
		if cells[cell] == BLOCKED: continue
		if not stays_connected(cells, cell): continue
		if as_type < 0: cells.erase(cell)
		else: cells[cell] = as_type
		taken += 1


## 把 victim 拿掉以后，剩下的能走的格子是不是还四方向连成一片
static func stays_connected(cells: Dictionary, victim: Vector2i) -> bool:
	var remaining := 0
	var first := Vector2i(-1, -1)
	for k in cells:
		if k == victim or cells[k] == BLOCKED: continue
		remaining += 1
		first = k
	if remaining <= 1: return true
	var seen: Dictionary = {first: true}
	var queue: Array = [first]
	while queue.size() > 0:
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + d
			if nb != victim and cells.has(nb) and cells[nb] != BLOCKED and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	return seen.size() == remaining


## 只保留最大的一块四方向连通的区域
static func keep_largest_group(cells: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var remaining: Array = cells.keys()
	shuffled(remaining, rng)
	var best: Dictionary = {}
	while remaining.size() > 0:
		var first: Vector2i = remaining.pop_back()
		var group: Dictionary = {first: true}
		var queue: Array = [first]
		while queue.size() > 0:
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nb: Vector2i = c + d
				if cells.has(nb) and not group.has(nb):
					group[nb] = true
					queue.append(nb)
		for k in group:
			remaining.erase(k)
		if group.size() > best.size():
			best = group
	var out: Dictionary = {}
	for k in best:
		out[k] = cells[k]
	return out


## 从 start 出发，沿四方向走到每个格子各需要几步
static func distances(walkable: Dictionary, start: Vector2i) -> Dictionary:
	var dist: Dictionary = {start: 0}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + d
			if walkable.has(nb) and not dist.has(nb):
				dist[nb] = dist[c] + 1
				queue.append(nb)
	return dist


## c 在四方向上有几个邻居
static func neighbour_count(cells: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if cells.has(c + d):
			n += 1
	return n


## 选起点。只要棋盘上有邻居不少于两个的格子，起点就从这些格子里挑：开局只有一条路可走的话，
## 第一步就是被逼的。在这些格子里再优先挑邻居最少的（多半在边缘），好让传送门放得更远
static func pick_start(walkable: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var degrees: Dictionary = {}
	var any_roomy := false
	for k in walkable:
		degrees[k] = neighbour_count(walkable, Vector2i(k))
		if degrees[k] >= 2:
			any_roomy = true
	var best_degree := 99
	var candidates: Array = []
	for k in degrees:
		var degree: int = degrees[k]
		if degree < 2 and any_roomy: continue
		if degree < best_degree:
			best_degree = degree
			candidates = [k]
		elif degree == best_degree:
			candidates.append(k)
	if candidates.is_empty(): return Vector2i(walkable.keys()[0])
	return Vector2i(candidates[rng.randi_range(0, candidates.size() - 1)])


## 往普通格子里撒补给格和脆格；起点和传送门保持普通
static func assign_special(cells: Dictionary, start: Vector2i, portal: Vector2i, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var keys: Array = []
	for k in cells:
		if cells[k] == NORMAL and k != start and k != portal:
			keys.append(k)
	shuffled(keys, rng)
	var springs := clampi(int(floor(keys.size() * p.spring_ratio)), 1 if keys.size() >= 14 else 0, 3)
	var crumbles := mini(int(keys.size() * p.crumble_ratio), keys.size())
	for i in mini(springs, keys.size()):
		cells[keys[i]] = SPRING
	for j in range(springs, mini(springs + crumbles, keys.size())):
		cells[keys[j]] = CRUMBLE


## 实在生成不出来时的兜底：一块完整的矩形，起点和传送门在对角
static func fallback(p: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for x in p.width:
		for y in p.height:
			cells[Vector2i(x, y)] = NORMAL
	return {"cells": cells, "portal": Vector2i(p.width - 1, p.height - 1), "start": Vector2i.ZERO}


static func shuffled(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ================================================================ 摆一局河灯
## 河灯开局就摆好：从起点长出一条路线，依次踩过路线上的格子，一步不踩空就能把灯收齐、走进水车。
## 生成的时候每一步都按"那时能跳多远"来挑下一格，所以这条路线一定走得通：能不能过看会不会找路，不看运气。
## 难不难由三个数决定（由 Ruleset 和关卡给出）：
##   gap     有多少跳"贴着极限"：连击一断就够不着。0 = 每一跳断了连击也够得着；1 = 每一跳都要满连击
##   detour  路线绕路的程度：越大越不走直线，灯和灯挨得越近、岔路越多，先收哪一盏越要动脑子
##   items   路线上摆几件道具，其中 gates 件的后面紧跟着一道"只有靠它才过得了去"的沟

## 路线上的东西。main.gd 按这个编号挑对应的资源
enum Thing { LAMP, BIG, LOTUS, UMBRELLA, SHOE, HAT, BOX, WHEEL, COIN }

const LAMP_THINGS := [Thing.LAMP, Thing.BIG]
const GATE_THINGS := [Thing.UMBRELLA, Thing.SHOE, Thing.LOTUS]     # 靠它才过得了后面那道沟的
const PLAIN_THINGS := [Thing.HAT, Thing.BOX, Thing.WHEEL, Thing.COIN]
const CALM_THINGS := [Thing.HAT, Thing.BOX, Thing.COIN]            # 拿了不会搅乱棋盘的道具（水车会把近处的灯卷走）

const SHOE_REACH := 0.5          # 草鞋：之后每一跳加这么远
const UMBRELLA_DASH := 3.0       # 纸伞：拿到之后的下一跳加这么远
const LOTUS_COMBO := 3.0         # 莲蓬：连击加这么多
const REACH_PAD := 0.1           # main.gd 算跳跃距离时多留的余量
const REACH_MARGIN := 0.02       # 摆棋时每一跳还得比"能跳多远"短这么多：游戏里是用浮点数比大小的，不能贴着边

## 路线计划里还没定是哪一件的道具：到了那一步再按当时的情况挑
const GATE_SLOT := -1
const PLAIN_SLOT := -2

## 最近一次摆不出来卡在哪（排查用）
static var last_fail := ""

## 典型的几档跳跃距离：直线一格、斜一格、直线两格、（2,1）、（2,2）、直线三格……
const JUMPS := [1.0, 1.41421356, 2.0, 2.23606798, 2.82842712, 3.0, 3.16227766, 3.60555128, 4.0, 4.12310563, 4.47213595, 5.0]

## 守夜人这类角色的跳跃参数：连击为 0 时能跳 1.1 格，每点连击加 0.2 格，连击算到 10 为止
const BASE_REACH := {"base": 1.1, "per": 0.2, "cap": 10.0}

static func _fail(key: String, detail: String) -> Dictionary:
	last_fail = key
	_last_fail_detail = detail
	return {}

static var _last_fail_detail := ""

## 某个角色能跳多远的参数。三个数要和 main.gd 里算 max_distance 的那几行一致
static func reach_params(max_move_distance: float, move_per_combo: float, max_combo_move_distance: float) -> Dictionary:
	return {"base": max_move_distance + REACH_PAD, "per": move_per_combo,
		"cap": (max_combo_move_distance / move_per_combo) if move_per_combo > 0.0 else 0.0}

## 连击 combo、已经穿了几双草鞋（累加的距离 shoe）、这一跳有没有纸伞（dash）的时候，能跳多远
static func reach_of(combo: float, shoe: float, dash: float, rp: Dictionary) -> float:
	return float(rp.base) + float(rp.per) * minf(combo, float(rp.cap)) + shoe + dash

static func dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))

## 不超过 r（留了余量）的那几档跳跃距离，从小到大
static func jumps_within(r: float) -> Array:
	var out: Array = []
	for j in JUMPS:
		if float(j) <= r - REACH_MARGIN:
			out.append(j)
	return out

## 路线上每一步放什么：lamps 盏灯，中间插 items 件道具（前 gates 件是带沟的，其余是普通的）。
## 道具只记下"这里有一件"，具体是哪一件等走到那一步再定。位置大致均匀铺开，再随机挪一挪；
## 第一盏灯之前和最后一盏之后不放道具
static func plan_things(lamps: int, items: int, gates: int, rng: RandomNumberGenerator) -> Array[int]:
	var slots: Array[int] = []
	var n_items := mini(items, maxi(lamps - 1, 0))
	if n_items > 0 and lamps >= 3:
		for i in n_items:
			var base := int(round(float(lamps) * float(i + 1) / float(n_items + 1)))
			var slot := -1
			for tries in 8:
				var try_slot := clampi(base + rng.randi_range(-1, 1), 1, lamps - 1)
				if not slots.has(try_slot):
					slot = try_slot
					break
			if slot < 0:
				for try_slot in range(1, lamps):
					if not slots.has(try_slot):
						slot = try_slot
						break
			if slot >= 0: slots.append(slot)
		slots.sort()
	var plan: Array[int] = []
	var lamp_i := 0
	var item_i := 0
	while lamp_i < lamps or item_i < slots.size():
		if item_i < slots.size() and slots[item_i] == lamp_i:
			plan.append(GATE_SLOT if item_i < gates else PLAIN_SLOT)
			item_i += 1
			continue
		plan.append(Thing.BIG if rng.randf() < 0.08 else Thing.LAMP)
		lamp_i += 1
	return plan

## 从 prev 出发，靠 kind 这件道具，能不能留出一道"不靠它过不去、靠它过得去"的沟
static func _gate_possible(prev: Vector2i, cells: Dictionary, used: Dictionary, portal: Vector2i, kind: int,
		combo: float, shoe: float, rp: Dictionary) -> bool:
	var without := reach_of(combo, shoe, 0.0, rp)
	var boosted := without
	match kind:
		Thing.UMBRELLA: boosted = without + UMBRELLA_DASH
		Thing.SHOE: boosted = reach_of(combo, shoe + SHOE_REACH, 0.0, rp)
		Thing.LOTUS: boosted = reach_of(combo + LOTUS_COMBO, shoe, 0.0, rp)
	for c in cells:
		if used.has(c) or c == portal or cells[c] == BLOCKED: continue
		var d := dist(prev, c)
		if d > without + REACH_MARGIN + 0.05 and d <= boosted - REACH_MARGIN:
			return true
	return false

## 从起点长一条路线。走不通就返回空字典（原因记在 last_fail），由 deal() 换一批随机数重来。
## opt 的键：lamps 盏数、items 道具件数、gates 其中带沟的件数、gap、detour、reach（角色能跳多远）、
##           must_end_at_portal（最后一跳必须正好够得着水车；水车开了以后可以随便走的方案不用）
static func grow_route(board: Dictionary, opt: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cells: Dictionary = board.cells
	var start: Vector2i = board.start
	var portal: Vector2i = board.portal
	var rp: Dictionary = opt.get("reach", BASE_REACH)
	var gap: float = opt.get("gap", 0.5)
	var detour: float = opt.get("detour", 0.3)
	var must_end: bool = opt.get("must_end_at_portal", false)
	var plan := plan_things(int(opt.get("lamps", 8)), int(opt.get("items", 0)), int(opt.get("gates", 0)), rng)
	var steps: int = plan.size()
	var route: Array[Vector2i] = []
	var used: Dictionary = {start: true}
	var prev := start
	var combo := 0.0
	var shoe := 0.0
	var dash := 0.0
	var gate := -1               # 刚落在一件"带沟"的道具上：接下来这一跳要靠它
	var gate_without := 0.0      # 不靠它的时候能跳多远
	var pending := -1            # 刚踩上去、还没定是哪一件的道具在 plan 里的位置
	# 这条路线要占掉能走的格子的多大比例：越挤，越要先走"出路少"的格子（都留到最后就走不开了）
	var landable_count := 0
	for c in cells:
		if cells[c] != BLOCKED: landable_count += 1
	var dense := clampf(float(steps) / maxf(float(landable_count - 2), 1.0), 0.0, 1.0)
	for s in steps:
		# 上一步踩到的那件道具现在定型：它决定接下来这一跳能跳多远
		if pending >= 0:
			if plan[pending] == GATE_SLOT:
				var without := reach_of(combo, shoe, 0.0, rp)
				var kinds: Array = GATE_THINGS.duplicate()
				shuffled(kinds, rng)
				var picked := -1
				for k in kinds:
					if _gate_possible(prev, cells, used, portal, k, combo, shoe, rp):
						picked = k
						break
				if picked < 0:
					# 这里留不出沟（比如连击已经满了，莲蓬加不动）：这件就当普通道具，接着摆
					plan[pending] = CALM_THINGS[rng.randi_range(0, CALM_THINGS.size() - 1)]
					pending = -1
				else:
					plan[pending] = picked
					gate = picked
					gate_without = without
					match picked:
						Thing.SHOE: shoe += SHOE_REACH
						Thing.UMBRELLA: dash = UMBRELLA_DASH
						Thing.LOTUS: combo = minf(combo + LOTUS_COMBO, float(rp.cap))
			else:
				plan[pending] = PLAIN_THINGS[rng.randi_range(0, PLAIN_THINGS.size() - 1)]
			pending = -1
		var kind: int = plan[s]
		var reach := reach_of(combo, shoe, dash, rp)
		var target := 1.0
		if gate >= 0:
			# 带沟的那一跳：要比不靠道具时能跳的最远还远（看下面候选格子的距离）
			target = reach
		elif rng.randf() < gap:
			var top := jumps_within(reach)
			target = float(top.back())
		else:
			# 松的一跳：连击比现在少两点也够得着
			target = float(jumps_within(reach_of(maxf(combo - 2.0, 0.0), shoe, 0.0, rp)).back())
		var best_score := -1e9
		var best: Array = []
		var trapped: Array = []        # 踩上去就没处可去的格子：实在没有别的选择了才考虑
		for c in cells:
			if used.has(c) or c == portal or cells[c] == BLOCKED: continue
			var d := dist(prev, c)
			if d > reach - REACH_MARGIN: continue
			if must_end and s == steps - 1 and dist(c, portal) > reach_of(combo + 1.0, shoe, 0.0, rp) - REACH_MARGIN: continue
			# 剩下的跳数还多，踩上去却哪儿都去不了：死胡同
			if s < steps - 1 and not _has_exit(c, cells, used, portal, reach_of(combo + 1.0, shoe, 0.0, rp)):
				trapped.append(c)
				continue
			var sc := _route_score(c, prev, portal, cells, used, combo, shoe, rp, float(steps - s - 1), gap, detour, rng, dense)
			if gate >= 0:
				if d <= gate_without + REACH_MARGIN + 0.05: continue
				sc += d * 2.0               # 越远越好：挡得住人
			else:
				# 离想要的那一档越远扣得越多；越是"贴极限"的关越不愿意将就
				sc -= absf(d - target) * (1.5 + 3.0 * gap)
			if sc > best_score:
				best_score = sc
				best = [c]
		if best.is_empty():
			if not trapped.is_empty():
				# 只剩死胡同可走：随便挑一个，下一跳多半就走不通了，由 deal() 重摆
				best = [trapped[rng.randi_range(0, trapped.size() - 1)]]
			else:
				return _fail("留不出沟" if gate >= 0 else "没处可去",
					"第 %d 跳（连击 %.0f，能跳 %.2f）从 %s 出发%s；走过的路：%s" % [s + 1, combo, reach, prev,
					"留不出一道只有靠道具才过得了的沟" if gate >= 0 else "没有够得着的空格", str(route)])
		var t: Vector2i = best[0]
		route.append(t)
		used[t] = true
		prev = t
		dash = 0.0                 # 纸伞只管刚刚那一跳
		gate = -1                  # 沟只管刚刚那一跳，后面的跳恢复普通摆法
		if kind == GATE_SLOT or kind == PLAIN_SLOT:
			pending = s
		elif kind == Thing.LAMP or kind == Thing.BIG:
			combo += 1.0
	if pending >= 0:
		return _fail("道具在最后", "最后一件是道具，后面没有灯了")
	var ends := dist(prev, portal) <= reach_of(combo, shoe, 0.0, rp) - REACH_MARGIN
	if must_end and not ends:
		return _fail("够不着水车", "收完最后一盏灯以后够不着水车")
	# 水车会卷走身边两格内的灯。要是它够得着路线上后面还没踩的灯，路线就断了：换成不搅乱路线的道具
	for i in steps:
		if plan[i] != Thing.WHEEL: continue
		for j in range(i + 1, steps):
			if LAMP_THINGS.has(plan[j]) and dist(route[i], route[j]) <= 2.01 + REACH_MARGIN:
				plan[i] = CALM_THINGS[rng.randi_range(0, CALM_THINGS.size() - 1)]
				break
	return {"route": route, "kinds": plan, "lamps": int(opt.get("lamps", 8)), "ends_at_portal": ends}

## 从 c 出发还有没有没走过的格子可去
static func _has_exit(c: Vector2i, cells: Dictionary, used: Dictionary, portal: Vector2i, reach: float) -> bool:
	for n in cells:
		if n != c and not used.has(n) and n != portal and cells[n] != BLOCKED and dist(c, n) <= reach - REACH_MARGIN:
			return true
	return false

## 候选格子好不好：剩下的跳数还多的时候别早早挤到水车边上，别贴着早就走过的格子；棋盘宽裕时周围要留有空地方，
## 棋盘挤（dense 大）时反过来，先走那些出路少的格子
static func _route_score(c: Vector2i, prev: Vector2i, portal: Vector2i, cells: Dictionary, used: Dictionary,
		combo: float, shoe: float, rp: Dictionary, remaining: float, gap: float, detour: float, rng: RandomNumberGenerator, dense: float) -> float:
	var sc := 0.0
	var dp := dist(c, portal)
	var keep := remaining * (0.9 + 0.9 * detour)
	if remaining >= 1.0 and dp < keep:
		sc -= (keep - dp) * 1.5
	if remaining <= 1.0:
		sc -= dp * 0.6
	var near_used := 0
	for u in used:
		if u != prev and dist(u, c) <= 1.5:
			near_used += 1
	sc -= near_used * (0.4 + 1.2 * gap)
	var next_reach := reach_of(combo + 1.0, shoe, 0.0, rp)
	var free := 0
	for n in cells:
		if n != c and not used.has(n) and n != portal and cells[n] != BLOCKED and dist(c, n) <= next_reach + 0.01:
			free += 1
	sc += minf(free, 5.0) * lerpf(0.3, -0.7, clampf((dense - 0.3) / 0.3, 0.0, 1.0))
	if remaining >= 2.0:
		var far_reach := reach_of(combo + 2.0, shoe, 0.0, rp) + 1.0
		var far_free := 0
		for n in cells:
			if n != c and not used.has(n) and n != portal and cells[n] != BLOCKED and dist(c, n) <= far_reach:
				far_free += 1
		if far_free < 2:
			sc -= 3.0
	if cells[c] == CRUMBLE:
		sc -= 0.3 if cells[prev] != CRUMBLE else 1.5
	sc += rng.randf() * (0.9 + 0.9 * detour)
	return sc

## 摆一局：长不出来就换随机数重来；试了 150 回还不行就少摆一盏灯再试（最多减 3 盏），实际玩的时候总能摆出来。
## 摆出来的局里 lamps 是实际摆了几盏。opt 同 grow_route。全失败返回空字典，last_fail 里是各种原因各卡了几回
static func deal(board: Dictionary, opt: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var fails: Dictionary = {}
	var tries := 150
	opt = opt.duplicate()
	opt.lamps = clamp_lamps(board, int(opt.get("lamps", 8)), int(opt.get("items", 0)))
	for reduction in 4:
		for attempt in tries:
			var d := grow_route(board, opt, rng)
			if d.is_empty():
				fails[last_fail] = int(fails.get(last_fail, 0)) + 1
				continue
			var check := check_deal(board, d, opt)
			if check.ok:
				d["attempts"] = attempt + 1
				d["branches"] = check.branches
				d["min_slack"] = check.min_slack
				d["reduced"] = reduction
				return d
			fails["走不通：" + check.error] = int(fails.get("走不通：" + check.error, 0)) + 1
		opt.lamps = maxi(int(opt.lamps) - 1, 3)
	var parts: Array[String] = []
	for k in fails:
		parts.append("%s ×%d" % [k, fails[k]])
	last_fail = "摆了 %d 回（中间减了 3 盏灯）：%s" % [tries * 4, "；".join(parts)]
	return {}

## 这张棋盘最多摆得下几盏灯：路线（灯加道具）最多占掉能走的格子的一半，不然摆不出来，人也没处下脚
static func clamp_lamps(board: Dictionary, lamps: int, items: int) -> int:
	var landable_count := 0
	for c in board.cells:
		if board.cells[c] != BLOCKED: landable_count += 1
	return clampi(mini(lamps, int((landable_count - 2) * 0.5) - items), 3, 99)

## 把一条路线从头走一遍，核对它真的走得通：每一跳都够得着、不重复、带沟的地方不靠道具过不去。
## 顺便数一数岔路（每一步时，后面还有几盏灯也够得着）和最松的一跳余量
static func check_deal(board: Dictionary, d: Dictionary, opt: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "branches": 0, "min_slack": 99.0}
	if d.is_empty():
		out.error = "没有路线"
		return out
	var cells: Dictionary = board.cells
	var start: Vector2i = board.start
	var portal: Vector2i = board.portal
	var rp: Dictionary = opt.get("reach", BASE_REACH)
	var route: Array = d.route
	var kinds: Array = d.kinds
	var used: Dictionary = {start: true}
	var prev := start
	var combo := 0.0
	var shoe := 0.0
	var dash := 0.0
	var gate := -1
	var gate_without := 0.0
	var lamps := 0
	if route.size() != kinds.size() or route.is_empty():
		out.error = "路线和放的东西对不上"
		return out
	for i in route.size():
		var t: Vector2i = route[i]
		var kind: int = kinds[i]
		var what := "第 %d 格" % (i + 1)
		if not cells.has(t) or t == start or t == portal:
			out.error = what + "不在能放的格子上"
			return out
		if cells[t] == BLOCKED:
			out.error = what + "是障碍"
			return out
		if used.has(t):
			out.error = what + "和前面重复"
			return out
		var reach := reach_of(combo, shoe, dash, rp)
		var dd := dist(prev, t)
		if dd > reach - REACH_MARGIN:
			out.error = "%s够不着：隔 %.2f 格，只能跳 %.2f 格" % [what, dd, reach]
			return out
		if gate >= 0 and dd <= gate_without + REACH_MARGIN:
			out.error = "%s前面那道沟不靠道具也过得了" % what
			return out
		if LAMP_THINGS.has(kind):
			for j in range(i + 1, route.size()):
				if LAMP_THINGS.has(kinds[j]) and dist(prev, route[j]) <= reach - REACH_MARGIN:
					out.branches += 1
		out.min_slack = minf(out.min_slack, reach - dd)
		used[t] = true
		prev = t
		dash = 0.0
		gate_without = reach_of(combo, shoe, 0.0, rp)
		gate = -1
		if kind < 0:
			out.error = what + "的道具没定型"
			return out
		match kind:
			Thing.LAMP, Thing.BIG:
				combo += 1.0
				lamps += 1
			Thing.LOTUS:
				combo = minf(combo + LOTUS_COMBO, float(rp.cap))
			Thing.SHOE:
				shoe += SHOE_REACH
			Thing.UMBRELLA:
				dash = UMBRELLA_DASH
		if GATE_THINGS.has(kind): gate = kind
	if lamps != int(d.lamps):
		out.error = "灯数不对：数到 %d 盏，应为 %d 盏" % [lamps, int(d.lamps)]
		return out
	if bool(opt.get("must_end_at_portal", false)) and dist(prev, portal) > reach_of(combo, shoe, 0.0, rp) - REACH_MARGIN:
		out.error = "收完最后一盏灯，够不着水车"
		return out
	out.ok = true
	return out

## 一局摆好的样子，画成字符画：S 起点、P 水车、数字是第几盏灯（超过 9 用字母），道具用汉字
static func deal_ascii(board: Dictionary, d: Dictionary) -> String:
	var cells: Dictionary = board.cells
	var lo := Vector2i(9999, 9999)
	var hi := Vector2i(-9999, -9999)
	for k in cells:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
	var marks: Dictionary = {}
	var names := "灯大莲伞鞋笠盒车钱"
	var lamp_no := 0
	var route: Array = d.get("route", [])
	var kinds: Array = d.get("kinds", [])
	for i in route.size():
		var kind: int = kinds[i]
		if LAMP_THINGS.has(kind):
			lamp_no += 1
			marks[route[i]] = str(lamp_no) if lamp_no <= 9 else char(64 + lamp_no - 9)
		else:
			marks[route[i]] = names[kind]
	var lines: Array[String] = []
	for y in range(lo.y, hi.y + 1):
		var line := ""
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			if not cells.has(cell):
				line += " "
			elif cell == board.start:
				line += "S"
			elif cell == board.portal:
				line += "P"
			elif marks.has(cell):
				line += str(marks[cell])
			else:
				match cells[cell]:
					CRUMBLE: line += "c"
					BLOCKED: line += "x"
					SPRING: line += "s"
					_: line += "."
		lines.append(line)
	return "\n".join(lines)

## 巡夜每一关怎么摆，一行一关：收几盏灯、摆几件道具（其中几件带沟）、路线绕路的程度、贴极限的那一小截。
## 这些数是拿"随手玩"的贪心机器人（BoardSim）一关一关量出来的，不是拍脑袋定的：
##   它的过关率大致是 第 1、2 关 100% → 第 3 关 80% → 第 4 关 100% → 第 5 到 8 关 70% 降到 55% → 第 9 到 12 关 50% 降到 25%。
## 量的时候发现：真正决定难易的是路线长短（灯数）、带沟的道具几件、道具几件；"贴极限的跳占多少"（gap）几乎不起作用，
## 所以每关的 gap 只是照旧留着。第一章学会连击跳，第二章开始有道具和沟，第三章棋盘大、路线长。
## 想调哪一关的难易：先加减灯数，再动带沟的件数；改完跑一遍 tools/test_boards.gd 看机器人每关的过关率
const CAMPAIGN_TABLE := [
	# 灯, 道具, 其中带沟, 绕路, 贴极限
	[6, 1, 0, 0.25, 0.15],	  # 第 1 关 石步
	[7, 1, 0, 0.30, 0.22],	  # 第 2 关 环桥
	[6, 1, 0, 0.35, 0.0],	   # 第 3 关 荷塘：河对岸的最后一盏灯要连击够了才跳得过，灯少一点才攒得住
	[6, 1, 0, 0.40, 0.36],	  # 第 4 关 十字河
	[10, 2, 1, 0.80, 0.10],	 # 第 5 关 断桥：第一道沟
	[10, 0, 0, 0.80, 0.10],	 # 第 6 关 回廊：没有道具，全靠找路
	[8, 1, 0, 0.80, 0.30],	  # 第 7 关 碑林
	[9, 1, 1, 0.80, 0.30],	  # 第 8 关 鼓亭
	[14, 3, 0, 0.45, 0.0],	  # 第 9 关 巷陌：大棋盘，头一回要走长路
	[15, 3, 2, 0.50, 0.78],	 # 第 10 关 堡墙
	[13, 3, 2, 0.55, 0.85],	 # 第 11 关 城垛
	[18, 3, 2, 0.60, 0.70],	 # 第 12 关 远巡
]

static func campaign_opt(index: int, lamps: int) -> Dictionary:
	var row: Array = CAMPAIGN_TABLE[clampi(index, 0, CAMPAIGN_TABLE.size() - 1)]
	# 方案把灯按比例缩过的（lamps 和表里差得远），道具也跟着表走
	return {
		"lamps": int(row[0]) if absf(float(lamps) - float(row[0])) < 0.5 * float(row[0]) else lamps,
		"items": int(row[1]),
		"gates": int(row[2]),
		"detour": float(row[3]),
		"gap": float(row[4]),
	}

## 长夜第 n 更（从 0 数起）怎么摆。量出来的贪心机器人过关率：第 1 更 100%、第 4 更 85%、第 7 更 75%、第 11 更 67%、
## 第 16 更 51%、第 21 更 39%、第 26 更 27%，之后在 25% 上下。
## 第 5 更起道具固定 5 件（棋盘大了，光靠灯路线容易被逼进死胡同，摆不出来），带沟的件数慢慢加
static func endless_opt(n: int, lamps: int) -> Dictionary:
	var k := maxi(n, 0)
	return {
		"lamps": lamps,
		"gap": 0.2 if k < 5 else 0.3,
		"detour": clampf(0.25 + k * 0.015, 0.25, 0.7),
		"items": 1 if k < 5 else 5,
		"gates": 0 if k < 5 else (1 if k < 16 else (2 if k < 25 else 3)),
	}

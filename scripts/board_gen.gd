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

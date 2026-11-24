extends SceneTree
## 棋盘逻辑的自动测试，不需要开游戏：
##   godot --headless --path <工程目录> --script res://tools/test_boards.gd
##
## 检查两样东西：
##   1. 12 张主线棋盘（resources/campaign）：起点和传送门各一个且在普通格上，
##      所有能走的格子连满连击也跳得到，起点旁边至少有两个能走的格子
##   2. 无尽模式：前 80 关，每关按固定的随机种子生成 20 张，检查能走的格子四方向连成一片、
##      传送门离起点足够远、格子不越界、特殊格的数量不超过设定、格子数不少于设定、
##      起点旁边至少有两个能走的格子（开局就有得选）
## 退出码：全部通过为 0，否则为 1。

const CAMPAIGN := [
	"c1_1", "c1_2", "c1_3", "c1_4",
	"c2_1", "c2_2", "c2_3", "c2_4",
	"c3_1", "c3_2", "c3_3", "c3_4",
]
const ENDLESS_LEVELS := 80
const SAMPLES := 20

var failures := 0

func _init() -> void:
	test_campaign()
	test_endless()
	print("RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func fail(msg: String) -> void:
	failures += 1
	if failures <= 40: print("FAIL ", msg)

## 能走的格子（去掉障碍）
func walkable(cells: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in cells:
		if cells[k] != BoardGen.BLOCKED:
			out[k] = cells[k]
	return out

## 连满连击（最远约 3.1 格）能不能从起点走到每一个能走的格子
func jump_connected(cells: Dictionary, start: Vector2i) -> bool:
	if not cells.has(start): return false
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	while queue.size() > 0:
		var c: Vector2i = queue.pop_back()
		for k in cells:
			if not seen.has(k) and (k.x - c.x) * (k.x - c.x) + (k.y - c.y) * (k.y - c.y) <= BoardGen.MAX_JUMP2:
				seen[k] = true
				queue.append(k)
	return seen.size() == cells.size()

func check_common(label: String, board: Dictionary) -> void:
	var cells: Dictionary = board.cells
	if cells.is_empty():
		fail(label + ": 没有格子")
		return
	var portal: Vector2i = board.portal
	if not cells.has(portal):
		fail(label + ": 传送门不在棋盘上")
	elif cells[portal] != BoardGen.NORMAL:
		fail(label + ": 传送门不在普通格上")
	var start: Vector2i = board.start
	if start.x >= 0:
		if not cells.has(start):
			fail(label + ": 起点不在棋盘上")
		elif cells[start] != BoardGen.NORMAL:
			fail(label + ": 起点不在普通格上")
		# 开局要有得选：起点旁边至少有两个能走的格子
		var around := 0
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cells.has(start + d) and cells[start + d] != BoardGen.BLOCKED:
				around += 1
		if around < 2:
			fail(label + ": 起点旁边只有 %d 个能走的格子，开局只有一条路可走" % around)

func ascii(board: Dictionary) -> String:
	var cells: Dictionary = board.cells
	var lo := Vector2i(9999, 9999)
	var hi := Vector2i(-9999, -9999)
	for k in cells:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
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
			else:
				match cells[cell]:
					BoardGen.NORMAL: line += "."
					BoardGen.CRUMBLE: line += "c"
					BoardGen.BLOCKED: line += "x"
					BoardGen.SPRING: line += "s"
		lines.append(line)
	return "\n".join(lines)

func test_campaign() -> void:
	print("==== 主线棋盘 ====")
	for name in CAMPAIGN:
		var res := load("res://resources/campaign/%s.tres" % name) as LevelResource
		if res == null:
			fail(name + ": 读不到关卡文件")
			continue
		if res.map.is_empty():
			fail(name + ": 关卡没有棋盘")
			continue
		var board := BoardGen.parse_map(res.map)
		check_common(name, board)
		if board.start.x < 0:
			fail(name + ": 没有起点")
			continue
		if not jump_connected(walkable(board.cells), board.start):
			fail(name + ": 有格子连满连击也跳不到")
		print("%s  %s  第 %d 章  鱼 %d  资源 %d" % [name, res.level_name, res.chapter, res.fish_before_end_portal, res.starting_credits])
		print(ascii(board))

func test_endless() -> void:
	print("\n==== 无尽模式：前 %d 关，每关 %d 张 ====" % [ENDLESS_LEVELS, SAMPLES])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	var boards := 0
	var roomy_starts := 0
	for n in ENDLESS_LEVELS:
		var p := BoardGen.params(n)
		var sum_tiles := 0
		var sum_walk := 0
		var sum_crumble := 0
		var sum_blocked := 0
		var sum_spring := 0
		var sum_dist := 0
		for i in SAMPLES:
			var board := BoardGen.generate(n, rng)
			var label := "无尽第 %d 关 第 %d 张" % [n + 1, i + 1]
			boards += 1
			check_common(label, board)
			var cells: Dictionary = board.cells
			var w := walkable(cells)
			# 挖洞和放障碍的时候每一步都保证剩下的还连通，所以格子数不会少于设定值
			var planned := int(round(p.width * p.height * p.ground_ratio))
			if cells.size() < planned:
				fail(label + ": 只有 %d 个格子，比设定的 %d 个少" % [cells.size(), planned])
			# 开局要有得选：只要棋盘上有邻居不少于两个的格子，起点就得是其中之一
			var start_degree := BoardGen.neighbour_count(w, board.start)
			if start_degree >= 2:
				roomy_starts += 1
			else:
				for k in w:
					if BoardGen.neighbour_count(w, Vector2i(k)) >= 2:
						fail(label + ": 起点只有 %d 个邻居，开局只有一条路可走" % start_degree)
						break
			if BoardGen.keep_largest_group(w, rng).size() != w.size():
				fail(label + ": 能走的格子不止连成一块")
			var dist: Dictionary = BoardGen.distances(w, board.start)
			if not dist.has(board.portal):
				fail(label + ": 从起点走不到传送门")
			else:
				sum_dist += dist[board.portal]
				if dist[board.portal] < 3 and w.size() > 12:
					fail(label + ": 传送门离起点只有 %d 步" % dist[board.portal])
			var crumbles := 0
			var blocks := 0
			var springs := 0
			for k in cells:
				if k.x < 0 or k.x >= p.width or k.y < 0 or k.y >= p.height:
					fail(label + ": 格子 %s 越界" % k)
				match cells[k]:
					BoardGen.CRUMBLE: crumbles += 1
					BoardGen.BLOCKED: blocks += 1
					BoardGen.SPRING: springs += 1
			var normal_count := w.size() - crumbles - springs
			if crumbles > ceili(w.size() * p.crumble_ratio) + 1:
				fail(label + ": 脆格 %d 个，超过设定比例 %.2f" % [crumbles, p.crumble_ratio])
			if blocks > ceili(cells.size() * p.blocked_ratio) + 1:
				fail(label + ": 障碍 %d 个，超过设定比例 %.2f" % [blocks, p.blocked_ratio])
			if normal_count < 3:
				fail(label + ": 普通格只剩 %d 个" % normal_count)
			sum_tiles += cells.size()
			sum_walk += w.size()
			sum_crumble += crumbles
			sum_blocked += blocks
			sum_spring += springs
			if i == 0 and (n < 8 or n % 10 == 0):
				print("\n-- 第 %d 关的一张样例（%d×%d）--" % [n + 1, p.width, p.height])
				print(ascii(board))
		if n % 10 == 0 or n == ENDLESS_LEVELS - 1:
			print("第 %2d 关：平均 %.1f 格（能走 %.1f）脆格 %.1f 障碍 %.1f 补给 %.1f  传送门平均离起点 %.1f 步  要吃 %d 条鱼" % [
				n + 1, float(sum_tiles) / SAMPLES, float(sum_walk) / SAMPLES, float(sum_crumble) / SAMPLES,
				float(sum_blocked) / SAMPLES, float(sum_spring) / SAMPLES, float(sum_dist) / SAMPLES, p.fish])
	print("共检查 %d 张随机棋盘，其中 %d 张的起点旁边有不少于两个能走的格子" % [boards, roomy_starts])

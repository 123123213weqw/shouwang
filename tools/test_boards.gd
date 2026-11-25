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
##   3. 摆一局河灯：巡夜 12 关各按固定种子摆一局，长夜抽几更各摆几十局。每一局都从头走一遍核对
##      （每跳够得着、不重复、带沟的地方不靠道具过不去、最后一盏灯收完能进水车），照着路线走必须一步不错就过；
##      再让"随手玩"的机器人（BoardSim）每关打 200 局，报出它的过关率、一步没错的比例和平均踩空次数
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
	test_deals()
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

func test_deals() -> void:
	var greedy_plays := 200
	print("\n==== 摆一局河灯：巡夜 %d 关各摆固定的一局，再让随手玩的机器人每关打 %d 局 ====" % [CAMPAIGN.size(), greedy_plays])
	var rng := RandomNumberGenerator.new()
	for li in CAMPAIGN.size():
		var name: String = CAMPAIGN[li]
		var res := load("res://resources/campaign/%s.tres" % name) as LevelResource
		if res == null or res.map.is_empty():
			fail("%s: 读不到关卡" % name)
			continue
		var board := BoardGen.parse_map(res.map)
		if board.start.x < 0:
			fail("%s: 没有起点，摆不了" % name)
			continue
		var opt := BoardGen.campaign_opt(li, res.fish_before_end_portal)
		var seed := 7000 + li * 37
		rng.seed = seed
		var d := BoardGen.deal(board, opt, rng)
		if d.is_empty():
			fail("%s: 摆不出来（%s）" % [name, BoardGen.last_fail])
			print("   最后一次卡在：" + BoardGen._last_fail_detail)
			continue
		var check := BoardGen.check_deal(board, d, opt)
		if not check.ok:
			fail("%s: 摆出来的这一局走不通：%s" % [name, check.error])
		# 照着路线走（道具的副作用也算在内）：必须一步不错，收完就能进水车
		var fsim := BoardSim.from_deal(board, d, 5, BoardGen.BASE_REACH, true)
		var follow := fsim.follow(d.route)
		if not follow.won or follow.missteps != 0:
			fail("%s: 照着路线走没能一步不错地过关（过了 %s，踩空 %d 次；走到第 %d 步，停在 %s，卡在 %s，收到 %d/%d 盏，连击 %.0f，步数 %d）" % [
				name, follow.won, int(follow.missteps), int(follow.steps), fsim.pos, fsim.stuck_at, fsim.got, fsim.need, fsim.combo, fsim.moves])
			# 一步一步重走一遍，把每一步摆出来的情况打出来
			var trace := BoardSim.from_deal(board, d, 5, BoardGen.BASE_REACH, true)
			for t in d.route:
				var has := trace.things.has(t)
				var can := trace.available().has(t)
				print("      到 %s：上面%s，现在%s，连击 %.0f 能跳 %.2f" % [t, "有东西" if has else "空了", "够得着" if can else "够不着", trace.combo, trace.reach()])
				if not can: break
				trace.land(t)
		# 随手玩：同一关换 200 个种子
		var won := 0
		var perfect := 0
		var missteps := 0
		var failed_deals := 0
		var branches := 0
		var attempts := 0
		for i in greedy_plays:
			rng.seed = seed * 1000 + i
			var dd := BoardGen.deal(board, opt, rng)
			if dd.is_empty():
				failed_deals += 1
				continue
			branches += int(dd.branches)
			attempts += int(dd.attempts)
			var r := BoardSim.from_deal(board, dd, 5, BoardGen.BASE_REACH, true).run()
			if r.won: won += 1
			if r.won and r.missteps == 0: perfect += 1
			missteps += int(r.missteps)
		var dealt := greedy_plays - failed_deals
		print("\n第 %d 关 %s（%d 格）：收 %d 盏，道具 %d 件（带沟 %d），贴极限 %.2f，绕 %.2f" % [
			li + 1, res.level_name, board.cells.size(), int(opt.lamps), int(opt.items), int(opt.gates), float(opt.gap), float(opt.detour)])
		print("   固定的那一局：试了 %d 回摆成，岔路 %d 处，最松的一跳还余 %.2f 格，最后一盏灯%s够得着水车" % [
			int(d.attempts), int(check.branches), float(check.min_slack), "" if d.ends_at_portal else "不"])
		print(BoardGen.deal_ascii(board, d))
		print("   随手玩 %d 局：摆不出来 %d 局；摆出来的里面过关 %.0f%%，一步没错 %.0f%%，平均踩空 %.2f 次；平均岔路 %.1f 处" % [
			greedy_plays, failed_deals, 100.0 * won / maxf(dealt, 1), 100.0 * perfect / maxf(dealt, 1), float(missteps) / maxf(dealt, 1), float(branches) / maxf(dealt, 1)])
		if failed_deals > greedy_plays / 20:
			fail("%s: 有 %d/%d 局摆不出来（%s）" % [name, failed_deals, greedy_plays, BoardGen.last_fail])

	print("\n==== 摆一局河灯：长夜抽几更，每更摆 40 局 ====")
	rng.seed = 20261125
	for n in [0, 3, 6, 10, 15, 20, 30]:
		var p := BoardGen.params(n)
		var won := 0
		var perfect := 0
		var missteps := 0
		var failed_deals := 0
		var tries := 0
		for i in 40:
			var board := BoardGen.generate(n, rng)
			var opt := BoardGen.endless_opt(n, p.fish)
			var d := BoardGen.deal(board, opt, rng)
			if d.is_empty():
				failed_deals += 1
				continue
			var check := BoardGen.check_deal(board, d, opt)
			if not check.ok:
				fail("长夜第 %d 更第 %d 局：摆出来的这一局走不通：%s" % [n + 1, i + 1, check.error])
			tries += int(d.attempts)
			var r := BoardSim.from_deal(board, d, 5, BoardGen.BASE_REACH, true).run()
			if r.won: won += 1
			if r.won and r.missteps == 0: perfect += 1
			missteps += int(r.missteps)
		var dealt := 40 - failed_deals
		print("第 %2d 更：收 %d 盏，道具 %d 件（带沟 %d），贴极限 %.2f  摆不出来 %d 局，平均试 %.1f 回；随手玩：过关 %.0f%%，一步没错 %.0f%%，平均踩空 %.2f" % [
			n + 1, p.fish, int(BoardGen.endless_opt(n, p.fish).items), int(BoardGen.endless_opt(n, p.fish).gates), float(BoardGen.endless_opt(n, p.fish).gap),
			failed_deals, float(tries) / maxf(dealt, 1), 100.0 * won / maxf(dealt, 1), 100.0 * perfect / maxf(dealt, 1), float(missteps) / maxf(dealt, 1)])
		if failed_deals > 4:
			fail("长夜第 %d 更：40 局里有 %d 局摆不出来（%s）" % [n + 1, failed_deals, BoardGen.last_fail])

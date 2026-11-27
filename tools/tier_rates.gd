extends SceneTree
## 难度四档各让"随手玩"的机器人（BoardSim）打多少局，算过关率。不开游戏，纯逻辑：
##   godot --headless --path <工程目录> --script res://tools/tier_rates.gd -- [runs=200] [think=1.0] [tiers=easy,normal,hard,extreme] [ascii=1] [seed=20261126]
##   （tools/playtest/agent.sh a7 rates [局数] [每步想几秒] [档，逗号隔开]）
##
## 摆法和游戏里是同一套代码（BoardGen.ruleset_opt：按难度的规矩改摆法、带风向、最后一跳够不够得着水车），
## 机器人和游戏里的自动试玩也是同一个（BoardSim），所以这里算出来的和真机上是同一种局、同一种打法。
##
## 每一档算三样：
##   1. 巡夜打 N 局（每一局从第一关打起）：每一关现摆一局（随机种子、随机风向），机器人按贪心打法走；
##      没过这一局就到此为止。步数带过关的档，下一关的步数是上一关剩下的（和游戏里一样），
##      所以"到了这一关的时侯还剩几步"也是真实的分布。报每一关"到了的人里过了的占多少"、平均踩空几次、
##      放了几盏灯、因为蜡烛烧完没过的有几局；最后是整局打通的比例
##   2. 巡夜游戏里真正摆出来的那 12 局（种子和游戏里一样：7000 + 关数 × 37，风也照游戏里的规矩刮）：
##      照着路线走的（一步不错）必须 12 关都过——这是"摆出来的局一定有解"的核对；
##      贪心的顺序打一遍（没过就停），再每关都带满步数各打一遍
##   3. 长夜前 12 更，同 1
## think（每走一步想多久，秒）只对开了夜巡的档有影响：机器人自己是不想的，这里按"一个真人每走一步想多久"代入。
## 机器人不学会：重来一关它还是那么走，所以"可以重来"对它的成绩没有帮助（对真人有）。
## 用的是默认角色（守夜人）的数：5 步，连击为 0 时跳 1.1 格、每点连击加 0.2 格、连击算到 10 为止（简单档每一跳再加半格）。
## 它不用主动技能。
## 退出码：每一档游戏里摆好的那 12 局都摆得出来、照着路线走都过得了；四档由易到难（整局打通的比例一档比一档低，
## 每一关的平均过关率一档比一档低 2 个点以上）；第一档随手玩也该有八成以上打穿、每关平均九成八以上；
## 每一档长夜前 12 更"摆不出来"的局不超过 2%。都满足是 0，否则是 1。
## 局数少了会有偶然的起伏：下结论至少打 150 局。

const CAMPAIGN := ["c1_1", "c1_2", "c1_3", "c1_4", "c2_1", "c2_2", "c2_3", "c2_4", "c3_1", "c3_2", "c3_3", "c3_4"]
const ENDLESS_LEVELS := 12
const MOVES := 5                      # 默认角色的步数

## 默认角色在这一档能跳多远（和 main.gd 的 base_reach、deal_options 算的一样）：1.0 加这一档给加的，再加 0.1 的余量
func _reach_for(r: Ruleset) -> Dictionary:
	return {"base": 1.0 + BoardGen.REACH_PAD + r.reach_add, "per": 0.2, "cap": 10.0}
var _levels: Array = []               # LevelResource
var _boards: Array = []               # parse_map 的结果
var _tiers: Array = []                # Ruleset
var _runs := 200
var _think := 1.0
var _seed := 20261126
var _ascii := false                   # 把游戏里摆好的那 12 局画成字符画
var _fail := 0

func _init() -> void:
	_read_args()
	for name in CAMPAIGN:
		var res := load("res://resources/campaign/%s.tres" % name) as LevelResource
		if res == null or res.map.is_empty():
			print("FAIL 读不到关卡 %s" % name)
			_fail += 1
			continue
		_levels.append(res)
		_boards.append(BoardGen.parse_map(res.map))
	_tiers = _load_rulesets()
	print("难度四档的过关率：每一档打 %d 局；机器人每走一步想 %.1f 秒；用的是默认角色（%d 步）" % [_runs, _think, MOVES])
	var summary: Array = []
	for r in _tiers:
		summary.append(_report(r))
	_check(summary)
	print("RESULT failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)

func fail(msg: String) -> void:
	_fail += 1
	print("FAIL " + msg)

## "--" 后面的 key=value
func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		# 只按第一个等号切：set=名字=值 的值自己带着等号
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2: continue
		match kv[0]:
			"runs": _runs = maxi(int(kv[1]), 20)
			"think": _think = maxf(float(kv[1]), 0.0)
			"seed": _seed = int(kv[1])
			"ascii": _ascii = kv[1] == "1"
			"tiers": set_meta("tiers", kv[1].split(","))      # 只算这几档（按 id）
			# 调数值用的：set=名字=值（可以写好几回）把选中的档里这个数临时改掉，不动 .tres。
			# 例：set=moves_cap_add=0 set=moves_bonus=2。名字是 Ruleset 里的属性名
			"set":
				var overrides: Array = get_meta("overrides", [])
				overrides.append(kv[1])          # kv[1] 是第一个等号后面的全部："名字=值"
				set_meta("overrides", overrides)

## resources/rulesets/ 里每一档（按文件名排，也就是由易到难）
func _load_rulesets() -> Array:
	var out: Array = []
	var names: Array[String] = []
	var dir := DirAccess.open("res://resources/rulesets")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".tres"): names.append(f)
	names.sort()
	var want: PackedStringArray = get_meta("tiers", PackedStringArray()) if has_meta("tiers") else PackedStringArray()
	for f in names:
		var r := load("res://resources/rulesets/" + f) as Ruleset
		if r == null:
			fail("读不到 resources/rulesets/" + f)
			continue
		if want.is_empty() or want.has(r.id): out.append(r)
	# 调数值：命令行上让改的数
	var overrides: Array = get_meta("overrides", []) if has_meta("overrides") else []
	if not overrides.is_empty():
		var what: Array[String] = []
		for o in overrides:
			var kv: PackedStringArray = (o as String).split("=")
			if kv.size() != 2: continue
			var touched: Array[String] = []
			for rr in out:
				if kv[0] in rr:                       # 这个数确实是 Ruleset 里的
					rr.set(kv[0], _as_value(kv[1], rr.get(kv[0])))
					if not touched.has(rr.id): touched.append(rr.id)
			what.append("%s=%s（%s）" % [kv[0], kv[1], "、".join(touched)])
		print("临时改过的数（没写进 .tres）：" + "；".join(what))
	return out

## 按原来的类型把命令行上的字转成数
func _as_value(text: String, like: Variant) -> Variant:
	if like is bool: return text == "true" or text == "1"
	if like is int: return int(text)
	if like is float: return float(text)
	return text

# ---------------------------------------------------------------- 摆一局、打一局

## 按这一档的规矩摆一局，让机器人从带 moves 步进来打完。摆不出来返回 {"dealt": false}
func _play(r: Ruleset, board: Dictionary, index: int, moves: int, deal_seed: int, wind: Vector2i, endless: bool, last_wind := Vector2i.ZERO, avoid := Vector2i.ZERO) -> Dictionary:
	var lamps: int = BoardGen.params(index).fish if endless else int(_levels[index].fish_before_end_portal)
	var n := maxi(1, int(round(lamps * r.lamp_scale)))
	var base: Dictionary = BoardGen.endless_opt(index, n) if endless else BoardGen.campaign_opt(index, n)
	base.reach = _reach_for(r)
	# 和游戏里一样：摆一局，有风向的规矩时连风向一起定（头一个方向摆不出来就换一个方向）。
	# last_wind 是上一关"头一个试的方向"：只跟种子有关，所以从头打上来和直接跳到这一关是同一种风
	var picked := BoardGen.deal_tiered(board, base, r, deal_seed, last_wind, avoid)
	var d: Dictionary = picked.deal
	if d.is_empty():
		return {"dealt": false, "why": BoardGen.last_fail}
	wind = picked.wind
	var rng := RandomNumberGenerator.new()
	rng.seed = deal_seed          # 和游戏里一样：摆棋用自己的随机数，补给格从种子重新开始
	# 和游戏里一样：先摆出路线，再在路线以外增减补给格
	var cells: Dictionary = (board.cells as Dictionary).duplicate()
	BoardGen.adjust_springs(cells, board.start, board.portal, r.spring_add, d.route, rng)
	var sim := BoardSim.from_deal({"cells": cells, "portal": board.portal, "start": board.start}, d, moves, _reach_for(r), r.portal_free)
	sim.max_moves = _max_moves(r)
	sim.held = r.hold_lamps
	sim.hold_cost = r.hold_cost
	sim.wind = wind
	sim.wind_bonus = r.wind_bonus
	sim.wind_penalty = r.wind_penalty
	sim.wind_floor = r.wind_floor
	if r.night_watch:
		sim.enable_night(r.night_seconds, r.night_every, r.night_gain, _think)
	# 步数没带满进关：路线以外多一个蒸笼（游戏里放在第一个这样的空格上）
	if moves < sim.max_moves:
		for c in cells:
			if c != board.start and c != board.portal and not d.route.has(c):
				sim.things[c] = BoardSim.HEART
				break
	var res: Dictionary = sim.run()
	res["dealt"] = true
	res["deal"] = d
	res["sim"] = sim
	res["board"] = {"cells": cells, "portal": board.portal, "start": board.start}
	res["wind"] = wind
	res["wind_tried"] = picked.wind_tried
	res["initial_wind"] = _initial_wind(r, deal_seed, last_wind)
	return res

func _max_moves(r: Ruleset) -> int:
	return maxi(MOVES + r.moves_add, 1)

## 过了一关以后，下一关带几步进来（和 main.next_level 一个道理）
## 这一关头一个试的风向（和游戏里 main._roll_wind 一个算法）。有风向的规矩才有，没有是零
func _initial_wind(r: Ruleset, deal_seed: int, prev: Vector2i) -> Vector2i:
	return BoardGen.level_initial_wind(deal_seed, prev) if r.wind else Vector2i.ZERO

func _next_moves(r: Ruleset, left: int, endless: bool) -> int:
	if endless:
		return mini(left + 1 + r.moves_bonus, _max_moves(r) + r.moves_cap_add) if r.endless_carry else _max_moves(r)
	return mini(left + r.moves_bonus, _max_moves(r) + r.moves_cap_add) if r.moves_carry else _max_moves(r)

## 一局：从第一关打起，没过就停。st 是每一关的统计（reached 过了几回、passed 过关几回……）。返回打过了几关
func _run(r: Ruleset, st: Array, rng: RandomNumberGenerator, endless: bool) -> int:
	var moves := _max_moves(r)
	var wind := Vector2i.ZERO            # 上一关头一个试的风向
	var last: Vector2i = Vector2i.ZERO   # 上一关最后刮的风向（换过方向的以它为准）
	var count: int = ENDLESS_LEVELS if endless else _levels.size()
	for i in count:
		var board: Dictionary = BoardGen.generate(i, rng) if endless else _boards[i]
		var res := _play(r, board, i, moves, rng.randi_range(1, 2000000000), Vector2i.ZERO, endless, wind, last)
		var s: Dictionary = st[i]
		s.reached = int(s.reached) + 1
		if not res.dealt:
			s.nodeal = int(s.nodeal) + 1
			if int(s.nodeal) == 1: print("      第 %d 关摆不出来的原因（记头一回的）：%s" % [i + 1, res.why])
			return i
		wind = res.initial_wind
		last = res.wind
		# 头一个风向摆不出来、换过风向的有几局
		if int(res.wind_tried) > 1: s.tried = int(s.tried) + 1
		s.missteps = int(s.missteps) + int(res.missteps)
		s.placed = int(s.placed) + int(res.placed)
		if res.night_lost: s.night_lost = int(s.night_lost) + 1
		if not res.won:
			return i
		s.passed = int(s.passed) + 1
		moves = _next_moves(r, int(res.moves), endless)
	return count

func _blank_stats(n: int) -> Array:
	var st: Array = []
	for i in n:
		st.append({"reached": 0, "passed": 0, "missteps": 0, "placed": 0, "night_lost": 0, "nodeal": 0, "tried": 0})
	return st

# ---------------------------------------------------------------- 报表

## 打一档。返回 {"id", "clear" 整局打通的比例, "avg" 每关平均过关率, "fixed_ok"} 给最后核对用
func _report(r: Ruleset) -> Dictionary:
	print("\n==== %s（%s）：%d 条加码的规矩 ====" % [r.title, r.id, r.rule_count()])
	print("   " + "；".join(r.rule_lines()))
	var out := {"id": r.id, "title": r.title, "clear": 0.0, "avg": 0.0, "fixed_ok": true, "endless_dealt": 0, "endless_nodeal": 0}

	# 1. 巡夜打 N 局
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 17 * r.tier
	var st := _blank_stats(_levels.size())
	var cleared := 0
	for i in _runs:
		if _run(r, st, rng, false) >= _levels.size(): cleared += 1
	print("巡夜 %d 局（每局从第一关打起，没过就停；步数带过关的档，下一关的步数是上一关剩下的）：" % _runs)
	out.avg = _print_table(st, false)
	out.clear = 100.0 * cleared / _runs
	print("   整局打通 %.1f%%（%d 局里 %d 局）；每一关平均过关率 %.1f%%" % [out.clear, _runs, cleared, out.avg])

	# 2. 游戏里真正摆出来的那 12 局
	out.fixed_ok = _fixed(r)

	# 3. 长夜
	rng.seed = _seed + 911 * r.tier
	var st2 := _blank_stats(ENDLESS_LEVELS)
	var cleared2 := 0
	for i in _runs:
		if _run(r, st2, rng, true) >= ENDLESS_LEVELS: cleared2 += 1
	print("长夜前 %d 更，%d 局（长夜里每一档都带步数，每更补一步）：" % [ENDLESS_LEVELS, _runs])
	_print_table(st2, true)
	print("   %d 更全过 %.1f%%（%d 局里 %d 局）" % [ENDLESS_LEVELS, 100.0 * cleared2 / _runs, _runs, cleared2])
	for s in st2:
		out.endless_dealt = int(out.endless_dealt) + int(s.reached)
		out.endless_nodeal = int(out.endless_nodeal) + int(s.nodeal)
	return out

## 一张表：每一关到了几回、过了几回、过关率、平均踩空、平均放灯、蜡烛烧完没过的。返回每一关平均过关率
func _print_table(st: Array, endless: bool) -> float:
	print("   %-4s %-10s %5s %5s %8s %8s %8s %8s %8s %s" % ["关", "名称", "到了", "过了", "过关率", "平均踩空", "平均放灯", "蜡烛烧完", "换过风向", "摆不出来"])
	var total := 0.0
	for i in st.size():
		var s: Dictionary = st[i]
		var reached: int = int(s.reached)
		if reached == 0:
			print("   %-4d %-10s %5s" % [i + 1, "—", "没人在这一关开始前就先输光了"])
			continue
		var rate: float = 100.0 * int(s.passed) / reached
		total += rate
		var what: String = "第 %d 更" % (i + 1) if endless else _levels[i].level_name
		print("   %-4d %-10s %5d %5d %7.1f%% %8.2f %8.2f %8d %8d %8d" % [i + 1, what, reached, int(s.passed), rate,
			float(s.missteps) / reached, float(s.placed) / reached, int(s.night_lost), int(s.tried), int(s.nodeal)])
	return total / st.size()

## 巡夜游戏里真正摆出来的那 12 局（种子、风都和游戏里一样）。返回是不是都摆得出来、照着路线走都过得了
func _fixed(r: Ruleset) -> bool:
	print("游戏里摆好的那 12 局（种子、风都和游戏里一样）：")
	var ok := true
	var wind := Vector2i.ZERO            # 上一关头一个试的风向
	var last: Vector2i = Vector2i.ZERO   # 上一关最后刮的风向
	var moves := _max_moves(r)
	var line_route: Array[String] = []
	var line_greedy: Array[String] = []
	var line_full: Array[String] = []
	var stopped := -1
	for i in _levels.size():
		var deal_seed: int = _levels[i].deal_seed if _levels[i].deal_seed != 0 else 7000 + i * 37
		var res := _play(r, _boards[i], i, moves, deal_seed, Vector2i.ZERO, false, wind, last)
		wind = res.initial_wind
		last = res.wind
		var wind_txt := "" if res.wind == Vector2i.ZERO else "，风 %s%s" % [_wind_name(res.wind), "（头一个方向摆不出来，换过）" if int(res.wind_tried) > 1 else ""]
		if not res.dealt:
			ok = false
			fail("%s 第 %d 关：按这一档的规矩摆不出河灯（%s）。游戏里会退回边收边刷" % [r.title, i + 1, res.why])
			line_route.append("×摆不出")
			line_greedy.append("×")
			line_full.append("×")
			continue
		var d: Dictionary = res.deal
		# 照着路线走：必须一步不错地过
		var fsim := BoardSim.from_deal(res.board, d, moves, _reach_for(r), r.portal_free)
		fsim.max_moves = res.sim.max_moves
		fsim.wind = res.wind
		fsim.wind_bonus = r.wind_bonus
		fsim.wind_penalty = r.wind_penalty
		fsim.wind_floor = r.wind_floor
		var follow: Dictionary = fsim.follow(d.route)
		if not follow.won or follow.missteps != 0:
			ok = false
			fail("%s 第 %d 关：照着路线走没能一步不错地过关（过了 %s，踩空 %d 次，停在 %s，卡在 %s）%s" % [
				r.title, i + 1, follow.won, int(follow.missteps), fsim.pos, fsim.stuck_at, wind_txt])
		line_route.append("过" if follow.won and follow.missteps == 0 else "×")
		# 贪心：顺序打（带着上一关剩下的步数；上一关没过就当它是带着满步数加一进来的）
		line_greedy.append("过" if res.won else "×")
		if not res.won and stopped < 0: stopped = i
		moves = _next_moves(r, int(res.moves), false) if res.won else mini(_max_moves(r) + 1, _max_moves(r) + 2)
		# 贪心：每关都带满步数
		var full := _play(r, _boards[i], i, _max_moves(r), deal_seed, Vector2i.ZERO, false, wind)
		line_full.append("过" if full.won else "×")
		if _ascii:
			# 字符画每一行前面都带四个空格和一个竖线：看总表的时侯把这些行滤掉就行
			print("    | -- 第 %d 关 %s：收 %d 盏，道具 %d 件（带沟 %d），换了 %d 个方向才摆出来%s --" % [i + 1, _levels[i].level_name, int(d.lamps), int(d.kinds.size()) - int(d.lamps),
				d.kinds.filter(func(k): return k == BoardGen.Thing.UMBRELLA or k == BoardGen.Thing.SHOE or k == BoardGen.Thing.LOTUS).size(), int(res.wind_tried), wind_txt])
			for row in BoardGen.deal_ascii(_boards[i], d).split("\n"):
				print("    | " + row)
	print("   照着路线走（必须都过）：" + " ".join(line_route))
	print("   贪心，顺序打（步数带过关的档带着上一关剩下的）：" + " ".join(line_greedy) + ("" if stopped < 0 else "   → 打到第 %d 关为止" % (stopped + 1)))
	print("   贪心，每关都带满步数进来：" + " ".join(line_full))
	return ok

func _wind_name(w: Vector2i) -> String:
	if w.y > 0: return "北风(往近处刮)"
	if w.y < 0: return "南风(往远处刮)"
	if w.x > 0: return "西风(往右刮)"
	return "东风(往左刮)"

## 四档是不是由易到难；简单档是不是每关都过得了
func _check(summary: Array) -> void:
	print("\n==== 小结 ====")
	for s in summary:
		print("   %-6s 整局打通 %5.1f%%   每关平均过关率 %5.1f%%   摆好的 12 局%s" % [s.title, s.clear, s.avg, "都摆得出来、照着路线走都过" if s.fixed_ok else "有问题"])
	if summary.size() < 2: return
	for i in range(1, summary.size()):
		var a: Dictionary = summary[i - 1]
		var b: Dictionary = summary[i]
		if b.clear >= a.clear:
			fail("%s 整局打通 %.1f%%，没有比 %s 的 %.1f%% 低" % [b.title, b.clear, a.title, a.clear])
		if b.avg > a.avg - 2.0:
			fail("%s 每关平均过关率 %.1f%%，没有比 %s 的 %.1f%% 低 2 个点" % [b.title, b.avg, a.title, a.avg])
	var first: Dictionary = summary[0]
	if first.clear < 80.0:
		fail("%s 整局打通只有 %.1f%%（随手玩的机器人也该有八成以上打穿，不然算不上简单）" % [first.title, first.clear])
	if first.avg < 98.0:
		fail("%s 每关平均过关率只有 %.1f%%（简单档该有九成八以上）" % [first.title, first.avg])
	# 长夜里"摆不出来"的局：摆不出保证有解的路线，游戏里那一更只能退回边收边刷。多了就是这一档的摆法有问题
	#（简单档原先道具减两件，后几更有 6% 摆不出来，就是这样查出来的）
	for s in summary:
		var dealt: int = int(s.get("endless_dealt", 0))
		var nodeal: int = int(s.get("endless_nodeal", 0))
		if dealt > 0 and float(nodeal) / float(dealt) > 0.02:
			fail("%s 长夜前 12 更有 %d/%d 局（%.1f%%）摆不出来，超过 2%%：多半是道具或带沟的道具减太多了" % [s.title, nodeal, dealt, 100.0 * nodeal / dealt])

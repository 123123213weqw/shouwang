extends SceneTree
## 给"摆河灯"调难度曲线用的扫描脚本，不开游戏：
##   godot --headless --path <工程目录> --script res://tools/tune_deals.gd
##
## 对每一格（巡夜某一关或长夜某一更 × 某一档 gap）摆 plays 局，每一局都让"随手玩"的贪心机器人（BoardSim，成绩是下限）
## 打一遍，统计：摆不出来的比例和主因、过关率、一步没错就过的比例、平均踩空次数、平均岔路数。
##   巡夜 12 关：gap 取 0.0 到 0.9 共 10 档，detour / items / gates 用 campaign_opt 现在的值；棋盘和灯数就是 resources/campaign 里那份
##   长夜：n 取 0、3、6、10、15、20、25、30，gap 同样 10 档，其余用 endless_opt 现在的值；每局用 BoardGen.generate 现生成一张棋盘
## 种子是固定的（见 make_play），同一份代码跑出来结果一样；同一关（更）的第 i 局在 10 档 gap 下用同一个种子，档与档之间好对比。
##
## 两种过关率：
##   过关%    BoardSim.run() 原样的结果，和 test_boards.gd 一个口径
##   修正过关% 灯已经收齐、只是机器人走不进水车的局也算过。灯收齐以后踩空格不花步、连击也不变，真人只要从停下的地方
##            沿空格走得过去、或者再跳一下够得着，就一定能进水车；机器人做不到，是因为它只挑"离水车直线最近"的第一步，
##            水车躲在障碍后面时会在墙根下来回踱步（走满 500 步），或者隔着一跳的地方它不会"先走再跳"
##            （BoardSim 后来改成按走过去的步数裁断，来回踱步的毛病没有了；这一列留着做对照，现在应该和上一列基本一样）
## 两种都是"摆出来的局里面"的占比；摆不出来的局单独记在"摆不出"一栏。
##
## 可选参数（写在 -- 后面）：
##   only=c3,e4       只扫这些关：c3 是巡夜第 3 关，e4 是长夜第 4 更（也就是 n = 3）；不写就是全扫
##   plays=150        每格摆几局
##   gaps=0,0.5,0.9   只扫这几档 gap（不写就是 0.0 到 0.9 共 10 档）
##   seeds            每一档下面多打贪心打输的局、踩空以后才过的局各是第几局（想给巡夜换固定种子的那一局时用）
##   variants         不扫主表，改扫"别的办法"第一轮：每一关在现在的摆法上一次只动一个数（见 SENS），默认只扫 0.0、0.5、0.9 三档 gap
##   combos           "别的办法"第二轮：把几个数一起改。巡夜照 COMBOS 表，长夜在 n = 6、10、15、20、25、30 上摆"道具件数 × 带沟件数"的小网格
##   show=c3:0.4:17   不扫，只把某一局画出来（巡夜第 3 关、gap 0.4、第 17 局，局号从 1 数起），并把贪心机器人一步步怎么走打出来；
##                    任务编号也可以写"别的办法"里的，比如 c5#D0.1:0.5:17（第一轮）或 c5#K1:0.5:17（第二轮）或 e7#I4G1:0.5:17（长夜小网格）；
##                    第一轮的编号是"关的编号#动了哪个数改成多少"（D 绕路、L 灯数、I 道具、G 带沟的道具），完整的表在对应的运行日志里
## 退出码恒为 0，跑没跑完看日志最后一行的 TUNE DONE。

const CAMPAIGN := [
	"c1_1", "c1_2", "c1_3", "c1_4",
	"c2_1", "c2_2", "c2_3", "c2_4",
	"c3_1", "c3_2", "c3_3", "c3_4",
]
const ENDLESS_NS := [0, 3, 6, 10, 15, 20, 25, 30]
const GAPS := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
const VARIANT_GAPS := [0.0, 0.5, 0.9]
const PLAYS := 150            # 每格摆几局
const MOVES := 5              # 开局的步数，同 test_boards.gd
const STEP_LIMIT := 500       # 一局最多走几步，同 BoardSim.run 的默认值
const CAMP_SEED := 7000       # 巡夜的种子，同 test_boards.gd：固定的一局是 7000 + 关序号 × 37，第 i 局（从 0 数）是它的 1000 倍加 i
const ENDLESS_SEED := 20261125
const THING_NAMES := "灯大莲伞鞋笠盒车钱"     # 路线上的东西叫什么，顺序同 BoardGen.Thing

## "别的办法"：带 -- variants 时，每一关在现在的摆法上按这张表一次只动一个数（key 是 deal() 的 opt 里的键），
## 看贪心机器人的过关率动不动。value 是直接改成多少，delta 是在现在的数上加几
const SENS := [
	{"key": "detour", "code": "D", "value": 0.1, "note": "几乎不绕路（detour 0.1）"},
	{"key": "detour", "code": "D", "value": 0.8, "note": "很绕（detour 0.8）"},
	{"key": "lamps", "code": "L", "delta": -2, "note": "少两盏灯"},
	{"key": "lamps", "code": "L", "delta": 2, "note": "多两盏灯"},
	{"key": "items", "code": "I", "delta": -1, "note": "少一件道具"},
	{"key": "items", "code": "I", "delta": 2, "note": "多两件道具"},
	{"key": "gates", "code": "G", "value": 0, "note": "道具都不带沟"},
]

## 第二轮"别的办法"：一次只动一个数到不了目标的关，把几个数一起改（要带 -- combos 才扫，同样只扫 0.0、0.5、0.9 三档 gap）。
## 巡夜照这张表：where 是关的编号，override 是要改成的数（键同 deal() 的 opt）。
## 第 10 关不在这里：这张图眼看要换，换完再扫
const COMBOS := [
	{"where": "c3", "override": {"lamps": 7}, "note": "少一盏灯（7 盏）"},
	{"where": "c3", "override": {"lamps": 7, "items": 2}, "note": "少一盏灯、多一件道具"},
	{"where": "c3", "override": {"lamps": 6, "items": 2}, "note": "少两盏灯、多一件道具"},
	{"where": "c5", "override": {"detour": 0.8, "items": 1, "lamps": 11}, "note": "很绕、少一件道具、多两盏灯"},
	{"where": "c5", "override": {"detour": 0.8, "items": 1, "lamps": 11, "gates": 0}, "note": "很绕、少一件道具、多两盏灯、不带沟"},
	{"where": "c6", "override": {"detour": 0.8, "items": 1, "lamps": 9}, "note": "很绕、少一件道具、多一盏灯"},
	{"where": "c6", "override": {"detour": 0.8, "items": 1, "lamps": 9, "gates": 0}, "note": "很绕、少一件道具、多一盏灯、不带沟"},
	{"where": "c7", "override": {"detour": 0.8, "items": 1, "lamps": 8}, "note": "很绕、少一件道具、多一盏灯"},
	{"where": "c7", "override": {"detour": 0.8, "items": 1, "lamps": 8, "gates": 0}, "note": "很绕、少一件道具、多一盏灯、不带沟"},
	{"where": "c8", "override": {"detour": 0.8, "items": 1, "lamps": 9}, "note": "很绕、少一件道具"},
	{"where": "c8", "override": {"detour": 0.8, "items": 1, "lamps": 9, "gates": 0}, "note": "很绕、少一件道具、不带沟"},
	{"where": "c9", "override": {"gates": 1}, "note": "带沟的少一件"},
	{"where": "c9", "override": {"gates": 1, "items": 4}, "note": "带沟的少一件、多一件道具"},
	{"where": "c9", "override": {"gates": 0}, "note": "不带沟"},
	{"where": "c11", "override": {"gates": 1}, "note": "带沟的少一件"},
	{"where": "c11", "override": {"gates": 2, "items": 4}, "note": "多一件道具"},
	{"where": "c12", "override": {"lamps": 17}, "note": "少一盏灯"},
	{"where": "c12", "override": {"lamps": 16, "gates": 1}, "note": "少两盏灯、带沟的少一件"},
	{"where": "c12", "override": {"gates": 1}, "note": "带沟的少一件"},
	{"where": "c12", "override": {"gates": 2, "items": 4}, "note": "多一件道具"},
	# 下面几条是看完前面的结果以后补的：第 6 关怎么都压不下去，试试不要道具、把灯加到 clamp_lamps 允许的上限
	{"where": "c5", "override": {"detour": 0.8, "items": 2, "lamps": 11}, "note": "很绕、多一盏灯（加到上限）"},
	{"where": "c6", "override": {"items": 0, "lamps": 10}, "note": "不要道具、多两盏灯"},
	{"where": "c6", "override": {"items": 0, "lamps": 10, "detour": 0.8}, "note": "很绕、不要道具、多两盏灯"},
	{"where": "c8", "override": {"detour": 0.8, "items": 0, "lamps": 10}, "note": "很绕、不要道具、多一盏灯"},
]
## 长夜不列表：这几更每更把"道具件数 × 带沟件数"摆一遍小网格
const GRID_NS := [6, 10, 15, 20, 25, 30]
const GRID_ITEMS := [1, 2, 3, 4, 5, 6]
const GRID_GATES := [0, 1, 2, 3]

## 每一档打成一行的各栏：名字和宽度（最后一栏不限宽）
const COLS := [
	["gap", 5], ["摆不出局/%", 12], ["过关%", 7], ["修正过关%", 11], ["一步没错%", 11], ["平均踩空", 10],
	["平均岔路", 10], ["平均灯数", 10], ["平均试回", 10], ["贴极限跳%", 11], ["断连击够不着%", 15],
	["输时差几盏", 12], ["固定局", 16],
]

var plays := PLAYS
var gaps: Array = GAPS.duplicate()

## 一格（某一关、某一档 gap）的统计
class Cell:
	var gap := 0.0
	var plays := 0
	var dealt := 0              # 摆成的局数
	var failed := 0             # 摆不出来的局数
	var won := 0                # 贪心机器人照 BoardSim.run() 的结果过关的局数
	var fixed := 0              # 灯已收齐、机器人没走进水车，但人走得进的局数
	var perfect := 0            # 一步没错就过的
	var missteps := 0
	var branches := 0
	var attempts := 0           # 摆成各局一共试了几回
	var lamps := 0              # 摆成各局实际摆了几盏灯（clamp_lamps 可能比关卡设的少）
	var route_steps := 0        # 摆成各局的路线一共几跳
	var tight := 0              # 其中"贴着极限"的跳：连击比路线上少两点就够不着
	var blocked := 0            # 其中"断了连击就够不着"的跳：踩空一次以后直接跳不过去
	var lost_short := 0         # 输的局一共还差几盏灯
	var lost_full := 0          # 灯已经收齐、却进不了水车的局数
	var over_limit := 0         # 走满 STEP_LIMIT 步还没结束的局数
	var follow_bad := 0         # 照着路线走却没能一步不错地过的局数
	var fail_tries: Dictionary = {}    # 摆不出来的原因 -> 卡住的回数
	var fail_total := 0
	var last_detail := ""       # 最近一回长路线卡在哪（BoardGen._last_fail_detail）
	var fail_seeds: Array = []         # 摆不出来的局是第几局（只记头几个）
	var lost_seeds: Array = []         # 贪心打输的局是第几局（只记头几个）
	var sloppy_seeds: Array = []       # 踩空以后才过的局是第几局（只记头几个）
	var fixed_text := "-"              # 巡夜固定种子的那一局，贪心打得怎么样
	var msec := 0

	func lost() -> int:
		return dealt - won

	## a 占 b 的百分比
	func share(a: int, b: int) -> float:
		return 100.0 * a / maxf(b, 1)

	## a / b 的平均值
	func mean(a: int, b: int) -> float:
		return float(a) / maxf(b, 1)


func _init() -> void:
	var args := read_args()
	var t0 := Time.get_ticks_msec()
	plays = maxi(int(args.get("plays", PLAYS)), 1)
	var bases := all_base_jobs()
	var jobs: Array = []
	if args.has("show"):
		gaps = GAPS.duplicate()
		show_deal(bases + make_variants(bases) + make_combos(bases), str(args.show))
	else:
		if args.has("combos"):
			gaps = VARIANT_GAPS.duplicate()
			jobs = make_combos(bases)
		elif args.has("variants"):
			gaps = VARIANT_GAPS.duplicate()
			jobs = make_variants(bases)
		else:
			jobs = bases
		if args.has("gaps"):
			gaps = []
			for g in str(args.gaps).split(",", false):
				gaps.append(float(g))
		jobs = filter_jobs(jobs, str(args.get("only", "")))
		var mode := ""
		if args.has("combos"): mode = "combos"
		elif args.has("variants"): mode = "variants"
		run_scan(jobs, args.has("seeds"), mode)
	print("\nTUNE DONE 任务 %d 个，每格 %d 局，用时 %d 秒" % [jobs.size(), plays, int((Time.get_ticks_msec() - t0) / 1000.0)])
	quit(0)


## -- 后面的参数：key=value；没有等号的记成 key=true
func read_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var at := a.find("=")
		if at < 0: out[a] = true
		else: out[a.substr(0, at)] = a.substr(at + 1)
	return out


## 巡夜 12 关和长夜 8 更各是一个任务。kind 是 campaign 或 endless，level 是关（更）的序号（都从 0 数起），
## lamps 是关卡设的灯数，override 是在这个基础上要改掉的几个摆法参数（主表里是空的）
func all_base_jobs() -> Array:
	var out: Array = []
	for li in CAMPAIGN.size():
		var res := load("res://resources/campaign/%s.tres" % CAMPAIGN[li]) as LevelResource
		if res == null or res.map.is_empty():
			print("读不到关卡 %s，跳过" % CAMPAIGN[li])
			continue
		out.append({"id": "c%d" % (li + 1), "kind": "campaign", "level": li, "lamps": res.fish_before_end_portal,
			"board": BoardGen.parse_map(res.map), "name": "第 %d 关 %s" % [li + 1, res.level_name],
			"note": "", "override": {}})
	for n in ENDLESS_NS:
		out.append({"id": "e%d" % (n + 1), "kind": "endless", "level": n, "lamps": BoardGen.params(n).fish,
			"board": {}, "name": "长夜 n=%d（第 %d 更）" % [n, n + 1], "note": "", "override": {}})
	return out


## 这一关现在的摆法（campaign_opt / endless_opt 给的）
func current_opt(job: Dictionary) -> Dictionary:
	if job.kind == "campaign":
		return BoardGen.campaign_opt(int(job.level), int(job.lamps))
	return BoardGen.endless_opt(int(job.level), BoardGen.params(int(job.level)).fish)


## "别的办法"的任务：每一关先来一行"现在的摆法"，再按 SENS 一次只动一个数
func make_variants(bases: Array) -> Array:
	var out: Array = []
	for b in bases:
		out.append(basis_of(b))
		var opt := current_opt(b)
		for s in SENS:
			var value = s.value if s.has("value") else opt.get(s.key, 0) + s.get("delta", 0)
			out.append(variant_of(b, "%s%s" % [s.code, str(value)], {s.key: value}, s.note))
	return out


## 第二轮"别的办法"：把几个数一起改。巡夜照 COMBOS 表；长夜在 GRID_NS 这几更上摆"道具件数 × 带沟件数"的小网格
func make_combos(bases: Array) -> Array:
	var out: Array = []
	for b in bases:
		var mine: Array = []
		if b.kind == "campaign":
			var k := 0
			for c in COMBOS:
				if c["where"] != b.id: continue
				k += 1
				mine.append(variant_of(b, "K%d" % k, c["override"], c["note"]))
		elif int(b.level) in GRID_NS:
			for it in GRID_ITEMS:
				for g in GRID_GATES:
					if g > it: continue
					mine.append(variant_of(b, "I%dG%d" % [it, g], {"items": it, "gates": g}, "道具 %d 件（带沟 %d）" % [it, g]))
		if mine.is_empty(): continue
		out.append(basis_of(b))
		out.append_array(mine)
	return out


## "现在的摆法"那一行
func basis_of(b: Dictionary) -> Dictionary:
	var now: Dictionary = b.duplicate()
	now.note = "现在的摆法"
	return now


## 在原来那关的基础上派生出一个"别的办法"的任务。编号是"关的编号#标签"
func variant_of(b: Dictionary, tag: String, override: Dictionary, note: String) -> Dictionary:
	var job: Dictionary = b.duplicate()
	job.id = "%s#%s" % [b.id, tag]
	job.note = note
	job.override = override
	job.base = b.id
	return job


## 只要 only 里点名的任务（逗号隔开）；没写就全要。别的办法里，点名的是原来那一关的编号
func filter_jobs(jobs: Array, only: String) -> Array:
	if only.strip_edges().is_empty(): return jobs
	var ids := only.split(",", false)
	var out: Array = []
	for j in jobs:
		for id in ids:
			var want := id.strip_edges()
			if j.id == want or str(j.get("base", "")) == want:
				out.append(j)
				break
	return out


## 第 i 局（从 0 数）用的棋盘和摆法（gap 还没定）：先按固定的公式设种子，再照 test_boards.gd 的办法取棋盘和现在的摆法
func make_play(job: Dictionary, i: int, rng: RandomNumberGenerator) -> Dictionary:
	if job.kind == "campaign":
		var li: int = job.level
		rng.seed = (CAMP_SEED + li * 37) * 1000 + i
		var copt := current_opt(job)
		copt.merge(job.get("override", {}), true)
		return {"board": job.board, "opt": copt}
	var n: int = job.level
	rng.seed = ENDLESS_SEED + n * 100003 + i
	var board := BoardGen.generate(n, rng)
	var eopt := current_opt(job)
	eopt.merge(job.get("override", {}), true)
	return {"board": board, "opt": eopt}


## mode 是空串就扫主表；variants / combos 是"别的办法"，扫完多打一份汇总
func run_scan(jobs: Array, with_seeds: bool, mode: String) -> void:
	print("==== 摆河灯难度扫描：每格 %d 局，贪心机器人开局 %d 步；过关率都是摆出来的局里面的占比 ====" % [plays, MOVES])
	var all_cells: Array = []
	for job in jobs:
		all_cells.append(scan_job(job, with_seeds, mode != ""))
	if mode != "":
		print_variant_matrices(jobs, all_cells, mode)
		return
	for kind in ["campaign", "endless"]:
		var some := false
		for job in jobs:
			if job.kind == kind: some = true
		if not some: continue
		print_matrix("%s：贪心机器人的过关率（%%）" % ("巡夜" if kind == "campaign" else "长夜"), jobs, all_cells, kind, "win")
		print_matrix("修正后的过关率（%%）：灯已收齐、只是机器人走不进水车的局也算人能过", jobs, all_cells, kind, "winfix")
		print_matrix("摆不出来的局数（每格 %d 局）" % plays, jobs, all_cells, kind, "fail")
		print_matrix("一步没错就过的比例（%）", jobs, all_cells, kind, "perfect")
		print_matrix("平均踩空次数", jobs, all_cells, kind, "missteps")
		print_matrix("平均岔路数（处）", jobs, all_cells, kind, "branches")


## 扫一个任务的各档 gap，一档一行，扫完一档就打出来
func scan_job(job: Dictionary, with_seeds: bool, brief: bool) -> Array:
	print_header(job, brief)
	var head: Array = []
	for col in COLS:
		head.append(pad_right(col[0], int(col[1])))
	head.append("摆不出的主因")
	print("  ".join(head))
	var t0 := Time.get_ticks_msec()
	var cells: Array = []
	for gap in gaps:
		var c := scan_cell(job, float(gap))
		cells.append(c)
		print(row_text(c))
		var note := note_text(c, with_seeds)
		if note != "": print(note)
	print("（用时 %d 秒）" % int((Time.get_ticks_msec() - t0) / 1000.0))
	print("")
	return cells


func print_header(job: Dictionary, brief: bool) -> void:
	var opt := current_opt(job)
	var walkable := 0
	if job.kind == "campaign":
		for k in job.board.cells:
			if job.board.cells[k] != BoardGen.BLOCKED: walkable += 1
		print("\n==== %s%s（%s，能走 %d 格）：设 %d 盏，道具 %d 件（带沟 %d），绕路 %.2f；现在的曲线 gap %.2f%s ====" % [
			id_tag(job), job.name, CAMPAIGN[int(job.level)], walkable, job.lamps, int(opt.items), int(opt.gates), float(opt.detour), float(opt.gap), note_of(job)])
		if not brief: print(BoardGen.deal_ascii(job.board, {}))
	else:
		var n: int = job.level
		var rng := RandomNumberGenerator.new()
		var p := BoardGen.params(n)
		for i in plays:
			walkable += walkable_count(BoardGen.generate(n, rng))
		print("\n==== %s%s｜棋盘 %d×%d，平均能走 %.1f 格：设 %d 盏，道具 %d 件（带沟 %d），绕路 %.2f；现在的曲线 gap %.2f%s ====" % [
			id_tag(job), job.name, p.width, p.height, float(walkable) / maxf(plays, 1), job.lamps, int(opt.items), int(opt.gates), float(opt.detour), float(opt.gap), note_of(job)])
		if not brief:
			print("第 1 局的棋盘：")
			print(BoardGen.deal_ascii(make_play(job, 0, rng).board, {}))
	if not job.get("override", {}).is_empty():
		print("改过的摆法：%s" % str(job.override))


## "别的办法"的任务在标题前面带上编号，show= 里要用它
func id_tag(job: Dictionary) -> String:
	return "" if not job.has("base") else "编号 %s｜" % job.id


func note_of(job: Dictionary) -> String:
	return "" if job.get("note", "") == "" else "｜%s" % job.get("note", "")


func walkable_count(board: Dictionary) -> int:
	var n := 0
	for k in board.cells:
		if board.cells[k] != BoardGen.BLOCKED: n += 1
	return n


## 摆 plays 局，每一局都让贪心机器人打一遍，记到 c 里
func scan_cell(job: Dictionary, gap: float) -> Cell:
	var c := Cell.new()
	c.gap = gap
	c.plays = plays
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	for i in plays:
		var made := make_play(job, i, rng)
		var board: Dictionary = made.board
		var opt: Dictionary = made.opt
		opt.gap = gap
		var d := BoardGen.deal(board, opt, rng)
		if d.is_empty():
			c.failed += 1
			if c.fail_seeds.size() < 8: c.fail_seeds.append(i)
			note_fail(c, BoardGen.last_fail, BoardGen._last_fail_detail)
			continue
		c.dealt += 1
		c.attempts += int(d.attempts)
		c.branches += int(d.branches)
		c.lamps += int(d.lamps)
		var js := jump_stats(board, d)
		c.route_steps += int(js.steps)
		c.tight += int(js.tight)
		c.blocked += int(js.blocked)
		# 核对：照着路线走必须一步不错就过
		var fsim := BoardSim.from_deal(board, d, MOVES, BoardGen.BASE_REACH, true)
		if not fsim.follow(d.route).won:
			c.follow_bad += 1
		# 随手玩
		var sim := BoardSim.from_deal(board, d, MOVES, BoardGen.BASE_REACH, true)
		var r := sim.run(STEP_LIMIT)
		c.missteps += int(r.missteps)
		if int(r.steps) >= STEP_LIMIT:
			c.over_limit += 1
		if r.won:
			c.won += 1
			if r.missteps == 0:
				c.perfect += 1
			elif c.sloppy_seeds.size() < 6:
				c.sloppy_seeds.append(i)
		else:
			c.lost_short += sim.need - sim.got
			if sim.got >= sim.need:
				c.lost_full += 1
				if portal_reachable(sim):
					c.fixed += 1
			if c.lost_seeds.size() < 6:
				c.lost_seeds.append(i)
	if job.kind == "campaign":
		c.fixed_text = fixed_text(job, gap, rng)
	c.msec = Time.get_ticks_msec() - t0
	return c


## 灯收齐以后，从机器人停下的地方走不走得进水车：水车开了以后踩空格不花步、连击也不变，能跳多远就一直是这么多，
## 所以只要沿着"每一跳都够得着"的格子一路换过去能碰到水车，人就走得进去（隔着一条河的，先走到河边、跳到对岸、再走过去）
func portal_reachable(sim: BoardSim) -> bool:
	var r: float = sim.reach() - BoardGen.REACH_MARGIN
	var landable: Array = []
	for k in sim.cells:
		if sim.cells[k] != BoardGen.BLOCKED: landable.append(k)
	var seen: Dictionary = {sim.pos: true}
	var queue: Array = [sim.pos]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n in landable:
			if seen.has(n) or BoardGen.dist(c, n) > r: continue
			if n == sim.portal: return true
			seen[n] = true
			queue.append(n)
	return false


## 巡夜里每关实际给玩家的是固定种子的那一局（同 test_boards.gd 的"固定的那一局"）：记贪心机器人打这一局的结果
func fixed_text(job: Dictionary, gap: float, rng: RandomNumberGenerator) -> String:
	rng.seed = CAMP_SEED + int(job.level) * 37
	var opt := current_opt(job)
	opt.merge(job.get("override", {}), true)
	opt.gap = gap
	var d := BoardGen.deal(job.board, opt, rng)
	if d.is_empty():
		return "摆不出"
	var sim := BoardSim.from_deal(job.board, d, MOVES, BoardGen.BASE_REACH, true)
	var r := sim.run(STEP_LIMIT)
	if r.won:
		return "赢·踩空%d" % int(r.missteps)
	if sim.got < sim.need:
		return "输·差%d盏" % (sim.need - sim.got)
	return "输·灯齐进不了水车·%s" % ("人能进" if portal_reachable(sim) else "人也进不了")


## 把路线从头走一遍，数一数有多少跳"贴着极限"（连击比路线上少两点就够不着）、
## 有多少跳"断了连击就够不着"（踩空一次、连击归零以后直接跳不过去）
func jump_stats(board: Dictionary, d: Dictionary) -> Dictionary:
	var rp: Dictionary = BoardGen.BASE_REACH
	var combo := 0.0
	var shoe := 0.0
	var prev: Vector2i = board.start
	var steps := 0
	var tight := 0
	var blocked := 0
	var route: Array = d.route
	var kinds: Array = d.kinds
	for i in route.size():
		var t: Vector2i = route[i]
		var dd := BoardGen.dist(prev, t)
		steps += 1
		if dd > BoardGen.reach_of(maxf(combo - 2.0, 0.0), shoe, 0.0, rp) - BoardGen.REACH_MARGIN:
			tight += 1
		if dd > BoardGen.reach_of(0.0, shoe, 0.0, rp) - BoardGen.REACH_MARGIN:
			blocked += 1
		match int(kinds[i]):
			BoardGen.Thing.LAMP, BoardGen.Thing.BIG: combo += 1.0
			BoardGen.Thing.LOTUS: combo = minf(combo + BoardGen.LOTUS_COMBO, float(rp.cap))
			BoardGen.Thing.SHOE: shoe += BoardGen.SHOE_REACH
		prev = t
	return {"steps": steps, "tight": tight, "blocked": blocked}


## 记下一局摆不出来：last_fail 形如"摆了 300 回：没处可去 ×287；走不通：第 3 格够不着：隔 2.50 格… ×13"，
## 按大的类别把各原因卡住的回数累加起来
func note_fail(c: Cell, msg: String, detail: String) -> void:
	var body := msg
	var cut := body.find("：")
	if cut >= 0: body = body.substr(cut + 1)
	for part in body.split("；", false):
		var at := part.rfind(" ×")
		if at < 0: continue
		var n := int(part.substr(at + 2).strip_edges())
		var key := short_reason(part.substr(0, at).strip_edges())
		c.fail_tries[key] = int(c.fail_tries.get(key, 0)) + n
		c.fail_total += n
	c.last_detail = detail


## "走不通：第 3 格够不着：隔 2.50 格，只能跳 2.30 格"带着具体数字，只留"走不通：够不着"这样的大类别
func short_reason(key: String) -> String:
	if not key.begins_with("走不通："): return key
	var tail := key.substr(4)
	if tail.begins_with("第 ") and tail.find("格") >= 0:
		tail = tail.substr(tail.find("格") + 3)
	var colon := tail.find("：")
	if colon >= 0: tail = tail.substr(0, colon)
	return "走不通：" + tail


## 这一档摆不出来的最多的原因，和它占卡住的总回数的比例
func top_fail(c: Cell) -> String:
	if c.fail_tries.is_empty(): return "-"
	var best := ""
	var best_n := 0
	for k in c.fail_tries:
		if int(c.fail_tries[k]) > best_n:
			best_n = int(c.fail_tries[k])
			best = k
	return "%s ×%d（%.0f%%）" % [best, best_n, 100.0 * best_n / maxf(c.fail_total, 1)]


func row_text(c: Cell) -> String:
	var v: Array = [
		"%.1f" % c.gap,
		"%d/%.1f" % [c.failed, c.share(c.failed, c.plays)],
		"%.1f" % c.share(c.won, c.dealt),
		"%.1f" % c.share(c.won + c.fixed, c.dealt),
		"%.1f" % c.share(c.perfect, c.dealt),
		"%.2f" % c.mean(c.missteps, c.dealt),
		"%.2f" % c.mean(c.branches, c.dealt),
		"%.1f" % c.mean(c.lamps, c.dealt),
		"%.1f" % c.mean(c.attempts, c.dealt),
		"%.1f" % c.share(c.tight, c.route_steps),
		"%.1f" % c.share(c.blocked, c.route_steps),
		"%.1f" % c.mean(c.lost_short, c.lost()),
		c.fixed_text,
		top_fail(c),
	]
	var parts: Array = []
	for i in COLS.size():
		parts.append(pad_left(str(v[i]), int(COLS[i][1])))
	parts.append(str(v[COLS.size()]))
	return "  ".join(parts)


## 一行下面值得多说的：哪几局摆不出来、卡在哪；灯收齐了却进不了水车的局有多少
func note_text(c: Cell, with_seeds: bool) -> String:
	var bits: Array[String] = []
	if c.failed > 0:
		bits.append("摆不出来的是第 %s 局（都从 1 数起）；最近一回长路线卡在：%s" % [seed_list(c.fail_seeds, "、"), c.last_detail])
	if c.lost_full > 0:
		bits.append("输的 %d 局里有 %d 局灯已收齐、只是机器人没走进水车（修正后算人能过的 %d 局；走满 %d 步来回踱步的 %d 局）" % [
			c.lost(), c.lost_full, c.fixed, STEP_LIMIT, c.over_limit])
	if c.over_limit > c.lost_full:
		bits.append("有 %d 局走满 %d 步还没结束" % [c.over_limit, STEP_LIMIT])
	if c.follow_bad > 0:
		bits.append("有 %d 局照着路线走却没能一步不错地过（机器人收尾时走不进水车，不是路线本身的问题）" % c.follow_bad)
	if with_seeds:
		if not c.lost_seeds.is_empty():
			bits.append("贪心打输的局：第 %s 局" % seed_list(c.lost_seeds, "、"))
		if not c.sloppy_seeds.is_empty():
			bits.append("踩空以后才过的局：第 %s 局" % seed_list(c.sloppy_seeds, "、"))
	if bits.is_empty(): return ""
	return "      · " + "；".join(bits)


## 局号都从 1 数起。第 N 局的种子：巡夜是 (7000 + 关序号 × 37) × 1000 + N − 1，长夜是 20261125 + n × 100003 + N − 1
func seed_list(list: Array, sep: String) -> String:
	var names: Array[String] = []
	for i in list:
		names.append("%d" % (int(i) + 1))
	return sep.join(names)


## 汇总成矩阵，一行一关（更）、一列一档 gap，制表符隔开，方便拿去算
func print_matrix(title: String, jobs: Array, all_cells: Array, kind: String, mode: String) -> void:
	print("\n==== 汇总｜%s ====" % title)
	var head := "编号\t关（更）"
	for g in gaps:
		head += "\t%.1f" % float(g)
	print(head)
	for j in jobs.size():
		if jobs[j].kind != kind: continue
		var line := "%s\t%s" % [jobs[j].id, jobs[j].name]
		for c in all_cells[j]:
			if c.dealt == 0 and mode != "fail":
				line += "\t-"
				continue
			match mode:
				"win": line += "\t%.1f" % c.share(c.won, c.dealt)
				"winfix": line += "\t%.1f" % c.share(c.won + c.fixed, c.dealt)
				"perfect": line += "\t%.1f" % c.share(c.perfect, c.dealt)
				"fail": line += "\t%d" % c.failed
				"missteps": line += "\t%.2f" % c.mean(c.missteps, c.dealt)
				"branches": line += "\t%.1f" % c.mean(c.branches, c.dealt)
		print(line)


## "别的办法"的汇总：一关一张表，一行一种改法，每格是「原始过关% → 修正过关%」
func print_variant_matrices(jobs: Array, all_cells: Array, mode: String) -> void:
	var what := "每一关在现在的摆法上一次只动一个数" if mode == "variants" else "把几个数一起改（长夜是道具件数 × 带沟件数的小网格）"
	print("\n#### 汇总｜别的办法：%s。每格是「原始过关%% → 修正过关%%」，括号里是摆不出来的局数 ####" % what)
	var order: Array = []
	var groups: Dictionary = {}
	for j in jobs.size():
		var base: String = str(jobs[j].get("base", jobs[j].id))
		if not groups.has(base):
			groups[base] = []
			order.append(base)
		groups[base].append(j)
	for base in order:
		print("\n==== %s ====" % jobs[groups[base][0]].name)
		var head := pad_right("改法", 28)
		for g in gaps:
			head += pad_left("gap %.1f" % float(g), 24)
		print(head)
		for j in groups[base]:
			var line := pad_right(str(jobs[j].get("note", "")), 28)
			for c in all_cells[j]:
				var cell := "-"
				if c.dealt > 0:
					cell = "%.1f → %.1f" % [c.share(c.won, c.dealt), c.share(c.won + c.fixed, c.dealt)]
				if c.failed > 0:
					cell += "（摆不出 %d）" % c.failed
				line += pad_left(cell, 24)
			print(line)


## 把某一局画出来，再看贪心机器人一步一步怎么走。spec 形如 c3:0.4:17（任务编号:gap:第几局，局号从 1 数起）
func show_deal(jobs: Array, spec: String) -> void:
	var parts := spec.split(":")
	if parts.size() != 3:
		print("show= 要写成 c3:0.4:17 这样（任务编号:gap:第几局）")
		return
	var job := {}
	for j in jobs:
		if j.id == parts[0]: job = j
	if job.is_empty():
		print("找不到任务 %s" % parts[0])
		return
	var no := int(parts[2])
	var rng := RandomNumberGenerator.new()
	var made := make_play(job, no - 1, rng)
	var board: Dictionary = made.board
	var opt: Dictionary = made.opt
	opt.gap = float(parts[1])
	var d := BoardGen.deal(board, opt, rng)
	print("\n==== %s｜%s，gap %.1f，第 %d 局（种子 %d）====" % [job.name, job.get("note", ""), opt.gap, no, rng.seed])
	print(BoardGen.deal_ascii(board, {}))
	if d.is_empty():
		print("这一局摆不出来：%s" % BoardGen.last_fail)
		print("最后一回卡在：%s" % BoardGen._last_fail_detail)
		return
	print(BoardGen.deal_ascii(board, d))
	print("路线（灯 %d 盏，岔路 %d 处，试了 %d 回）：%s" % [int(d.lamps), int(d.branches), int(d.attempts), str(d.route)])
	var js := jump_stats(board, d)
	print("共 %d 跳：贴着极限 %d 跳，断了连击就够不着 %d 跳" % [int(js.steps), int(js.tight), int(js.blocked)])
	print("贪心机器人：")
	var sim := BoardSim.from_deal(board, d, MOVES, BoardGen.BASE_REACH, true)
	var guard := 0
	while not sim.finished and guard < STEP_LIMIT:
		guard += 1
		var from := sim.pos
		var t := sim.next_move()
		if t == from:
			print("  第 %d 步：停在 %s 没处可去（连击 %.0f，能跳 %.2f 格，剩 %d 步，收到 %d/%d 盏）" % [
				guard, from, sim.combo, sim.reach(), sim.moves, sim.got, sim.need])
			break
		# 来回踱步的局只打出头 40 步和最后 10 步
		if guard > 40 and guard < STEP_LIMIT - 10:
			sim.land(t)
			continue
		var what := "踩空，斗笠挡掉（不花步、连击不变）" if sim.shields > 0 else "踩空，花一步、连击归零"
		if sim.things.has(t):
			what = "拿「%s」" % THING_NAMES[sim.things[t]]
		elif sim.step_free(t):
			what = "走空格，不花步"
		print("  第 %d 步：%s → %s（%.2f 格），%s；连击 %.0f，能跳 %.2f 格，剩 %d 步" % [
			guard, from, t, BoardGen.dist(from, t), what, sim.combo, sim.reach(), sim.moves])
		sim.land(t)
	print("  结果：%s；踩空 %d 次，共 %d 步，收到 %d/%d 盏" % ["过关" if sim.won else "没过", sim.missteps, sim.steps, sim.got, sim.need])
	if not sim.won and sim.got >= sim.need:
		print("  灯已收齐：%s" % ("人从这儿走得进水车（修正后算过）" if portal_reachable(sim) else "从这儿也够不着水车（人也进不了）"))


## 终端里一个字符占几列：汉字和全角标点占 2 列
func disp_width(s: String) -> int:
	var w := 0
	for ch in s:
		w += 2 if ch.unicode_at(0) >= 0x1100 else 1
	return w


func pad_left(s: String, width: int) -> String:
	return " ".repeat(maxi(width - disp_width(s), 0)) + s


func pad_right(s: String, width: int) -> String:
	return s + " ".repeat(maxi(width - disp_width(s), 0))

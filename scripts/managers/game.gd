extends Node

## 游戏模式：CAMPAIGN 是主线关卡（打完最后一张棋盘算通关），ENDLESS 是无尽模式（棋盘随机生成，比谁走得远）
enum GameMode { CAMPAIGN, ENDLESS }
var game_mode: GameMode = GameMode.CAMPAIGN

## 本机最好成绩。键是 "模式/难度id/角色id"（模式是 GameMode 的整数值），值是 {"score": 分数, "level": 到达的关数}。
## 难度是后来加的：旧存档里的键是 "模式/角色id"，读进来的时侯记到"中等"名下
var best_records: Dictionary = {}

var selected_character: CharacterResource
var characters: Array[CharacterResource]
var unlocked_characters: Array[CharacterResource]
var completed_runs: Dictionary
var save_path := "user://savegame.save"

## 新手教程：哪些提示已经看过了（键是提示的名字，值是 true）。记在存档里，每条只出现一次
var tutorial_seen: Dictionary = {}

## 被环境变量临时顶替的设置（SW_RULESET、SW_OPENING，自动测试用）在存档里原来记的值。这一局里它们是环境变量给的，
## 但 save() 写进存档的照旧是这里记的。不然这一局里只要有别的保存动作（记一条"提示看过了"、记一局成绩），
## 临时指定的值就被写进存档，之后不带环境变量的测试全在错的设置下跑
##（2026-11-26 整轮回归就因此在"非常困难"下跑了一回：蜡烛烧完、灯灭，过关流程的测试走不通）
var _kept: Dictionary = {}

## 难度四档：resources/rulesets/ 里每个文件一档。选了哪档记在存档里（记的是 id）
var rulesets: Array[Ruleset] = []
var ruleset: Ruleset
var ruleset_id := ""

## 开场动画：random 每次开机随机换一个（默认）；A / B / C / D 固定播一个；off 是不播
var opening := "random"
var opening_last := ""            # 随机的时侯上一次播的是哪个：不连着两次一样

var master_value := 1.0
var music_value := 1.0
var sfx_value := 1.0
var visuals_value := true

## 存档。难度和开场如果是被环境变量临时顶替的（SW_RULESET、SW_OPENING），写的是存档里原来记着的那个（见 _kept）
func save():
	var data = {
		"characters": unlocked_characters.map(func(a: CharacterResource): return a.id),
		"master_value": master_value,
		"music_value": music_value,
		"sfx_value": sfx_value,
		"visuals_value": visuals_value,
		"completed_runs": completed_runs,
		"best_records": best_records,
		"tutorial": tutorial_seen,
		"ruleset": _kept.get("ruleset", ruleset_id),
		"opening": _kept.get("opening", opening),
		"opening_last": opening_last
	}
	var save_file = FileAccess.open(save_path, FileAccess.WRITE)
	save_file.store_line(JSON.stringify(data))

func load():
	# 环境变量 SW_OPENING 临时指定开场动画（录预览视频用）。存档是标题页准备好了才读的，所以在这儿再压一遍，
	# 不然存档里记的那个会把它盖掉
	var forced := OS.get_environment("SW_OPENING")
	if not FileAccess.file_exists(save_path):
		unlocked_characters = characters.filter(func(a: CharacterResource): return not a.locked) 
		if forced != "":
			opening = forced
			_kept["opening"] = "random"
		load_rulesets()
		return
	var save_file = FileAccess.open("user://savegame.save", FileAccess.READ)
	var data = JSON.parse_string(save_file.get_as_text())
	unlocked_characters = characters.filter(func(a: CharacterResource): return not a.locked or data.characters.has(a.id)) 
	if data.has("master_value"): master_value = data.master_value
	if data.has("music_value"): music_value = data.music_value
	if data.has("sfx_value"): sfx_value = data.sfx_value
	if data.has("visuals_value"): visuals_value = data.visuals_value
	if data.has("completed_runs"): completed_runs = data.completed_runs
	if data.has("best_records"): best_records = data.best_records
	# 旧存档的记录键里没有难度：记到"中等"名下（它是原来唯一那套玩法的接替者）
	var old_keys: Array = []
	for key in best_records:
		if (key as String).split("/").size() == 2: old_keys.append(key)
	for key in old_keys:
		var parts: PackedStringArray = (key as String).split("/")
		var moved := "%s/normal/%s" % [parts[0], parts[1]]
		if not best_records.has(moved): best_records[moved] = best_records[key]
		best_records.erase(key)
	if data.has("tutorial"): tutorial_seen = data.tutorial
	if data.has("ruleset"): ruleset_id = str(data.ruleset)
	# 开场：存档里记的那个；被环境变量临时顶替的时侯这一局用它，存档里照旧记原来那个
	var saved_opening := str(data.opening) if data.has("opening") else "random"
	opening = forced if forced != "" else saved_opening
	if forced != "": _kept["opening"] = saved_opening
	if data.has("opening_last"): opening_last = str(data.opening_last)
	load_rulesets()
	loaded.emit()

## 把 resources/rulesets/ 里的难度都读进来，按文件名排。存档里记着上次选的那一档就还选它，不然用第一档。
## 一个文件都没读到（不该发生）就用代码里的默认值凑一套，游戏照样能玩
func load_rulesets() -> void:
	rulesets.clear()
	var names: Array[String] = []
	var dir := DirAccess.open("res://resources/rulesets")
	if dir:
		for f in dir.get_files():
			# 导出成包以后，没被别的资源引用的文本资源会被转成二进制的，目录里列出来的名字后面多一个 ".remap"
			#（编辑器里直接跑的时侯没有）。去掉它，按原来的路径读，引擎自己会找到转好的那一份
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"): names.append(f)
	names.sort()
	for f in names:
		var r := load("res://resources/rulesets/" + f) as Ruleset
		if r: rulesets.append(r)
	if rulesets.is_empty():
		var r := Ruleset.new()
		r.id = "normal"
		r.title = "中等"
		rulesets.append(r)
	# 旧存档里记的方案（灯谱、流水、疾走、万灯、旧灯）现在没有了：都落到"中等"上，它是原来灯谱的接替者。
	# "hard" 不在里面：旧的长明和新的困难用的是同一个 id，选过它的人留在困难档，本来就是对的位置
	if ruleset_id in ["", "dealt", "flow", "rush", "party", "legacy"]: ruleset_id = "normal"
	# 环境变量 SW_RULESET 临时指定一档（自动测试用）：这一局用它，存档里照旧记原来那一档（见 _kept）
	var forced_ruleset := OS.get_environment("SW_RULESET")
	if forced_ruleset != "":
		_kept["ruleset"] = ruleset_id
		ruleset_id = forced_ruleset
	ruleset = rulesets[0]
	for r in rulesets:
		if r.id == ruleset_id:
			ruleset = r
			break

## 选一个开场动画（记进存档）。测试里用环境变量临时指定的，不写存档
func select_opening(key: String) -> void:
	opening = key
	if OS.get_environment("SW_OPENING") != "": return
	save()

## 随机开场抽一个：last 是上一次播的，这次不再抽它
static func pick_opening(last: String) -> String:
	var keys: Array = Opening.NAMES.keys()
	keys.erase(last)
	return str(keys.pick_random())

## 这次开机播哪个：记下它，下次随机不再抽到同一个
func roll_opening() -> String:
	opening_last = pick_opening(opening_last)
	save()
	return opening_last

## 选一档难度（记进存档）。只对之后开的局生效
func select_ruleset(r: Ruleset) -> void:
	if r == null: return
	ruleset = r
	ruleset_id = r.id
	if OS.get_environment("SW_RULESET") != "": return      # 测试里临时指定的，不写存档
	save()

## 记下某一条教程提示已经看过（并写进存档）
func tutorial_mark(id: String):
	tutorial_seen[id] = true
	save()

## 记下一局的成绩：分数更高，或者分数相同但走得更远，才算刷新纪录。返回这一局的记录键。
## 每个模式、每一档难度、每个角色各记一条：简单档的分数不该拿去跟非常困难档的比。
## tier 是记在哪一档名下（不给就是现在这一档）：半路调过难度的一局，main.gd 会把它记在用过的最低一档名下
func record_run(character: CharacterResource, score: int, level: int, tier: Ruleset = null) -> String:
	var t: Ruleset = tier if tier != null else ruleset
	var key := "%d/%s/%s" % [game_mode, t.id if t != null else "normal", character.id]
	var best: Dictionary = best_records.get(key, {"score": 0, "level": 0})
	if score > int(best.score) or (score == int(best.score) and level > int(best.level)):
		best_records[key] = {"score": score, "level": level}
		save()
	return key
	
func unlock_character(character: CharacterResource):
	if not unlocked_characters.has(character): unlocked_characters.append(character)
	save()

func unlock_character_by_id(id: String):
	var character = get_character_resource_by_id(id)
	if not character: return;
	unlock_character(character)
	
func get_character_resource_by_id(id: String):
	var matching_characters = characters.filter(func(a): return a.id == id)
	if not matching_characters.size(): return;
	return matching_characters[0]
	
func clear():
	unlocked_characters.clear()
	completed_runs.clear()
	tutorial_seen = {}          # 进度清空了，教程也从头来
	save()

func get_locked_characters() -> Array[CharacterResource]:
	return characters.filter(func(c): return not unlocked_characters.has(c))

func complete_run(character: CharacterResource):
	completed_runs[character.id] = true
	save()
	
func has_completed_run(character: CharacterResource):
	return completed_runs.has(character.id) and completed_runs[character.id]
	
signal loaded

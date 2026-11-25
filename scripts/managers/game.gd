extends Node

## 游戏模式：CAMPAIGN 是主线关卡（打完最后一张棋盘算通关），ENDLESS 是无尽模式（棋盘随机生成，比谁走得远）
enum GameMode { CAMPAIGN, ENDLESS }
var game_mode: GameMode = GameMode.CAMPAIGN

## 本机最好成绩。键是 "模式/角色id"（模式是 GameMode 的整数值），值是 {"score": 分数, "level": 到达的关数}
var best_records: Dictionary = {}

var selected_character: CharacterResource
var characters: Array[CharacterResource]
var unlocked_characters: Array[CharacterResource]
var completed_runs: Dictionary
var save_path := "user://savegame.save"

## 新手教程：哪些提示已经看过了（键是提示的名字，值是 true）。记在存档里，每条只出现一次
var tutorial_seen: Dictionary = {}

## 玩法方案：resources/rulesets/ 里每个文件一套。选了哪套记在存档里（记的是 id）
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
		"ruleset": ruleset_id,
		"opening": opening,
		"opening_last": opening_last
	}
	var save_file = FileAccess.open(save_path, FileAccess.WRITE)
	save_file.store_line(JSON.stringify(data))

func load():
	# 环境变量 SW_OPENING 临时指定开场动画（录预览视频用）。存档是标题页准备好了才读的，所以在这儿再压一遍，
	# 不然存档里记的那个会把它盖掉
	var forced := OS.get_environment("SW_OPENING")
	if forced != "": opening = forced
	if not FileAccess.file_exists(save_path):
		unlocked_characters = characters.filter(func(a: CharacterResource): return not a.locked) 
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
	if data.has("tutorial"): tutorial_seen = data.tutorial
	if data.has("ruleset"): ruleset_id = str(data.ruleset)
	if data.has("opening") and forced == "": opening = str(data.opening)
	if data.has("opening_last"): opening_last = str(data.opening_last)
	load_rulesets()
	loaded.emit()

## 把 resources/rulesets/ 里的方案都读进来，按文件名排。存档里记着上次选的那套就还选它，不然用第一套。
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
		r.id = "dealt"
		r.title = "灯谱"
		rulesets.append(r)
	# 环境变量 SW_RULESET 临时指定一套（自动测试用），不写存档
	if OS.get_environment("SW_RULESET") != "": ruleset_id = OS.get_environment("SW_RULESET")
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

## 选一套方案（记进存档）。只对之后开的局生效
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
func record_run(character: CharacterResource, score: int, level: int) -> String:
	var key := "%d/%s" % [game_mode, character.id]
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

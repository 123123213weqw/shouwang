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
		"tutorial": tutorial_seen
	}
	var save_file = FileAccess.open(save_path, FileAccess.WRITE)
	save_file.store_line(JSON.stringify(data))

func load():
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
	loaded.emit()

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

class_name LeaderBoardContainerControl extends Control
## 成绩列表。原来会把成绩上传到原作者的服务器、再拉取全球排行榜；
## 这是个独立的新游戏，不再联网，只显示保存在本机的最好成绩（每个模式、每个角色各一条）。
const LEADERBOARD_CONTROL = preload("res://scenes/uis/leaderboard_control.tscn")
@onready var v_box_container: VBoxContainer = $VBoxContainer
@onready var loading_label: Label = $LoadingLabel
@onready var no_response_label: Label = $NoResponse

var scores: Array[LeaderboardControl]
## 刚打完的那一局的记录键，用来在列表里标出这一局
var current_key := ""

func _ready() -> void:
	v_box_container.set_visible(false)

func update():
	for child in v_box_container.get_children(): child.queue_free()
	scores.clear()
	loading_label.set_visible(false)

	# 每条记录的键是 "模式/角色id"
	var rows := []
	for key in Game.best_records:
		var parts := (key as String).split("/")
		if parts.size() != 2: continue
		var character: CharacterResource = Game.get_character_resource_by_id(parts[1])
		if not character: continue
		var rec: Dictionary = Game.best_records[key]
		rows.append({
			"key": key, "mode": int(parts[0]), "score": int(rec["score"]), "level": int(rec["level"]),
			"character": character,
		})
	# 主线在前、无尽在后；同一个模式里分数高的在前
	rows.sort_custom(func(a, b):
		if a.mode != b.mode: return a.mode < b.mode
		return a.score > b.score
	)

	no_response_label.set_visible(rows.is_empty())
	v_box_container.set_visible(not rows.is_empty())
	if rows.is_empty(): return

	var rank := 0
	var last_mode := -1
	for row in rows:
		if row.mode != last_mode:
			last_mode = row.mode
			rank = 1
		else:
			rank += 1
		var new_score = LEADERBOARD_CONTROL.instantiate() as LeaderboardControl
		v_box_container.add_child(new_score)
		new_score.load_character(row.character)
		new_score.score_label.text = str(row.score)
		new_score.name_label.text = "长夜" if row.mode == Game.GameMode.ENDLESS else "巡夜"
		new_score.rank_label.text = str("#", rank)
		new_score.level_label.text = str("第 ", row.level, " 更" if row.mode == Game.GameMode.ENDLESS else " 关")
		new_score.background.set_visible(rank % 2 == 0)
		new_score.run_id = 1 if row.key == current_key else 0
		scores.append(new_score)

func set_current(key):
	current_key = key
	for new_score in scores:
		new_score.is_current = new_score.run_id == 1

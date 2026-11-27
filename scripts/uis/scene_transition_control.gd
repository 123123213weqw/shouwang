class_name SceneTransitionControl extends CanvasLayer
## 换关、换场景时把画面盖住、再掀开：main.load_level 和 SceneManager.load_scene_progress 调它。
## 平时是随机的：每一趟从 RANDOM_POOL 里抽一种，不连着两趟一样。池里是原来那一套（tiles，一层石砖贴图的着色器，
## alpha 从 0 到 1 再回去，就是下面的 TextureRect 和 AnimationPlayer）和 scripts/uis/transitions/ 里的几种（接口见 transition_style.gd）。
## 要固定一种：环境变量 SW_TRANSITION=<样式>（random 是随机），或者在游戏里 call pad_adapter.gd debug_transition <样式>。
## 每一趟都量：盖住、掀开各用了多久，中间最长的一帧有多长（report）。怎么加一种、怎么录片子见 docs/transitions.md。
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var tiles: TextureRect = $TextureRect

const STYLES := ["tiles", "ripple", "lanterns", "steps", "wheel", "ink"]     # 有哪几种：tiles 是原来那一套；别的对应 scripts/uis/transitions/transition_<名字>.gd
const RANDOM := "random"
const RANDOM_POOL := ["lanterns", "steps", "wheel", "ink", "tiles"]          # 随机的那一池。涟漪开合（ripple）不进随机，要看得单独指定
const STYLE_DIR := "res://scripts/uis/transitions/"
const HITCH_MS := 25.0        # 过渡里最长的一帧过了这么多毫秒，就算卡了一下（服务器上平时一帧 10 毫秒上下）
const INK := Color(0.04, 0.06, 0.07)

var is_opened: bool = true    ## 画面是不是盖着的（或者正在盖）。开机的时候是盖着的
var style_id := RANDOM        ## 现在是随机（RANDOM）还是固定的一种
var style: TransitionStyle    ## 这一趟用的那一种；用 tiles 的时侯是空，走原来那套动画
var records: Array = []       ## 最近几趟量出来的数，最新的一趟在最后（每趟一个 Dictionary，见 report）

var _styles: Dictionary = {}  # 建好的样式：名字 → TransitionStyle。开机就把要用的都建好、预热好，换关途中不现建（现建要加载、编译，会卡一下）
var _random := false          # 现在是不是随机
var _pick := "tiles"          # 这一趟用的是哪一种（随机的时侯是抽到的那一种）
var _last_pick := ""          # 上一趟抽到的是哪一种：不连着两趟一样
var _busy := false            # 正在盖或者正在掀。这中间又有谁来盖、来掀，不理
var _warm_done := true        # 样式预热完了没有。开机掀幕要等它：预热会把节点藏起来，掀幕要是先开始了，会被它拦腰截断
var _phase := ""              # 正在量哪一段：cover 盖住、load 盖住到掀开之间、reveal 掀开
var _mark := {}               # 这一段开始的那一刻、过了几帧、最长的一帧
var _current := {}            # 这一趟的样式和几段

func _ready() -> void:
	set_process(false)
	set_style(OS.get_environment("SW_TRANSITION"))
	if _random:
		# 开机掀幕也算一趟：现在就抽好，免得头几帧画的是石砖墙、掀幕的却是别的（闪一下）
		_use(_draw())

## 固定一种，或者改成随机（RANDOM，不写也是它）。tiles 是原来那一套；别的名字到 scripts/uis/transitions/ 里找
## transition_<名字>.gd，找不到就还是用 tiles。返回最后用的是哪一种。正在过渡的时侯不换（样式正做着事）
func set_style(id: String) -> String:
	if id == "": id = RANDOM
	if _busy: return style_id
	_random = id == RANDOM
	var warm: Array = []               # 这回要预热的样式
	if _random:
		for name in RANDOM_POOL:
			if name != "tiles" and _build(name) != null: warm.append(_styles[name])
	else:
		if id != "tiles" and _build(id) == null:
			push_warning("没有「%s」这种过渡（%s 里没有），还是用原来的石砖墙" % [id, STYLE_DIR])
			id = "tiles"
		if id != "tiles": warm.append(_styles[id])
		_use(id)
	style_id = id
	if not warm.is_empty():
		_warm_done = false
		_warm_up.call_deferred(warm)
	return id

## 建一种样式（建过就直接给）。它的节点是先藏着的
func _build(id: String) -> TransitionStyle:
	if _styles.has(id): return _styles[id]
	var path := STYLE_DIR + "transition_" + id + ".gd"
	var script: Script = load(path) if ResourceLoader.exists(path) else null
	if script == null: return null
	var s: TransitionStyle = script.new()
	s.ctl = self
	s.build()
	_styles[id] = s
	return s

## 这儿已经建好的样式里，哪些是有的（排查、调试用）
func built() -> Array:
	return _styles.keys()

## 现在是随机（池里是哪几种）还是固定的一种
func describe() -> String:
	if not _random: return "「%s」" % style_id
	return "随机（%s）" % "、".join(RANDOM_POOL)

## 从一池里抽一种，不和上一趟一样。池里只有建不出来的样式的话就用 tiles
func _draw() -> String:
	var pool: Array = []
	for name in RANDOM_POOL:
		if name == "tiles" or _styles.has(name): pool.append(name)
	if pool.is_empty(): return "tiles"
	if pool.size() == 1 or _last_pick == "":
		_last_pick = pool[0] if pool.size() == 1 else pool[randi() % pool.size()]
		return _last_pick
	var pick: String = pool[randi() % pool.size()]
	while pick == _last_pick:
		pick = pool[randi() % pool.size()]
	_last_pick = pick
	return pick

## 这一趟用哪一种：style 和石砖墙那一层跟着换
func _use(pick: String) -> void:
	_pick = pick
	style = null if pick == "tiles" else _styles.get(pick)
	tiles.visible = pick == "tiles"

## 把这几种一起预热：各自等 3 帧、露 2 帧、再藏，同时进行。反正在开机的黑幕底下
func _warm_up(styles: Array) -> void:
	for s: TransitionStyle in styles:
		s.warm_up()
	for i in 6:
		await get_tree().process_frame
	_warm_done = true

## 等到开机的掀幕可以开始（样式预热完）。开机的黑幕撤掉之前要先等它：黑幕先撤、掀幕后开始，标题页会裸露几帧
func wait_ready() -> void:
	while not _warm_done:
		await get_tree().process_frame

## 盖住。ctx 里放这一趟的说明（见 transition_style.gd），盖完了才返回。已经盖着的时侯什么都不做
func open(ctx: Dictionary = {}) -> void:
	if is_opened or _busy: return
	_busy = true
	if _random: _use(_draw())         # 每一趟抽一回，抽在盖住以前：掀开的时侯用的还是盖住的这一种
	if style == null and not visible:
		# 石砖墙那一层的 alpha 平时停在"掀开完了"的 0 上；可开机的掀幕要是抽给了别的样式，它就还停在 1 上，
		# 头一回抽到它的时侯会先整墙闪一帧、再从 0 淡进来。所以先归零
		(tiles.material as ShaderMaterial).set_shader_parameter("alpha", 0.0)
	set_visible(true)
	var full := _context(ctx, false)
	_current = {"style": _pick, "mode": full.mode, "fast": full.fast, "from_color": full.color_from}
	# 录片子的时候按这两行对齐（record_transition_v100.sh）：过渡开始、过渡结束
	print("TRANSITION_BEGIN %d %s %s" % [Time.get_ticks_usec(), _pick, full.mode])
	_begin("cover")
	if style != null: await style.cover(full)
	else:
		animation_player.play("open")
		await animation_player.animation_finished
	_end("cover")
	is_opened = true
	_busy = false
	_begin("load")            # 盖住到掀开之间：调用的人在这中间换棋盘、摆河灯

## 掀开。ctx 里放这一趟的说明，掀完了才返回。没盖着的时侯什么都不做
func close(ctx: Dictionary = {}) -> void:
	if not is_opened or _busy: return
	_busy = true
	# 开机掀幕等样式预热完再掀（反正在开机的黑幕底下，看不出来）
	while not _warm_done:
		await get_tree().process_frame
	_end("load")
	var full := _context(ctx, true)
	if _current.is_empty():
		_current = {"style": _pick, "mode": "boot", "fast": full.fast}        # 开机第一幕：没盖过，直接掀
	_begin("reveal")
	if style != null: await style.reveal(full)
	else:
		animation_player.play("close")
		await animation_player.animation_finished
	_end("reveal")
	print("TRANSITION_END %d %s %s" % [Time.get_ticks_usec(), _pick, _current.get("mode", "")])
	set_visible(false)
	is_opened = false
	_busy = false
	records.append(_current)
	if records.size() > 12: records.pop_front()

## 调用的人给的说明，补上公共的那几样：谁触发的（from，平时是主角这会儿站的地方）、要去的这一关的底色和离开的那一关的底色、main
func _context(ctx: Dictionary, revealing: bool) -> Dictionary:
	var out := ctx.duplicate()
	var main := get_node_or_null("/root/Main") as Main
	out["mode"] = str(ctx.get("mode", "level"))
	out["fast"] = bool(ctx.get("fast", false))
	out["main"] = main
	var where: Variant = null
	if main != null and is_instance_valid(main.character): where = main.character.global_position
	if not out.has("from"): out["from"] = where
	if revealing and not out.has("to"): out["to"] = where
	var level: Variant = ctx.get("level", main.current_level if main != null else null)
	out["color"] = level.base_color if level != null else INK
	if not out.has("color_from"):      # 换关的时侯 main 给了（离开的那一关的底色）；没给就按现在这一关算
		out["color_from"] = _current.get("from_color", INK) if revealing else (main.current_level.base_color if main != null and main.current_level != null else INK)
	if level != null and not out.has("name"): out["name"] = level.level_name
	return out

func _begin(phase: String) -> void:
	_phase = phase
	_mark = {"t": Time.get_ticks_usec(), "frames": 0, "max_us": 0}
	_current[phase] = _mark
	set_process(true)

func _process(_delta: float) -> void:
	if _phase == "": return
	var now := Time.get_ticks_usec()
	_mark.frames = int(_mark.frames) + 1
	if _mark.has("last"): _mark.max_us = maxi(int(_mark.max_us), now - int(_mark.last))
	_mark.last = now

func _end(phase: String) -> void:          # 参数别叫 _phase：会和成员变量重名，把它遮住
	if _phase != phase: return
	_mark.us = (int(_mark.last) if _mark.has("last") else int(_mark.t)) - int(_mark.t)
	_phase = ""
	set_process(false)

## 最近一趟量出来的数，一行。back 是往回数第几趟（0 是最新的一趟）。
## 只判换关的那一些：盖住或者掀开里最长的一帧过了 HITCH_MS 毫秒，或者长短离谱（见 _verdict），就报"没过"。
## 开机掀幕和标题页↔游戏换场景的那两趟不判（新场景头几帧本来就重）；头一趟换关也不判——着色器就算预热过，
## 头一趟也常有点别的头一回的开销；要判就看第二趟
func report(back := 0) -> String:
	if records.is_empty(): return "RESULT 过渡：没过，还没放过一次"
	var r: Dictionary = records[records.size() - 1 - clampi(back, 0, records.size() - 1)]
	var mode := str(r.get("mode", "level"))
	var kind: String = {"boot": "开机掀幕", "scene": "换场景"}.get(mode, "换关")
	var text := "样式 %s，%s；%s" % [r.style, kind, _phases(r)]
	if mode == "boot" or mode == "scene": return "RESULT 过渡：通过（%s；这一种不判）" % text
	if _level_trips(r) < 2: return "RESULT 过渡：通过（%s；头一趟，不判）" % text
	var bad := _verdict(r)
	if bad != "": return "RESULT 过渡：没过（%s；%s）" % [text, bad]
	return "RESULT 过渡：通过（%s）" % text

## 这几段各多久、最长的一帧多长。没量过的那一段（开机掀幕没有盖住……）不写
func _phases(r: Dictionary) -> String:
	var parts: Array[String] = []
	if r.has("cover"): parts.append("盖住 %.2f 秒，最长一帧 %.1f 毫秒" % [_secs(r.cover), _ms(r.cover)])
	if r.has("load"): parts.append("中间 %.2f 秒" % _secs(r.load))
	if r.has("reveal"): parts.append("掀开 %.2f 秒，最长一帧 %.1f 毫秒" % [_secs(r.reveal), _ms(r.reveal)])
	return "；".join(parts)

## 这一趟哪儿不对；没问题返回空字符串。换关换得快的局（fast）每一段最多 0.9 秒，别的局 0.25 到 1.6 秒
func _verdict(r: Dictionary) -> String:
	var fast := bool(r.get("fast", false))
	var top := 0.9 if fast else 1.6
	var bad: Array[String] = []
	for phase in ["cover", "reveal"]:
		if not r.has(phase): continue
		var who := "盖住" if phase == "cover" else "掀开"
		if _ms(r[phase]) > HITCH_MS: bad.append("%s的时候卡了一下（最长一帧 %.1f 毫秒）" % [who, _ms(r[phase])])
		if _secs(r[phase]) > top: bad.append("%s得太慢（%.2f 秒）" % [who, _secs(r[phase])])
		if _secs(r[phase]) < 0.25: bad.append("%s得太快（%.2f 秒）" % [who, _secs(r[phase])])
	return "；".join(bad)

## 到 up_to 这一趟为止（算上它）换过几趟关（开机掀幕、换场景的那种不算）
func _level_trips(up_to: Dictionary) -> int:
	var n := 0
	for r: Dictionary in records:
		if str(r.get("mode", "level")) == "level": n += 1
		if is_same(r, up_to): break
	return n

func _secs(mark: Dictionary) -> float:
	return float(mark.get("us", 0)) / 1000000.0 if mark != null else 0.0

func _ms(mark: Dictionary) -> float:
	return float(mark.get("max_us", 0)) / 1000.0 if mark != null else 0.0

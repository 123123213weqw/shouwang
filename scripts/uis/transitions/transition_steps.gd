extends TransitionStyle
## 石阶沉浮（docs/transitions.md 五种样式里的第 3 种）。别的样式往屏幕上贴一层，这一种不贴，动的是棋盘上的石阶：
##   盖住  石阶从水车那一格往外一圈一圈沉进水里，河灯、道具跟着自己那一块走；别处都沉完了，主角脚下那一块才带着主角和水车沉下去。
##         最后"潜进水里"：一层暗幕压上来盖严。调用的人（main.load_level）等盖严了才换棋盘，换棋盘那一帧就藏在暗幕底下。
##   中间  暗幕一直盖严。新棋盘一搭出来就把它按在水底（摆河灯是一件隔一帧落下的，那几帧新棋盘已经在树上）。
##   掀开  暗幕退开（浮上来），新棋盘的石阶从主角落脚的那一格往外一圈一圈浮出水面，带一点过冲；河灯、主角跟着自己那一块上来。
##
## 石阶是逐块挪 Tile 节点：格子上面的灯、站在上面的人、它自己的模型都挂在这一块上，挪节点最直接。Tile、Character
## 自己的 _process 每一帧会把高度拉回原处，所以挪它们的这只手必须排在它们后面：Driver 是个真节点，process_priority
## 比它们都大，每帧最后动一次。过渡做完，每一块石阶、每一盏灯、主角都回到载入时记下的那个高度，这里不再碰它们。

const INK := Color(0.04, 0.06, 0.07)     # 和 SceneTransitionControl.INK 是同一个墨色：没有关卡底色的时侯暗幕用它

# ------------------------------------------------------------------ 数都在这儿调
const COVER_SECS := 0.58          # 平时的局盖住多久（规矩是 0.35 到 0.7）
const REVEAL_SECS := 0.62         # 平时的局掀开多久（规矩是 0.4 到 0.9）
const COVER_FAST := 0.28          # 长夜、轮战的局：各 0.2 到 0.35
const REVEAL_FAST := 0.30
const SINK_DEPTH := 1.75          # 沉多深。水面在 y = -1.26，石阶的台面在 0 到 0.25：沉到底后台面在 -1.5 到 -1.75，离水面还有一段
const GHOST_DEPTH := 4.0          # 旧棋盘上的对手（脚下已经没有石阶了）按到多深
const DROP_SECS := 0.03           # 每一块沉下去用多久（带一点加速：越落越快）
const HERO_DROP_SECS := 0.11      # 主角脚下那一块：带着人和水车，沉得慢一点，看得出是一块大石头落下去
const RISE_SECS := 0.30           # 每一块浮上来用多久（平时的局）：阻尼弹簧，冲过头的量由弹簧自己给
const SPRING_K := 6.0             # 弹簧阻得多快（按浮上来的进度算）：到头的时侯已经停稳
const SPRING_W := TAU             # 弹簧的快慢：整个浮上来的过程里来回一次（过冲一回，回来就停）
const WAVE_GAP_MIN := 0.035       # 一圈和一圈之间隔多久。大棋盘圈多就挤一挤（换关换得快的局挤得更紧），小棋盘就慢一点
const WAVE_GAP_MAX := 0.11
const VEIL_IN := 0.42             # 盖住的最后这么大一段（占盖住的时长）暗幕压上来
const VEIL_OUT := 0.36            # 掀开的开头这么一段暗幕退开

var veil: TextureRect             # "潜进水里"的那层暗幕，铺满画面、压在所有界面上（在"还没开始"的状态下整张透明）
var driver: Driver                # 每帧最后动石阶的那只手

enum Phase { IDLE, COVER, MIDDLE, REVEAL }
var _phase: int = Phase.IDLE
var _clock := 0.0                 # 这一段过了几秒
var _stones: Array[Stone] = []    # 这一趟手里拿着的石阶
var _hero: Stone                  # 主角脚下那一块（盖住时最后沉，掀开时最先浮）
var _riders: Array[Rider] = []    # 站在石阶上的角色（主角、对战里的对手）和它脚下那一块
var _total := 0.0                 # 这一段一共多长
var _rise := 0.30                 # 这一趟每块石阶浮多久（换关换得快的局短一些）
var _veil_from := 0.0             # 暗幕从第几秒开始压上来 / 退开
var _veil_to := 0.0
var _veil := 0.0                  # 暗幕现在有多厚（最后一次写进着色器的数。不从材质里读回来：读回来的是_variant，空着的时侯不是数）
var _last_us := 0                 # 量帧时间：上一帧这只手动的时候
var _frames: Dictionary = {}      # 最近这一趟每一段最长的一帧（微秒）：cover、load、reveal

## 每帧最后动石阶的那只手。TransitionStyle 自己不是节点，没有 _process
class Driver extends Node:
	var tick := Callable()         # 样式的 _tick
	func _process(delta: float) -> void:
		if tick.is_valid(): tick.call(delta)

	## 排查用（call transition_steps.gd debug_last）：最近一趟量出来的数。中间那一段最长的一帧 SceneTransitionControl 不报，这里报
	func debug_last() -> String:
		return tick.get_object().debug_last()

## 一块石阶在过渡里的状态
class Stone:
	var tile: Tile                 # 沉浮的这一块
	var rest := 0.0                # 平时停在多高：过冲、回落都以它为准，做完也回到它
	var from := 0.0                # 从多高开始动
	var at := 0.0                  # 第几秒开始动
	var secs := 0.0                # 动多久
	var ring := 0                  # 离中心第几圈（1 是紧挨着的那一圈）
	var done := false              # 沉到底 / 浮到位了没有（那一刻河面上荡开一圈）

## 站在石阶上的角色和它脚下那一块。stone 是空的（脚下那一块已经收走了）：让它一直待在水底下
class Rider:
	var node: Node3D
	var stone: Stone

# ------------------------------------------------------------------ 接口

func build() -> void:
	veil = add(full_rect(shader("steps")), true)
	(veil.material as ShaderMaterial).set_shader_parameter("noise_tex", preload("res://assets/sprites/FlowMap.png"))
	veil.visible = false          # 预热是外面帮着做的；平时藏着，盖的时候自己设回可见
	driver = Driver.new()
	driver.name = "StepsDriver"
	driver.process_priority = 100        # 排在所有格子、角色、对战的玩法后面：它们每一帧都会把自己的高度写一遍，这里随后改写
	driver.tick = _tick
	add(driver)
	driver.set_process(false)

func cover(ctx: Dictionary) -> void:
	_frames = {}
	_last_us = 0
	_clock = 0.0
	_phase = Phase.COVER
	_total = duration(ctx, COVER_SECS, COVER_FAST)
	_set_veil_tint(ctx)
	_set_veil_flow(-1.0)
	_fit_veil()
	veil.visible = true
	_take_old_board(ctx)
	# 暗幕：有旧棋盘的时侯等石阶沉得差不多了再压上来；没有旧棋盘（从标题页进游戏）就是一路暗下去
	_veil_from = _total * (1.0 - VEIL_IN) if not _stones.is_empty() else 0.0
	_veil_to = _total * 0.94      # 盖严以后留几帧纯暗的：换棋盘那一帧的长短看不出来
	driver.set_process(true)
	while _phase == Phase.COVER:
		await ctl.get_tree().process_frame

func reveal(ctx: Dictionary) -> void:
	_clock = 0.0
	_phase = Phase.REVEAL
	_total = duration(ctx, REVEAL_SECS, REVEAL_FAST)
	_rise = RISE_SECS * _total / REVEAL_SECS
	_set_veil_tint(ctx)
	_set_veil_flow(1.0)
	_fit_veil()
	# 一进来就把新棋盘按在水底：和调用的人在同一帧里、渲染之前。不然会先闪一帧摆好的棋盘
	_take_new_board(ctx)
	if _stones.is_empty() and not _veil_is_up():
		veil.visible = false       # 开机掀幕：没盖过，画面上也没有石阶，什么都不用做
		_phase = Phase.IDLE
		return
	_veil_from = 0.0
	_veil_to = _total * VEIL_OUT if not _stones.is_empty() else _total * 0.8
	driver.set_process(true)
	while _phase == Phase.REVEAL:
		await ctl.get_tree().process_frame
	_give_back()

## 换样式的时侯：先把借走的东西都还回去（万一正做到一半），再让基类收走节点
func dispose() -> void:
	driver.set_process(false)
	_give_back()
	super()

# ------------------------------------------------------------------ 每帧

func _tick(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us != 0:
		var key := "load" if _phase == Phase.MIDDLE else ("cover" if _phase == Phase.COVER else "reveal")
		_frames[key] = maxi(int(_frames.get(key, 0)), now - _last_us)
	_last_us = now
	if _phase == Phase.IDLE:
		driver.set_process(false)
		return
	_clock += delta
	match _phase:
		Phase.COVER:
			_tick_cover()
			if _clock >= _total: _to_middle()
		Phase.MIDDLE:
			_tick_middle()
		Phase.REVEAL:
			_tick_reveal()
			if _clock >= _total:
				_phase = Phase.IDLE
				_last_us = 0

func _tick_cover() -> void:
	for s in _stones:
		if not is_instance_valid(s.tile): continue        # 场景换了（回标题页）：旧棋盘已经收走了
		var p := clampf((_clock - s.at) / s.secs, 0.0, 1.0)
		# 越落越快：开头几乎不动，末了直落下去
		_set_stone_y(s, lerpf(s.from, s.rest - SINK_DEPTH, p * p * (0.55 + 0.45 * p)))
		if p >= 1.0 and not s.done:
			s.done = true
			_ripple(s, 1.0 if s == _hero else 0.5)
	_set_veil(_veil_amount())

func _tick_middle() -> void:
	# 摆河灯是一件隔一帧落下的：每一帧都看一眼树上有没有新来的石阶，有就按到水底
	var main := ctl.get_node_or_null("/root/Main") as Main
	if main != null and main.grid != null and not main.grid.tiles.is_empty(): _hold_board(main)
	_keep_under()

func _tick_reveal() -> void:
	for s in _stones:
		if not is_instance_valid(s.tile): continue
		var u := clampf((_clock - s.at) / s.secs, 0.0, 1.0)
		_set_stone_y(s, s.rest - (s.rest - s.from) * exp(-SPRING_K * u) * cos(SPRING_W * u))
		if u >= 1.0 and not s.done:
			s.done = true
			_ripple(s, 1.0 if s == _hero else 0.5)
	_set_veil(_veil_amount())

## 暗幕这会儿该有多厚（0 看不见，1 盖严）：按时间从压上来 / 退开的那一段里算
func _veil_amount() -> float:
	return clampf((_clock - _veil_from) / maxf(_veil_to - _veil_from, 0.001), 0.0, 1.0)

## 把暗幕的厚度写进着色器。自己记一份：不从材质里读回来（读回来的是_variant，空着的时侯不是数）
func _set_veil(amount: float) -> void:
	_veil = amount
	veil.material.set("shader_parameter/depth", amount)

func _veil_is_up() -> bool:
	return _veil > 0.0

func _set_veil_tint(ctx: Dictionary) -> void:
	# 水底的墨色里透一点要去的这一关的底色：换了一关，暗幕的颜色也不一样
	veil.material.set("shader_parameter/tint", Color(ctx.get("color", INK)).darkened(0.55))

func _set_veil_flow(flow: float) -> void:
	veil.material.set("shader_parameter/flow", flow)

## 盖严了。旧棋盘交还给调用的人去收（这里不再碰它），后面那几帧只管把新来的按到水底
func _to_middle() -> void:
	_phase = Phase.MIDDLE
	_clock = 0.0
	_set_veil(1.0)
	_stones.clear()

# ------------------------------------------------------------------ 拿起来、放回去

## 盖住：把旧棋盘拿起来。从水车那一格往外按格子量距离，近的一圈先沉；主角脚下那一块留到最后
func _take_old_board(ctx: Dictionary) -> void:
	_stones.clear()
	_riders.clear()
	_hero = null
	var main := ctx.get("main") as Main
	if main == null or not is_instance_valid(main.grid) or main.grid.tiles.is_empty(): return
	var centre := _centre(ctx, main)
	var unit: float = main.grid.tile_size.x
	var rings := 0
	for tile: Tile in main.grid.tiles.values():
		var s := Stone.new()
		s.tile = tile
		s.rest = _rest_y(tile)
		s.from = tile.global_position.y
		s.secs = DROP_SECS
		s.ring = int(floor(Vector2(tile.global_position.x - centre.x, tile.global_position.z - centre.y).length() / unit + 0.5))
		rings = maxi(rings, s.ring)
		_stones.append(s)
		if tile == main.character.target_tile: _hero = s
	if _hero == null: _hero = _stones[0]
	# 一圈隔一圈地沉，总归在盖住的前六成长里沉完，留给暗幕和主角那一块。大棋盘圈多就挤一挤，小棋盘就慢一点
	var gap := _wave_gap(rings, _total * 0.6 - DROP_SECS)
	var latest := 0.0
	for s in _stones:
		s.at = (s.ring - 1) * gap + s.tile.rseed * gap * 0.2     # 同一圈里的几块差一点点，不是齐刷刷的
		if s != _hero: latest = maxf(latest, s.at)
	_hero.secs = HERO_DROP_SECS
	_hero.at = clampf(latest + DROP_SECS + 0.02, _total * 0.4, _total - HERO_DROP_SECS - 0.04)
	_riders.append(_make_rider(main.character, _hero))
	# 对战里的对手站在它自己那一块上，跟着那一块走
	if main.versus != null and is_instance_valid(main.versus.foe):
		var foe: Character = main.versus.foe
		_riders.append(_make_rider(foe, _stone_of(foe.target_tile)))

func _make_rider(node: Node3D, stone: Stone) -> Rider:
	var r := Rider.new()
	r.node = node
	r.stone = stone
	return r

func _stone_of(tile: Tile) -> Stone:
	for s in _stones:
		if s.tile == tile: return s
	return null

## 一圈隔多久：想把 wave 这么长的一段分给 rings 圈，但每圈至少隔那么一下、至多也不过那么久
func _wave_gap(rings: int, wave: float) -> float:
	var lo := 0.02 if _total < 0.4 else WAVE_GAP_MIN
	return clampf(wave / maxf(rings - 1.0, 1.0), lo, WAVE_GAP_MAX)

## 还没拿起来的石阶都拿起来、按到水底（新棋盘每一块都从水底往上浮）
func _hold_board(main: Main) -> void:
	var taken := {}
	for s in _stones:
		if is_instance_valid(s.tile): taken[s.tile] = s
	for tile: Tile in main.grid.tiles.values():
		if taken.has(tile): continue
		var s := Stone.new()
		s.tile = tile
		s.rest = _rest_y(tile)
		s.from = s.rest - SINK_DEPTH
		s.secs = _rise
		s.done = true
		_stones.append(s)
		_set_stone_y(s, s.from)

## 掀开：新棋盘已经在水底了，定下谁先浮。主角落脚的那一格先浮，往外一圈一圈跟着
func _take_new_board(ctx: Dictionary) -> void:
	var main := ctl.get_node_or_null("/root/Main") as Main
	_stones = _stones.filter(func(s: Stone) -> bool: return is_instance_valid(s.tile))
	# 上一趟的角色：脚下那一块还在（就地放一遍，棋盘没换）的照旧跟着走；不在了的（换了棋盘）当成沉在水底的，别让它浮出来站着
	var old := _riders
	_riders.clear()
	for r in old:
		if is_instance_valid(r.node): _riders.append(r)
	_hero = null
	if main == null or not is_instance_valid(main.grid) or main.grid.tiles.is_empty(): return
	_hold_board(main)
	var centre := _centre(ctx, main)
	var unit: float = main.grid.tile_size.x
	var rings := 0
	var nearest := 1e9
	for s in _stones:
		var d := Vector2(s.tile.global_position.x - centre.x, s.tile.global_position.z - centre.y).length() / unit
		s.ring = int(floor(d + 0.5))
		rings = maxi(rings, s.ring)
		s.done = false
		s.secs = _rise
		if d < nearest:
			nearest = d
			_hero = s
	var gap := _wave_gap(rings + 1, _total * 0.96 - _rise)
	for s in _stones:
		s.at = s.ring * gap + s.tile.rseed * gap * 0.2
	_hero.at = 0.02
	# 主角站上新一关的起点。上一趟记下的主角那一条不要了（它脚下是旧棋盘的石头）
	_riders = _riders.filter(func(r: Rider) -> bool: return not is_instance_valid(r.node) or r.node != main.character)
	_riders.append(_make_rider(main.character, _hero))

## 把一块石阶放到 y 这么高。它上面摆着的灯、道具跟着走；站在它上面的角色也跟着走
func _set_stone_y(s: Stone, y: float) -> void:
	s.tile.global_position.y = y
	var o: Node3D = s.tile.object
	if o != null and is_instance_valid(o): o.global_position.y = y
	for r in _riders:
		if r.stone == s and is_instance_valid(r.node): r.node.global_position.y = y

## 中间和掀开的时侯，角色每一帧都会被它自己的 _process 拉回原处（它记着的目标格子的高度是载入时的）：
## 脚下有石阶的跟着石阶走，脚下没有的按在水底下
func _keep_under() -> void:
	for r in _riders:
		if not is_instance_valid(r.node): continue
		if r.stone != null and is_instance_valid(r.stone.tile): r.node.global_position.y = r.stone.tile.global_position.y
		else: r.node.global_position.y = -GHOST_DEPTH

## 暗幕按画面算宽高（画面是 1152×720，掌机的窗口是 2560×1600，不写死）
func _fit_veil() -> void:
	var size := ctl.get_viewport().get_visible_rect().size
	veil.material.set("shader_parameter/aspect", size.x / maxf(size.y, 1.0))

## 过渡做完：借走的都还回去。石阶回到载入时记下的高度，暗幕收走
func _give_back() -> void:
	for s in _stones:
		if is_instance_valid(s.tile): _set_stone_y(s, s.rest)
	for r in _riders:
		# 脚下已经没有石阶的角色（旧棋盘上的对手）：把它放回它自己记着的位置，新对手摆好了游戏会把它收走
		if is_instance_valid(r.node) and r.node is Character and (r.stone == null or not is_instance_valid(r.stone.tile)):
			var who: Character = r.node
			who.global_position.y = who.target_position.y
	_stones.clear()
	_riders.clear()
	_hero = null
	_phase = Phase.IDLE
	_set_veil(0.0)
	veil.visible = false
	driver.set_process(false)

## 中心在哪儿：盖住的时侯是水车那一格（主角正站在它上面）；没有水车、或者掀开的时侯，用 ctx 里的那个点
func _centre(ctx: Dictionary, main: Main) -> Vector2:
	var p: Vector3 = main.character.global_position if ctx.get("to") == null else ctx.to
	if ctx.get("to") == null and is_instance_valid(main.end_portal_instance): p = main.end_portal_instance.global_position
	return Vector2(p.x, p.z)

## 平时石阶停在多高。和 tile.gd 的 _process 里那个 rest_height 是同一个式子：碎掉的脆格沉着一截，
## 障碍高出一截，选技能目标的时侯选中的那一格抬起来。过渡做完要回到这儿，不然它自己还得慢慢飘回去
static func _rest_y(tile: Tile) -> float:
	return tile.pos_y + tile.aim_raise - (0.9 if tile.is_broken() else 0.0) + (0.8 if tile.is_blocked() else 0.0)

## 沉下去 / 浮上来的地方河面荡开一圈。水面上的涟漪只有六个位置轮着用（stage_backdrop.gd），所以只给主角脚下那一块
func _ripple(s: Stone, amp: float) -> void:
	if s != _hero: return
	var main := ctl.get_node_or_null("/root/Main")
	if main == null: return
	var stage: Node = main.get_node_or_null("StageBackdrop")
	if stage == null or not stage.has_method("ripple"): return
	var p: Vector3 = s.tile.global_position
	stage.call("ripple", Vector2(p.x, p.z), amp)

## 最近一趟量出来的数（给 Driver.debug_last 用）
func debug_last() -> String:
	return "石阶沉浮：盖住最长一帧 %.1f 毫秒，中间最长一帧 %.1f 毫秒，掀开最长一帧 %.1f 毫秒" % [
		float(_frames.get("cover", 0)) / 1000.0, float(_frames.get("load", 0)) / 1000.0, float(_frames.get("reveal", 0)) / 1000.0]

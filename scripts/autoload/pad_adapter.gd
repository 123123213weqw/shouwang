extends Node
# 《守望》掌机适配层：手柄操作和自动测试都靠它，开机就加载（project.godot 里自动加载的 PadAdapter）
# 1) 手柄映射到原工程的按键动作：左摇杆/十字键 = WASD，A = Power(空格)，Start/Back = 菜单(Esc)，B = 返回
# 2) 左摇杆同时驱动一个虚拟光标；光标停在界面控件上时，按 A 等于鼠标点击
# 3) 调试遥控：只监听 127.0.0.1，命令 snapshot / full / ui / texts / click / key / call（见文件末尾的两个调试方法）
# 4) 限帧 60：这台掌机满载会突然断电

# 调试遥控的端口和截图的临时文件可以用环境变量 SW_DEBUG_PORT、SW_SNAP 改：
# 几个互不相干的测试实例同时跑的时候各用各的
var port := 9878
var snap_path := "/tmp/sw_snap"
const CURSOR_SPEED := 1400.0
const STICK_DEADZONE := 0.25

var _srv := TCPServer.new()
var _clients: Array = []
var _cursor: Control
var _cursor_pos := Vector2.ZERO
var _click_state := 0
var _click_target := Vector2.ZERO
var _a_prev := false
var _burst_left := 0
var _burst_phase := -1
var _burst_done := {}
var _burst_started := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 帧率交给垂直同步（跟着屏幕刷新率走）。再叠一个 60 帧的死上限，限速器先睡到 16.6 毫秒、垂直同步再等下一次刷新，
	# 两者互相等，帧时间就会一会儿 16 毫秒一会儿 33 毫秒。要压帧率做测试就设 SW_FPS_CAP
	var cap := OS.get_environment("SW_FPS_CAP")
	Engine.max_fps = int(cap) if cap != "" else 0
	_add_pad_events()
	_record_boot()
	if OS.get_environment("SW_DEBUG_PORT") != "": port = int(OS.get_environment("SW_DEBUG_PORT"))
	if OS.get_environment("SW_SNAP") != "": snap_path = OS.get_environment("SW_SNAP")
	_srv.listen(port, "127.0.0.1")
	_make_cursor.call_deferred()

func _make_cursor() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var cursor := Control.new()
	cursor.set_script(preload("res://scripts/autoload/virtual_cursor.gd"))
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cursor)
	get_tree().root.add_child(layer)
	_cursor = cursor
	_cursor_pos = get_viewport().get_visible_rect().size / 2.0

func _process(delta: float) -> void:
	_pump_remote()
	_frame_log(delta)
	_autoplay_step(delta)
	_record_tick(delta)
	# 连拍：着色器的抖动每换到一个还没拍过的相位就拍一张（见 debug_burst）
	if _burst_left > 0:
		var now := Time.get_ticks_msec()
		var phase := int(now * 0.008) % 10
		if phase != _burst_phase and not _burst_done.has(phase):
			_burst_phase = phase
			_burst_done[phase] = true
			_burst_left -= 1
			get_viewport().get_texture().get_image().save_png("%s_P%d.png" % [snap_path, phase])
		elif now - _burst_started > 40000:
			print("BURST 超时：只拍到 ", _burst_done.size(), " 个相位")
			_burst_left = 0
	if _cursor == null:
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var pad_connected := Input.get_connected_joypads().size() > 0
	_cursor.visible = pad_connected
	# 正在执行一个排队的点击（遥控的 click，或者手柄的 A）：这三帧里别再推虚拟光标的位置。
	# 中间那一帧的"移回光标处"会把按钮的按下状态取消掉——掌机接着手柄，每帧都在推，遥控的点击就一直点不动
	if pad_connected and _click_state == 0:
		var stick := _stick_vector()
		if stick.length() > 0.0:
			_cursor_pos = (_cursor_pos + stick * CURSOR_SPEED * delta).clamp(Vector2.ZERO, size)
		# 接了手柄就以虚拟光标为准：每帧同步一次悬停位置
		_push_motion(_cursor_pos)
	# 排队的点击不依赖手柄是否连着
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var a_now := pad_connected and _any_pad_button(JOY_BUTTON_A)
	if a_now and not _a_prev and hovered != null and _click_state == 0:
		_click_target = _cursor_pos
		_click_state = 1
	_a_prev = a_now
	match _click_state:
		1:
			_push_motion(_click_target)
			_click_state = 2
		2:
			_push_button(_click_target, true)
			_click_state = 3
		3:
			_push_button(_click_target, false)
			_click_state = 0
	_cursor.is_hot = hovered != null
	_cursor.pos_to_draw = _cursor_pos
	_cursor.queue_redraw()

# ---------- 手柄映射 ----------
func _axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)

func _button(action: String, index: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = index
	InputMap.action_add_event(action, ev)

func _add_pad_events() -> void:
	_axis("MoveForward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("MoveBack", JOY_AXIS_LEFT_Y, 1.0)
	_axis("MoveLeft", JOY_AXIS_LEFT_X, -1.0)
	_axis("MoveRight", JOY_AXIS_LEFT_X, 1.0)
	_button("MoveForward", JOY_BUTTON_DPAD_UP)
	_button("MoveBack", JOY_BUTTON_DPAD_DOWN)
	_button("MoveLeft", JOY_BUTTON_DPAD_LEFT)
	_button("MoveRight", JOY_BUTTON_DPAD_RIGHT)
	_button("Power", JOY_BUTTON_A)
	_button("OpenMenu", JOY_BUTTON_START)
	_button("OpenMenu", JOY_BUTTON_BACK)
	if InputMap.has_action("ui_cancel"):
		_button("ui_cancel", JOY_BUTTON_B)

# Legion Go 的左右手柄在系统里是两个独立设备，所以把所有设备的左摇杆加在一起
func _stick_vector() -> Vector2:
	var v := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var x := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
		if absf(x) < STICK_DEADZONE:
			x = 0.0
		if absf(y) < STICK_DEADZONE:
			y = 0.0
		v += Vector2(x, y)
	return v.limit_length(1.0)

func _any_pad_button(index: JoyButton) -> bool:
	for dev in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(dev, index):
			return true
	return false

# ---------- 合成鼠标事件（分三帧：移动、按下、抬起）----------
func _push_motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	get_viewport().push_input(ev, true)

func _push_button(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	get_viewport().push_input(ev, true)

# ---------- 调试遥控 ----------
func _pump_remote() -> void:
	if _srv.is_connection_available():
		_clients.append(_srv.take_connection())
	for i in range(_clients.size() - 1, -1, -1):
		var c: StreamPeerTCP = _clients[i]
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(i)
			continue
		var n := c.get_available_bytes()
		if n <= 0:
			continue
		var line: String = c.get_data(n)[1].get_string_from_utf8().strip_edges()
		if line.is_empty():
			continue
		c.put_data((_handle(line) + "\n").to_utf8_buffer())
		# 答完就挂断：客户端读到结尾符立刻返回，不用干等到超时（一条命令一个连接）
		c.disconnect_from_host()
		_clients.remove_at(i)
		continue

func _handle(line: String) -> String:
	var parts: PackedStringArray = line.split(" ")
	match parts[0]:
		"hello":
			return "OK pad adapter"
		"size":
			var s: Vector2 = get_viewport().get_visible_rect().size
			return "OK viewport %dx%d window %dx%d joypads %d fps %d" % [
				int(s.x), int(s.y),
				DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
				Input.get_connected_joypads().size(), Engine.get_frames_per_second()]
		"snapshot":
			var img := get_viewport().get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
			img.save_jpg(snap_path + ".jpg", 0.85)
			return "OK snapshot %dx%d" % [img.get_width(), img.get_height()]
		"full":
			get_viewport().get_texture().get_image().save_png(snap_path + ".png")
			return "OK full png"
		"scene":
			var cur: Node = get_tree().current_scene
			return "OK scene %s (%s) paused=%s" % [
				cur.name if cur != null else "<none>",
				cur.scene_file_path if cur != null else "",
				str(get_tree().paused)]
		"pad":
			var lines: Array = []
			for dev in Input.get_connected_joypads():
				lines.append("pad %d '%s' L=(%.2f,%.2f) R=(%.2f,%.2f) A=%s B=%s Start=%s" % [
					dev, Input.get_joy_name(dev),
					Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y),
					Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y),
					Input.is_joy_button_pressed(dev, JOY_BUTTON_A),
					Input.is_joy_button_pressed(dev, JOY_BUTTON_B),
					Input.is_joy_button_pressed(dev, JOY_BUTTON_START)])
			return "\n".join(lines) if lines.size() > 0 else "NO-PAD"
		"ui":
			return _dump_ui()
		"texts":
			return _dump_texts()
		"click":
			if parts.size() < 3:
				return "ERR usage: click x y"
			_click_target = Vector2(parts[1].to_float(), parts[2].to_float())
			_cursor_pos = _click_target          # 虚拟光标跟着挪过去（画面上看得见它在点哪儿）
			_click_state = 1
			return "OK click queued"
		"move":
			if parts.size() < 3:
				return "ERR usage: move x y"
			_cursor_pos = Vector2(parts[1].to_float(), parts[2].to_float())
			_push_motion(_cursor_pos)
			return "OK moved"
		"keydown", "keyup":
			var held := InputEventKey.new()
			held.physical_keycode = OS.find_keycode_from_string(parts[1])
			held.keycode = held.physical_keycode
			held.pressed = parts[0] == "keydown"
			get_viewport().push_input(held)
			return "OK " + parts[0] + " " + parts[1]
		"key":
			var code := OS.find_keycode_from_string(parts[1])
			var down := InputEventKey.new()
			down.physical_keycode = code
			down.keycode = code
			down.pressed = true
			get_viewport().push_input(down)
			var up := InputEventKey.new()
			up.physical_keycode = code
			up.keycode = code
			up.pressed = false
			get_viewport().push_input(up)
			return "OK key " + parts[1]
		"spawn":
			# spawn res://resources/heart.tres [次数]：把指定的那样东西放几个到棋盘上（不清场；清场用 debug_spawn 0）
			if parts.size() < 2:
				return "ERR usage: spawn <资源路径> [次数]"
			return _spawn_path(parts[1], int(parts[2]) if parts.size() > 2 else 1)
		"call":
			# 第三个参数以后：写得成整数的按整数传，其余的按文字传（录像的名字就是文字：debug_record 3 20 ring）
			var args: Array = []
			for extra in parts.slice(3):
				args.append(int(extra) if extra.is_valid_int() else extra)
			return _call(parts[1], parts[2], args)
	return "ERR unknown command"

func _dump_ui() -> String:
	var out := ""
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is BaseButton and node.is_visible_in_tree():
			var b: BaseButton = node
			var r: Rect2 = b.get_global_rect()
			var label: String = (b as Button).text if b is Button else ""
			if label == "":
				for child in b.get_children():
					if child is Label or child is RichTextLabel:
						label = child.text
			if b.tooltip_text != null and b.tooltip_text != "":
				label += "  (tip: %s)" % b.tooltip_text
			# 末尾带上节点名：测试脚本按节点名找按钮，界面文字改了也不受影响
			out += "BTN [%d,%d %dx%d] %s <%s>\n" % [
				int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y), label.strip_edges(), b.name]
		for child in node.get_children():
			stack.push_back(child)
	return out if out != "" else "NO-BUTTONS"

func _dump_texts() -> String:
	var items: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if (node is Label or node is RichTextLabel or node is Button) and node.is_visible_in_tree():
			var text: String = ""
			if node is RichTextLabel:
				text = (node as RichTextLabel).get_parsed_text()
			else:
				text = str(node.get("text"))
			text = text.strip_edges()
			if text != "":
				var r: Rect2 = (node as Control).get_global_rect()
				items.append([int(r.position.y), int(r.position.x), text.replace("\n", " / ").substr(0, 80)])
		for child in node.get_children():
			stack.push_back(child)
	items.sort()
	var out: Array = []
	for it in items:
		out.append("(%d,%d) %s" % [it[1], it[0], it[2]])
	return "\n".join(out) if out.size() > 0 else "NO-TEXT"

func _call(script_sub: String, method: String, args: Array) -> String:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var s: Script = node.get_script()
		if s != null and s.resource_path.contains(script_sub) and node.has_method(method):
			var result: Variant = node.callv(method, args)
			return "OK called %s -> %s" % [method, str(result)]
		for child in node.get_children():
			stack.push_back(child)
	return "ERR not found %s.%s" % [script_sub, method]

# 下面几个是调试用的方法，配合遥控的 call 命令：
#   call pad_adapter.gd debug_state          看当前局面的一行摘要
#   call pad_adapter.gd debug_jump_to 3      让主角直接跳到离它最近的某种类型的格子（0 普通 1 脆格 2 障碍 3 补给格）
#                                            再带一个 1 表示只要上面没有东西的空格子，例如 debug_jump_to 3 1
#   call pad_adapter.gd debug_pick_character 0   在选人界面选第几张卡（从 0 数）并进游戏，不用算卡片的坐标
#   call pad_adapter.gd debug_char_variant 1     排查用：把主角的头、身子临时换成 assets/dev/head_N.png、body_N.png

#   call pad_adapter.gd debug_spawn 0        把格子上的东西清掉（传送门留着）
#   spawn res://resources/heart.tres 3    把指定的那样东西放 3 个到棋盘上，不清场（平时不会自己出现的东西，比如心、宝箱、骰子，用它）
#   call pad_adapter.gd debug_spawn 5        清场，再把编号是 5 的那样东西放在离镜头最近的一块空格子上
#   call pad_adapter.gd debug_spawn 5 12     清场后一次放 12 个（一样东西有几个随机外观的版本时，多放几个才都能看到）
#                                         编号见日志里的 SPAWNABLE 清单：先是能收的（鱼、大鱼、心），再是道具，最后是传送门
var spawnable: Array = []
var spawned_count := 0

func debug_spawn(code: int, times: int = 1) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	if spawnable.is_empty():
		for group in [main.fishes, main.upgrades, [main.end_portal]]:
			for res in group:
				if res: spawnable.append(res)
	# 清场：传送门是关卡的一部分，留着
	for tile in main.grid.tiles.values():
		if tile.object and tile.object != main.end_portal_instance:
			tile.object.queue_free()
			tile.object = null
	main.update_tiles_color()
	if code <= 0:
		spawned_count = 0
		return "cleared the board"
	if code == 1 and spawned_count == 0:
		_list_spawnable()
	if code > spawnable.size(): return "no such thing: %d (there are %d)" % [code, spawnable.size()]
	return _put(spawnable[code - 1], times)

func _put(res: ObjectResource, times: int) -> String:
	# 一样东西放几个，从离镜头最近的空格子放起
	var main := get_node("/root/Main")
	var placed: PackedStringArray = []
	for i in maxi(times, 1):
		var empty: Array = main.grid.get_empty_tiles()
		if empty.is_empty(): break
		empty.sort_custom(func(a, b): return a.global_position.z > b.global_position.z or (a.global_position.z == b.global_position.z and a.global_position.x < b.global_position.x))
		var tile: Tile = empty[mini(spawned_count, empty.size() - 1)]
		_place(res, tile)
		spawned_count += 1
		placed.append(tile.name)
	return "spawned %s on %s" % [res.resource_path.get_file(), ", ".join(placed)]

func _spawn_path(res_path: String, times: int) -> String:
	# 游戏平时只往棋盘上放 fishes 和 upgrades 里的那几样；心、宝箱、骰子这些要按资源路径指定
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	if not ResourceLoader.exists(res_path): return "no such resource: " + res_path
	var res: ObjectResource = load(res_path)
	if not spawnable.has(res): spawnable.append(res)
	return _put(res, times)

var _listed := false

func _list_spawnable() -> void:
	# 每次进游戏只往日志里打印一次清单；drive_v100.sh 会把它带到输出里
	if _listed: return
	_listed = true
	var listing: PackedStringArray = []
	for i in spawnable.size():
		listing.append("%d=%s" % [i + 1, spawnable[i].resource_path.get_file()])
	print("SPAWNABLE ", ", ".join(listing))

func debug_spawn_all(start: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	debug_spawn(0)
	_list_spawnable()
	var placed: PackedStringArray = []
	# 先把空格子排好再逐个放，不依赖放上去之后格子状态的刷新
	var empty: Array = main.grid.get_empty_tiles()
	empty.sort_custom(func(a, b): return a.global_position.z > b.global_position.z or (a.global_position.z == b.global_position.z and a.global_position.x < b.global_position.x))
	# 最后一样是传送门，它本来就在棋盘上，不放
	var code := 1 + maxi(start, 0)
	while code < spawnable.size() and code - start - 1 < empty.size():
		var tile: Tile = empty[code - start - 1]
		_place(spawnable[code - 1], tile)
		placed.append("%d=%s@%s" % [code, spawnable[code - 1].resource_path.get_file(), tile.name])
		code += 1
	spawned_count = placed.size()
	return "placed %d: %s" % [placed.size(), ", ".join(placed)]

func _place(res: ObjectResource, tile: Tile) -> void:
	# 照 main.gd 里 spawn_fish 的顺序：先进场景树再设位置（原来的 spawn_object_at_position 是先设位置后进树，会报错）
	var main := get_node("/root/Main")
	var obj: Fish = main.FISH.instantiate()
	main.add_child(obj)
	tile.object = obj
	obj.global_position = tile.global_position
	obj.load_resource(res)

func debug_burst(count: int) -> String:
	_burst_left = mini(count, 10)
	_burst_phase = -1
	_burst_done = {}
	_burst_started = Time.get_ticks_msec()
	return "burst started: %d frames" % _burst_left

func debug_burst_status() -> String:
	return "done %d" % _burst_done.size() if _burst_left <= 0 else "waiting %d" % _burst_left

func _tex_name(tex: Texture2D) -> String:
	return tex.resource_path.replace("res://", "") if tex.resource_path != "" else "<内嵌 %dx%d>" % [tex.get_width(), tex.get_height()]

func _thing_name(node: Node) -> String:
	var res = node.get("resource")
	if res is Resource and res.resource_path != "":
		return res.resource_path.get_file()
	return String(node.name)

func _short_path(node: Node, owner_of: Dictionary) -> String:
	# 这个精灵属于什么：格子上的东西、主角、格子本身，或者界面上离它最近的那个有名字的控件
	var cur: Node = node
	var steps := 0
	while cur != null and steps < 6:
		if owner_of.has(cur):
			return String(owner_of[cur])
		cur = cur.get_parent()
		steps += 1
	var names: PackedStringArray = []
	cur = node
	while cur != null and names.size() < 3:
		names.append(String(cur.name))
		cur = cur.get_parent()
	names.reverse()
	return "/".join(names)

func _node_texture(node: Node, cam: Camera3D) -> Array:
	# 返回 [贴图, 类别, 画布大小, 在画面上的范围]；不是带贴图的可见节点就返回空的
	var art: Texture2D = null
	if node is Sprite3D:
		var s: Sprite3D = node
		if cam == null or s.texture == null: return []
		var size: Vector2 = s.texture.get_size()
		if s.region_enabled: size = s.region_rect.size
		if s.hframes > 1: size.x /= s.hframes
		if s.vframes > 1: size.y /= s.vframes
		# 这块面片是按 sprite 自己的贴图定大小的；着色器里真正画出来的那张图（texture_albedo）可能换过
		art = s.texture
		var mat := s.material_override as ShaderMaterial
		if mat != null and mat.get_shader_parameter("texture_albedo") is Texture2D:
			art = mat.get_shader_parameter("texture_albedo")
		var half: Vector3 = Vector3(size.x * s.pixel_size, size.y * s.pixel_size, 0.0) * 0.5
		var r := Rect2()
		for i in 4:
			var corner := Vector3(half.x if (i & 1) != 0 else -half.x, half.y if (i & 2) != 0 else -half.y, 0.0)
			var p: Vector2 = cam.unproject_position(s.global_transform * corner)
			r = Rect2(p, Vector2.ZERO) if i == 0 else r.expand(p)
		return [art, "3D", r, Vector2(r.size.x / art.get_width(), r.size.y / art.get_height())]
	var tex: Texture2D = null
	if node is TextureRect:
		var t: TextureRect = node
		# 界面上的精灵也是着色器里 texture_albedo 那张图（比如选人卡片，运行时按角色换图），节点的 texture 只是占位
		var mat := t.material as ShaderMaterial
		if mat != null and mat.get_shader_parameter("texture_albedo") is Texture2D:
			tex = mat.get_shader_parameter("texture_albedo")
		elif t.texture is Texture2D:
			tex = t.texture
		if tex == null: return []
		var r: Rect2 = t.get_global_rect()
		var fit: Vector2 = r.size / Vector2(tex.get_width(), tex.get_height())
		# 保持长宽比的模式下，画布不会铺满整个矩形
		if t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT or t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED or t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			fit = Vector2.ONE * (maxf(fit.x, fit.y) if t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED else minf(fit.x, fit.y))
		return [tex, "2D", get_viewport().get_final_transform() * r, fit]
	if node is NinePatchRect:
		if not (node.texture is Texture2D): return []
		tex = node.texture
		return [tex, "2D", get_viewport().get_final_transform() * node.get_global_rect(), node.get_global_transform().get_scale()]
	if node is TextureButton:
		if not (node.texture_normal is Texture2D): return []
		tex = node.texture_normal
		return [tex, "2D", get_viewport().get_final_transform() * node.get_global_rect(), node.get_global_transform().get_scale()]
	if node is Sprite2D:
		if not (node.texture is Texture2D): return []
		tex = node.texture
		var r: Rect2 = node.get_rect()
		return [tex, "2D", get_viewport().get_final_transform() * node.get_global_transform() * r, node.get_global_transform().get_scale()]
	return []

func debug_rects() -> String:
	# 标题页、选人页这些纯界面的场景没有镜头，只量界面上的贴图
	var cam: Camera3D = get_viewport().get_camera_3d()
	var main := get_node_or_null("/root/Main")
	var owner_of := {}
	if main != null:
		for tile in main.grid.tiles.values():
			if tile.object: owner_of[tile.object] = "%s@%s" % [_thing_name(tile.object), tile.name]
	# 贴图 → 按类别和 zoom 分组：[个数, 最小 zoom, 最大 zoom, 最大那一个的范围, 它在哪]
	var info := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if (node is CanvasItem or node is Node3D) and node.is_visible_in_tree():
			var found: Array = _node_texture(node, cam)
			if not found.is_empty() and found[3].x > 0.0:
				var zoom: float = found[3].x
				var key := "%s|%s|%.2f" % [_tex_name(found[0]), found[1], zoom]
				if not info.has(key):
					info[key] = [0, zoom, zoom, found[2], _short_path(node, owner_of)]
				info[key][0] += 1
		for child in node.get_children():
			stack.push_back(child)
	if info.is_empty(): return "no textured nodes on screen"
	var keys := info.keys()
	keys.sort()
	var out: PackedStringArray = []
	for key in keys:
		var parts: PackedStringArray = key.split("|")
		var it: Array = info[key]
		var r: Rect2 = it[3]
		out.append("RECT %s  x%d  zoom %s  画面 [%d,%d %dx%d]  %s" % [
			parts[0], it[0], parts[2], r.position.x, r.position.y, r.size.x, r.size.y, it[4]])
	return "
".join(out)

#   call pad_adapter.gd debug_goto_level 12   直接跳到第几关（主线 1 到 12；长夜模式里是第几更，可以更大）。
#                                           镜头会按棋盘大小拉远，棋盘越大、离镜头越远的东西在屏幕上越小：
#                                           细节要在最小的那种情况下也看得出来
#   call pad_adapter.gd debug_seed 7         把长夜模式的随机数定住（只在内存里）：之后再生成的棋盘每次都一样，自动测试用。
#                                           定完要再跳一次关（debug_goto_level），眼前的这张不会变
func debug_goto_level(n: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var name := ""
	if main.is_endless():
		main.current_level_index = n - 1
		main.load_level(main.endless_level(n))
		name = "长夜"
	else:
		var levels: Array = main.levels
		if n < 1 or n > levels.size(): return "no level %d (there are %d)" % [n, levels.size()]
		main.current_level_index = n - 1
		main.load_level(levels[n - 1])
		name = levels[n - 1].level_name
	main.reset_upgrades()
	main.load_character(Game.selected_character)
	return "loading level %d (%s)" % [n, name]

## 把长夜模式的随机数定住（只在内存里）：之后生成的每一更棋盘，都和上一次用同一个种子时的一样。自动测试靠它不靠运气
func debug_seed(seed_value: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	main.endless_rng.seed = seed_value
	return "endless seed set to %d" % seed_value

#   call pad_adapter.gd debug_unlock_all  把所有角色设成已解锁（只在内存里，不写存档），选人界面马上刷新
func debug_unlock_all() -> String:
	Game.unlocked_characters = Game.characters.duplicate()
	var title := get_node_or_null("/root/Title")
	if title and title.has_method("update_characters"): title.update_characters()
	return "unlocked %d characters" % Game.unlocked_characters.size()

#   call pad_adapter.gd debug_play_character 3   游戏里直接把主角换成第几张卡的角色（只换头和身子的图，数值不变），看新角色的实拍用
func debug_play_character(index: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var list: Array = Game.characters
	if index < 0 or index >= list.size(): return "no character %d (there are %d)" % [index, list.size()]
	Game.selected_character = list[index]
	main.character.load_resource(list[index])
	# HUD 上技能按钮里的图标也跟着换（照 main.gd 的 load_character）
	main.active_control.active_effect_sprite.material.set("shader_parameter/texture_albedo", list[index].active_effect_sprite)
	# 没有自己身子图的角色用的是共用的那张；从守夜人换过来的时候要把它换回去
	if not list[index].body_sprite:
		main.character.get_node("SpriteContainer/BodySprite").material_override.set("shader_parameter/texture_albedo", load("res://assets/sprites/characters/body.png"))
	return "now showing %s" % list[index].character_name

#   call pad_adapter.gd debug_charge_full    把技能充能充满：HUD 上的技能图标变成亮色，抖动也更大（充能后 displacement_power 从 0.5 变成 2.0）
#   call pad_adapter.gd debug_charge_empty   把充能放空
func debug_charge(amount: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var cc = main.active_control.charges_control
	cc.charges = cc.max_charges if amount > 0 else 0
	for i in cc.charges_container.get_child_count():
		cc.charges_container.get_child(i).set_enabled(i < cc.charges)
	cc.update()
	main.active_control.update()
	return "charges %d/%d" % [cc.charges, cc.max_charges]

#   call pad_adapter.gd debug_lock_all     把除了守夜人以外的角色重新锁上（只在内存里，不写存档），选人界面马上刷新。拍锁定状态用
func debug_lock_all() -> String:
	Game.unlocked_characters = Game.characters.filter(func(a: CharacterResource): return not a.locked)
	var title := get_node_or_null("/root/Title")
	if title and title.has_method("update_characters"): title.update_characters()
	return "locked: %d unlocked left" % Game.unlocked_characters.size()

#   call pad_adapter.gd debug_marker 1    排查用：让主角的技能临时变成"回到上一格"并充满充能，刚离开的格子上就会出现弯箭头记号。
#                                       现在的六个角色都没有这个技能，平时看不到那个记号
func debug_marker(on: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var res: CharacterResource = Game.selected_character
	res.active_effect = CharacterResource.ActiveEffect.ReturnToLastPosition if on > 0 else CharacterResource.ActiveEffect.SpawnFishes
	debug_charge(1)
	main.update_tiles_color()
	return "marker on" if on > 0 else "marker off"

#   call pad_adapter.gd debug_tutorial_reset   把新手教程从头来一遍（只在内存里，不写存档）：之后该弹的提示都会再弹
#   call pad_adapter.gd debug_tutorial_card    随时把"玩法"卡片调出来
func debug_tutorial_reset() -> String:
	Game.tutorial_seen = {}
	var main := get_node_or_null("/root/Main")
	if main and main.tutorial:
		main.tutorial._shown = {}
		main.tutorial.hint_label.visible = false
	return "tutorial reset: %d seen" % Game.tutorial_seen.size()

func debug_tutorial_card() -> String:
	var main := get_node_or_null("/root/Main")
	if main == null or main.tutorial == null: return "not in game"
	main.tutorial.show_card(not Game.tutorial_seen.has(Tutorial.RULES_SEEN))
	return "card shown"

#   call pad_adapter.gd debug_tutorial_hint 2   手动弹一条提示（1 踩到空格子，2 技能充满，3 水车开了），拍图用
#   call pad_adapter.gd debug_tutorial_seen    看哪些提示已经看过
func debug_tutorial_hint(code: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null or main.tutorial == null: return "not in game"
	var names := ["empty", "skill", "portal"]
	if code < 1 or code > names.size(): return "no such hint: %d" % code
	main.tutorial.hint(names[code - 1])
	return "hint %s" % names[code - 1]

#   call pad_adapter.gd debug_tutorial_fake_pad 1   排查用：让新手教程按"接了手柄"来写操作说明（测试机上没有手柄）
func debug_tutorial_fake_pad(on: int) -> String:
	Tutorial.fake_pad = on > 0
	return "fake pad %s" % Tutorial.fake_pad

func debug_tutorial_seen() -> String:
	return "seen: " + ", ".join(Game.tutorial_seen.keys())

func debug_char_variant(index: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var swapped: Array[String] = []
	for pair in [["HeadSprite", "head"], ["BodySprite", "body"]]:
		var path := "res://assets/dev/%s_%d.png" % [pair[1], index]
		if ResourceLoader.exists(path):
			main.character.get_node("SpriteContainer/" + pair[0]).material_override.set("shader_parameter/texture_albedo", load(path))
			swapped.append(pair[1])
	return "swapped: " + ", ".join(swapped) if swapped else "no variant %d" % index

func debug_char_tree() -> String:
	# 排查用：列出主角下面的所有节点，精灵的话带上位置、贴图、是否受灯光
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var out: PackedStringArray = []
	var stack: Array = [[main.character, 0]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var extra := ""
		if node is Sprite3D:
			var s: Sprite3D = node
			extra = "  pos=(%.2f,%.2f,%.2f) vis=%s shaded=%s tex=%s size=%s" % [s.global_position.x, s.global_position.y, s.global_position.z,
				s.visible, s.shaded, s.texture.resource_path.get_file() if s.texture else "-",
				str(s.texture.get_size()) if s.texture else "-"]
		elif node is MeshInstance3D or node is GPUParticles3D or node is Label3D:
			extra = "  vis=%s" % node.visible
		out.append("%s%s (%s)%s" % ["  ".repeat(pair[1]), node.name, node.get_class(), extra])
		var kids: Array = node.get_children()
		kids.reverse()
		for child in kids:
			stack.push_back([child, pair[1] + 1])
	return "\n".join(out)

func debug_char_flags(flags: int) -> String:
	# 排查用，按位开关：1 隐藏头的精灵，2 隐藏身子的精灵，4 关掉拖尾粒子，8 关掉格子上所有物体的粒子
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var ch: Node3D = main.character
	ch.get_node("SpriteContainer/HeadSprite").visible = flags & 1 == 0
	ch.get_node("SpriteContainer/BodySprite").visible = flags & 2 == 0
	ch.get_node("SpriteContainer/TrailParticles3D").emitting = flags & 4 == 0
	if flags & 8:
		for tile in main.grid.tiles.values():
			if tile.object and tile.object is Fish:
				for n in ["BubbleParticles", "SplashParticles", "LootParticles"]:
					var part = tile.object.get_node_or_null(n)
					if part: part.emitting = false
	return "flags=%d head_visible=%s body_visible=%s trail_emitting=%s" % [flags,
		ch.get_node("SpriteContainer/HeadSprite").visible, ch.get_node("SpriteContainer/BodySprite").visible,
		ch.get_node("SpriteContainer/TrailParticles3D").emitting]

func debug_pick_character(index: int) -> String:
	var container := get_node_or_null("/root/Title/CanvasLayer/TitleControl/CharacterSelect/CharactersContainer")
	if container == null: return "not on the character select screen"
	if index < 0 or index >= container.get_child_count():
		return "no card %d (there are %d)" % [index, container.get_child_count()]
	var card = container.get_child(index)
	if not card.is_enabled: return "card %d is locked" % index
	Game.selected_character = card.resource
	SceneManager.load_game()
	return "picked card %d (%s), loading game" % [index, card.resource.character_name]

func debug_state() -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game (scene has no Main node)"
	var counts := {}
	var available := 0
	var broken := 0
	for tile in main.grid.tiles.values():
		counts[tile.tile_type] = counts.get(tile.tile_type, 0) + 1
		if tile.is_available: available += 1
		if tile.is_broken(): broken += 1
	var pos: Vector2 = main.grid.world_to_grid_position(main.character.global_position)
	return "label='%s' index=%d mode=%d tiles=%d types=%s available=%d broken=%d moves=%d combo=%d fish=%d/%d credits=%.1f pos=(%.1f,%.1f) score=%d records=%s missteps=%d shields=%d reach=%.2f dealt=%s ready=%s skill=%d/%d usable=%s aim=%d left=%d cand=%d" % [
		main.level_label.text, main.current_level_index, Game.game_mode, main.grid.tiles.size(), counts, available, broken,
		main.moves_left, main.combo, main.current_fish_count, main.fish_before_end_portal, main.credits, pos.x, pos.y,
		main.score, Game.best_records, main.level_missteps, main.shields, main._reach_now(), str(not main.current_deal.is_empty()), str(main.level_ready),
		main.active_control.charges_control.charges, main.active_control.charges_control.max_charges, str(main.can_use_skill()),
		main.aiming, main.aim_left, main.aim_list.size()]

func debug_jump_to(tile_type: int, empty_only: int = 0) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	if main.character.is_jumping: return "busy: still jumping"
	var best: Tile = null
	var best_d := 1e12
	var cpos: Vector3 = main.character.global_position
	for tile in main.grid.tiles.values():
		if tile.tile_type != tile_type or tile == main.character.target_tile or not tile.is_landable(): continue
		if empty_only != 0 and tile.object != null: continue
		var d: float = tile.global_position.distance_to(cpos)
		if d < best_d:
			best_d = d
			best = tile
	if best == null: return "no such tile"
	main.character.move_to(best)
	return "jumping to (%.1f, %.1f), distance %.1f" % [best.global_position.x, best.global_position.z, best_d]

#   call pad_adapter.gd debug_next_fish      让主角跳到离它最近的有鱼的格子；鱼吃完了就跳进终点传送门
# 配合起来就能把"吃满鱼 → 传送门打开 → 进门 → 下一关"这条真实的过关流程整个走一遍

func debug_next_fish() -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	if main.character.is_jumping: return "busy: still jumping"
	var cpos: Vector3 = main.character.global_position
	var best_fish: Tile = null
	var best_portal: Tile = null
	var fish_d := 1e12
	var portal_d := 1e12
	for tile in main.grid.tiles.values():
		if tile == main.character.target_tile or not tile.is_landable() or tile.object == null: continue
		var d: float = tile.global_position.distance_to(cpos)
		if tile.object.is_portal:
			if d < portal_d:
				portal_d = d
				best_portal = tile
		elif not tile.object.is_upgrade and d < fish_d:
			fish_d = d
			best_fish = tile
	if best_fish != null:
		main.character.move_to(best_fish)
		return "jumping to fish at (%.1f, %.1f)" % [best_fish.global_position.x, best_fish.global_position.z]
	if best_portal != null:
		main.character.move_to(best_portal)
		return "no fish left, jumping to portal at (%.1f, %.1f)" % [best_portal.global_position.x, best_portal.global_position.z]
	return "no fish and no portal found"

#   call pad_adapter.gd debug_board_screen   棋盘在屏幕上占的范围（像素），用来确认整张棋盘都在画面里

func debug_board_screen() -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	var size: Vector2 = get_viewport().get_visible_rect().size
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var half: float = main.grid.tile_size.x * 0.5
	for tile in main.grid.tiles.values():
		# 四个角都算：格子有大小，只算中心点的话边缘可能已经出画面了
		for corner in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(-half, 0, half), Vector3(half, 0, half)]:
			var p: Vector2 = main.camera_3d.unproject_position(tile.global_position + corner)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var fits: bool = lo.x >= 0.0 and hi.x <= size.x and lo.y >= 0.0 and hi.y <= size.y
	return "棋盘在画面里: x %.0f..%.0f  y %.0f..%.0f（画面 %dx%d）  镜头距离 %.2f  可挪 %.2f  放得下=%s" % [
		lo.x, hi.x, lo.y, hi.y, size.x, size.y, main.camera_dist, main.camera_slack, fits]

#   call pad_adapter.gd debug_set_view_height 720   把窗口改成 1152×720（16:10，掌机屏幕的比例）；改回 648 就是 16:9
# 注意：在 V100 那个没有窗口管理器的测试环境里，窗口变了但画面尺寸不会跟着变，所以量掌机比例
# 要在启动时就指定分辨率（tools/playtest/launch_v100.sh 的 SW_RES），这个方法留给有桌面环境的情况

func debug_set_view_height(height: int) -> String:
	DisplayServer.window_set_size(Vector2i(1152, height))
	var size := DisplayServer.window_get_size()
	return "window %dx%d" % [size.x, size.y]

#   call pad_adapter.gd debug_watch         在游戏里按帧记录 14 秒：碎掉的脆格数、步数、连击、是否在跳、所在的格子
#   call pad_adapter.gd debug_report        取上面记录到的内容（只列状态发生变化的时刻）
# 脆格从碎掉到恢复只有 2.5 秒，在游戏里记时间线比从外面掐表可靠。

var _watch_log: PackedStringArray = []
var _watching := false

func debug_watch() -> String:
	if _watching: return "already watching"
	if get_node_or_null("/root/Main") == null: return "not in game"
	_watching = true
	_watch_log.clear()
	var start := Time.get_ticks_msec()
	var last := ""
	while Time.get_ticks_msec() - start < 14000:
		await get_tree().process_frame
		var main := get_node_or_null("/root/Main")
		if main == null: break
		var broken := 0
		for tile in main.grid.tiles.values():
			if tile.is_broken(): broken += 1
		# 位置取落脚的格子而不是实时坐标，免得跳跃途中每一帧都记一行
		var pos := Vector2(-99.0, -99.0)
		if main.character.target_tile != null:
			pos = main.grid.world_to_grid_position(main.character.target_tile.global_position)
		var s := "broken=%d moves=%d combo=%d jumping=%s tile=(%.1f,%.1f)" % [
			broken, main.moves_left, main.combo, main.character.is_jumping > 0.0, pos.x, pos.y]
		if s != last:
			_watch_log.append("%6.2fs %s" % [(Time.get_ticks_msec() - start) / 1000.0, s])
			last = s
	_watch_log.append("  (记录结束)")
	_watching = false
	return "watch finished"

func debug_report() -> String:
	if _watching: return "still watching, call again later"
	return "\n".join(_watch_log) if _watch_log.size() > 0 else "nothing recorded"

# ================================================================ 自动试玩
## 让游戏自己玩（真机、真渲染、真计时）：调平衡和回归测试用。
##   call pad_adapter.gd debug_autoplay 1        照着摆棋的那条路线走：必须一步不错、每关都过。哪一跳引擎说跳不到，就是摆棋的模型和引擎对不上
##   call pad_adapter.gd debug_autoplay 2        贪心打法（BoardSim 的那套：够得着的灯里挑最近的）：当作"随手玩的玩家"的下限
##   call pad_adapter.gd debug_autoplay 0        停
##   第二个参数是最多打到第几关（长夜里用，免得停不下来）
## 玩法卡片开着、正在跳、正在换关的时侯它等着。一局结束了（结算面板出来，或者打到指定的关数）自己停，
## 并把这一局的记录打印成一行 AUTOPLAY_RESULT（JSON），debug_autoplay_report 随时能再要一份
var _auto_mode := 0
var _auto_max_level := 999
var _auto_wait := 0.0
var _auto_route_i := 0
var _auto_serial := -1
var _auto_report: Dictionary = {}
var _auto_broken := 0              # 照路线走却走不到的次数（模型和引擎对不上）
var _auto_waited := false           # 这一关等到灯摆完了才动手（换关后 1.5 秒还没载入完）
var _auto_t0 := 0.0                 # 这一关开始载入的时刻
var _auto_n := 0                    # 这一关里机器人走了几步
var _auto_trace := OS.get_environment("SW_AUTO_TRACE") != ""   # 设了就把机器人每一步都打进日志
var _auto_eager := OS.get_environment("SW_AUTO_EAGER") != ""   # 设了就换关后只等 0.2 秒：试它在灯还没摆完的时侯会不会乱动
var _auto_bad_seen := ""            # 这一关里棋盘登记上最近一次查出的毛病（同一种只报一次）

## 棋盘上的登记对不对：每盏灯只登记在一个格子上；格子指着的节点都还在，也都停在它登记的那个格子附近
##（捞网挪灯要 0.2 秒，挪到一半的时侯灯在两个格子之间，算正常）。没问题返回空字符串
func _board_check(main: Node) -> String:
	var seen: Dictionary = {}
	for t in main.grid.tiles.values():
		if t.object == null: continue
		if not is_instance_valid(t.object): return "格子 (%d, %d) 指着一个已经不存在的灯" % [main.to_cell(t.global_position).x, main.to_cell(t.global_position).y]
		var here := Vector2(t.global_position.x, t.global_position.z)
		var there := Vector2(t.object.global_position.x, t.object.global_position.z)
		if here.distance_to(there) > main.grid.tile_size.x * 1.6:
			return "格子 (%d, %d) 登记的灯不在它登记的格子上" % [main.to_cell(t.global_position).x, main.to_cell(t.global_position).y]
		if not seen.has(t.object): seen[t.object] = 0
		seen[t.object] = int(seen[t.object]) + 1
	for fish in seen:
		if int(seen[fish]) > 1: return "同一盏灯登记在 %d 个格子上" % int(seen[fish])
	return ""

func debug_autoplay(mode: int, max_level: int = 999) -> String:
	var main := get_node_or_null("/root/Main")
	_auto_mode = clampi(mode, 0, 2)
	_auto_max_level = max_level
	_auto_wait = 1.0
	_auto_route_i = 0
	_auto_serial = -1
	_auto_broken = 0
	_auto_report = {"mode": _auto_mode, "levels": [], "broken": 0, "ruleset": Game.ruleset.id if Game.ruleset else "", "max": _auto_max_level}
	if _auto_mode == 0: return "autoplay off"
	return "autoplay mode %d%s" % [_auto_mode, "" if main == null else " (already in game: the report counts from the current level)"]

func debug_autoplay_report() -> String:
	return JSON.stringify(_auto_report)

## 现在选哪套方案（0 起，按文件名排）。只对之后开的局生效
func debug_ruleset(index: int) -> String:
	if index < 0 or index >= Game.rulesets.size(): return "no ruleset %d (there are %d)" % [index, Game.rulesets.size()]
	var r: Ruleset = Game.rulesets[index]
	Game.select_ruleset(r)
	return "ruleset %d: %s (%s)" % [index, r.id, r.title]

## 排查用：导出包里该读到的都读到了没有。包里没被别的资源引用的文本资源是转成二进制的，
## 按目录列名字再读的那几处最容易漏（2026-11-25 方案就因此在包里一套都没读到，只剩代码里的默认值）
func debug_export_check() -> String:
	var problems: Array[String] = []
	if Game.rulesets.size() < 6:
		problems.append("方案只读到 %d 套（应有 6 套）" % Game.rulesets.size())
	for r in Game.rulesets:
		if r.title == "" or r.summary == "": problems.append("方案 %s 没读全" % r.id)
	var paths := [
		"res://resources/upgrades/combooo.tres", "res://resources/upgrades/umbrella.tres", "res://resources/upgrades/shoe.tres",
		"res://resources/upgrades/hat.tres", "res://resources/upgrades/cane.tres", "res://resources/upgrades/magnet.tres",
		"res://resources/upgrades/portal.tres", "res://resources/upgrades/chest.tres", "res://resources/upgrades/clover.tres",
		"res://resources/fishes/fish.tres", "res://resources/fishes/big_fish.tres", "res://resources/heart.tres"]
	for path in paths:
		var res = load(path)
		if res == null or not res is ObjectResource:
			problems.append("读不到 %s" % path)
	for key in Opening.NAMES:
		var stream = load("res://assets/audio/opening/open%s.wav" % key)
		if stream == null or not stream is AudioStream or stream.get_length() < 4.0:
			problems.append("读不到开场 %s 的声音" % key)
	# 设置里选的开场得是认得的；随机要三个都抽得到，不连着两次一样
	if Game.opening != "random" and Game.opening != "off" and not Opening.NAMES.has(Game.opening):
		problems.append("设置里选的开场不认识：%s" % Game.opening)
	var counts := {}
	var last := ""
	var repeats := 0
	for i in 400:
		var w := Game.pick_opening(last)
		if w == last: repeats += 1
		counts[w] = int(counts.get(w, 0)) + 1
		last = w
	if counts.size() != Opening.NAMES.size() or repeats != 0:
		problems.append("随机开场不对：抽到 %d 种，连着重复 %d 次" % [counts.size(), repeats])
	if problems.is_empty():
		return "RESULT 导出包自检：通过（%d 套方案，%d 件东西的资源，%d 段开场的声音都读到了）" % [Game.rulesets.size(), paths.size(), Opening.NAMES.size()]
	return "RESULT 导出包自检：没过，%d 处：%s" % [problems.size(), "；".join(problems)]

# ================================================================ 逐帧计时（查"不够顺滑"用）
## 每一帧花了多少毫秒都记下来（最多 30000 帧，够一分多钟）。统计见 debug_frame_stats
var _frames: Array = []
var _frames_on := true
var _opening_seen := ""        # 这一局开局真的播过哪个开场（空是没有播）。开场自己播的时侯记下来，给检查用

func _frame_log(delta: float) -> void:
	if not _frames_on or _frames.size() >= 30000: return
	_frames.append([Time.get_ticks_msec() / 1000.0, delta * 1000.0])

## 排查用：这些帧的时间都花在哪。报平均、中位数、最差的几帧，以及超过 20 毫秒（掉到 50 帧以下）、
## 超过 33 毫秒（掉到 30 帧以下）的各有多少帧，最差的十帧在什么时刻（秒，从游戏启动算）
##   call pad_adapter.gd debug_frame_stats
func debug_frame_stats() -> String:
	if _frames.is_empty(): return "还没有记录到帧"
	var ms: Array = []
	for f in _frames: ms.append(float(f[1]))
	var sorted := ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for v in ms: total += v
	var over20 := 0
	var over33 := 0
	for v in ms:
		if v > 20.0: over20 += 1
		if v > 33.0: over33 += 1
	# 最差的十帧（按毫秒挑，记下时刻）
	var worst: Array = _frames.duplicate()
	worst.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var picks := PackedStringArray()
	for i in mini(10, worst.size()):
		picks.append("%.2fs:%.0fms" % [float(worst[i][0]), float(worst[i][1])])
	return "帧计时：%d 帧，平均 %.1f 毫秒（%.0f 帧/秒），中位 %.1f，95%% 不超过 %.1f，最差 %.1f；超过 20 毫秒 %d 帧，超过 33 毫秒 %d 帧；最差的十帧 %s；帧率上限 %d" % [
		n, total / n, 1000.0 * n / maxf(total, 0.001), sorted[n / 2], sorted[int(n * 0.95)], sorted[n - 1], over20, over33, " ".join(picks), Engine.max_fps]

## 清空记录，从现在重新开始数
func debug_frame_clear() -> String:
	_frames.clear()
	return "帧计时已清空"

## 帧率上限：0 是交给垂直同步（跟着屏幕的刷新率走），60 是死限 60。开着垂直同步又限 60 帧，两者会打架
func debug_fps_cap(n: int) -> String:
	Engine.max_fps = n
	return "帧率上限 %d（0 表示不限制，交给垂直同步）" % n

## 排查用：开场动画此刻的状态——在不在播、播的哪一个、声音放出来没有、标题页的音乐压低了没有。
## 播着的时侯查一回、播完了再查一回，没过的会报出来
##   call pad_adapter.gd debug_opening_state
## 开场动画播起来的时侯调一下：记下播的是哪一个。debug_opening_state 靠它判断"这一局到底播过没有"
func note_opening_played(id: String) -> void:
	_opening_seen = id

func debug_opening_state() -> String:
	var scene := get_tree().current_scene
	var opening: Node = null
	# 按类型找开场那一层（它挂在标题页的根上）。不按名字找：设置页里也有叫"开场"的东西
	if scene != null:
		for child in scene.get_children():
			if child is Opening:
				opening = child
				break
	var voice: AudioStreamPlayer = scene.find_child("OpeningVoice", true, false) as AudioStreamPlayer if scene != null else null
	var music: AudioStreamPlayer = scene.get_node_or_null("MainTitle2") as AudioStreamPlayer if scene != null else null
	var narration: AudioStreamPlayer = scene.find_child("OpeningNarration", true, false) as AudioStreamPlayer if scene != null else null
	var problems: Array[String] = []
	var music_db := music.volume_db if music != null else 0.0
	if music == null:
		problems.append("找不到标题页的音乐（MainTitle2）")
	var playing := opening != null
	if playing:
		if voice == null or not is_instance_valid(voice) or not voice.playing:
			problems.append("开场在播，声音没放出来")
		if music != null and music_db > -6.0:
			problems.append("开场在播，标题音乐没有压低（%.1f 分贝）" % music_db)
	else:
		# 开机盖上的那块黑幕要撤：以前只有开场动画才撤它，设置里选了"不播"的话标题页一直压在黑幕底下，整个画面是黑的
		if scene != null and get_node_or_null("/root/SceneManager/BootCover") != null:
			problems.append("开机盖上的黑幕没有撤掉，标题页看不见")
		if voice != null and is_instance_valid(voice) and voice.playing and voice.volume_db > -40.0:
			problems.append("开场已经结束，声音还在响")
		if music != null and absf(music_db) > 0.5:
			problems.append("开场结束了，标题音乐没有回到原来的音量（%.1f 分贝）" % music_db)
		if narration != null and is_instance_valid(narration) and narration.playing:
			problems.append("开场已经结束，旁白还在说")
	# 硬要求：这一局得真的播过开场。设置里是"不播"才允许没播；否则一次都没播就是没过
	#（有一次类型转换写错了，开场根本没播，这个检查却因为"没在播的时候什么都不要求"连着三次报通过）
	if _opening_seen == "" and Game.opening != "off":
		problems.append("这一局没有播过开场（设置里是 %s，应该播）" % Game.opening)
	if problems.is_empty():
		var what := "没在播（这一局播过%s）" % _opening_seen if not playing else "播着%s，第 %.1f 秒" % [str(opening.variant), float(opening._elapsed)]
		var said := "" if narration == null else "；旁白%s" % ("在说" if narration.playing else "说过了")
		return "RESULT 开场状态：通过（%s；音乐 %.1f 分贝%s；设置里选的是 %s，上一次播的是 %s）" % [what, music_db, said, Game.opening, Game.opening_last]
	return "RESULT 开场状态：没过，%d 处：%s" % [problems.size(), "；".join(problems)]

## 大厅那条河（标题页才有）
##   call pad_adapter.gd debug_lobby 1 600 400     在画面上 (600, 400) 那一点荡开一圈大的
##   call pad_adapter.gd debug_lobby 2 12          河上马上凑到 12 盏灯（给 0 回到平时那样，看等了多久）
##   call pad_adapter.gd debug_lobby 0             一行状态：画面多大、几盏灯、几圈涟漪
##   call pad_adapter.gd debug_lobby 3             排查用：每一盏河灯在哪、有多淡、在避让什么
func debug_lobby(action: int, a: int = 0, b: int = 0) -> String:
	var scene := get_tree().current_scene as TitleControl
	if scene == null: return "不在标题页上"
	var river: Node = scene.lobby_river()
	if river == null: return "标题页上没有河（LobbyRiver）"
	match action:
		1:
			river.debug_ripple(Vector2(a, b), 1.0)
			return "OK 在 (%d, %d) 荡开一圈" % [a, b]
		2:
			river.debug_lamps(a)
			return "OK 河上的灯：%d 盏%s" % [a, "（硬性规定）" if a > 0 else "（回到平时那样）"]
		3:
			return "河灯：" + str(river.debug_lamps_detail())
		_:
			return "RESULT 大厅的河：" + str(river.debug_state())

## 游戏里的背景（进了游戏才有）
##   call pad_adapter.gd debug_stage 0             一行状态：哪种布局、水到哪儿到头、几盏河灯
##   call pad_adapter.gd debug_stage 1             在主角站的那个格子底下荡开一圈
func debug_stage(action: int) -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "不在游戏里"
	var stage: Node = main.get_node_or_null("StageBackdrop")
	if stage == null: return "游戏场景里没有背景（StageBackdrop）"
	if action == 1:
		stage.debug_ripple()
		return "OK 在主角脚下荡开一圈"
	return "RESULT 游戏里的背景：" + str(stage.debug_state())

## 对战的玩法（scripts/versus/）。在标题页上调：
##   call pad_adapter.gd debug_versus 2        直接开一局：抢灯 1、追影 2、夺岸 3、轮战 4、对弈 5（用第一位同伴，不经过选人页）
##   call pad_adapter.gd debug_versus 2 1      同上，但主角也交给机器人打（录预览、自动测试用）
##   call pad_adapter.gd debug_versus 0        已经在对战里：一行这一局的状况（没分出胜负时报"进行中"）
func debug_versus(n: int, autopilot: int = 0) -> String:
	var ids: Array = VersusBase.IDS
	if n <= 0:
		var main := get_node_or_null("/root/Main") as Main
		if main == null or main.versus == null: return "不在对战的局里"
		var state := "进行中" if not main.versus.over else ("赢了" if main.versus.won else "输了")
		return "RESULT 对战 %s：%s｜%s" % [VersusBase.NAMES.get(Game.versus, "?"), state, main.versus.debug_state()]
	if n > ids.size(): return "没有第 %d 个对战的玩法（一共 %d 个）" % [n, ids.size()]
	if get_tree().current_scene as TitleControl == null: return "不在标题页上"
	if Game.characters.is_empty(): return "没有角色"
	Game.versus = ids[n - 1]
	Game.versus_auto = autopilot != 0
	Game.selected_character = Game.characters[0]
	SceneManager.load_game()
	return "开了一局%s（%s）" % [VersusBase.NAMES[Game.versus], "主角交给机器人" if Game.versus_auto else "主角自己操作"]

## 这一关摆好的那一局，画成字符画
func debug_deal() -> String:
	var main := get_node_or_null("/root/Main")
	if main == null: return "not in game"
	if main.current_deal.is_empty(): return "this level has no deal (lamps are spawned as you go)"
	return BoardGen.deal_ascii(main.current_board(), main.current_deal)

func _autoplay_level_start(main: Node, label: String) -> void:
	_auto_route_i = 0
	_auto_n = 0
	_auto_bad_seen = ""
	_auto_serial = main.level_serial
	_auto_report.levels.append({"level": main.current_level_index + 1, "name": label, "missteps": [], "score0": main.score})

func _autoplay_step(delta: float) -> void:
	if _auto_mode == 0: return
	var main := get_node_or_null("/root/Main")
	if main == null or not is_instance_valid(main.character) or main.tutorial == null: return
	if main.final_score_control.visible:
		var done: bool = main.final_score_control.completed.visible and not main.is_endless()
		_autoplay_finish("completed" if done else "game over")
		return
	if main.tutorial.card_open() or main.character.is_jumping: return
	if main.grid.tiles.is_empty(): return
	if main.level_serial != _auto_serial:
		_autoplay_level_start(main, main.level_label.text)
		_auto_wait = 0.2 if _auto_eager else 1.5
		_auto_t0 = main.get_time()
		_auto_waited = false
		return
	if main.current_level_index + 1 > _auto_max_level and _auto_max_level != 999:
		_autoplay_finish("reached level limit %d" % _auto_max_level)
		return
	_auto_wait -= delta
	if _auto_wait > 0.0: return
	# 这一关还在载入（灯一件一件往下落，要一秒多；机器忙的时侯更久）：等它载入完再动手。
	# 不等的话，机器人会在灯只摆了一半的时侯就跳出去捡，之后照着路线走就对不上了
	if not main.level_ready:
		if not _auto_waited:
			_auto_waited = true
			print("AUTOPLAY_WAIT level %d：换关后 %.1f 秒灯还没摆完（已经摆上 %d 件），等这一关载入完" % [
				main.current_level_index + 1, main.get_time() - _auto_t0, _placed_count(main)])
		_auto_wait = 0.1
		return
	if _auto_t0 > 0.0:
		print("AUTOPLAY_LOAD level %d：换关后 %.1f 秒机器人动手%s" % [
			main.current_level_index + 1, main.get_time() - _auto_t0, "（灯摆得慢，等过它）" if _auto_waited else ""])
		_auto_t0 = 0.0
		_auto_waited = false
	# 每一步之前查一遍棋盘上的登记对不对（捞网挪过灯以后最容易出错）
	var bad := _board_check(main)
	if bad != "" and bad != _auto_bad_seen:
		_auto_bad_seen = bad
		_auto_report["board_bad"] = int(_auto_report.get("board_bad", 0)) + 1
		print("AUTOPLAY_BOARD_BAD level %d 第 %d 步之后：%s" % [main.current_level_index + 1, _auto_n, bad])
	_auto_wait = 0.4
	var tile: Tile = null
	var route_tile := false
	if _auto_mode == 1 and not main.current_deal.is_empty():
		var route: Array = main.current_deal.route
		# 路线上还有东西的下一格就是下一跳（被水车卷走的灯那一格跳过去不踩）
		while _auto_route_i < route.size():
			var t: Tile = main.tile_at_cell(route[_auto_route_i])
			if t != null and t.object != null:
				tile = t
				break
			_auto_route_i += 1
		if tile != null:
			route_tile = true
			_auto_route_i += 1
			if not tile.is_available:
				# 引擎说这一跳跳不到：摆棋的模型和引擎对不上了，记下来，改用贪心走法接着走
				_auto_broken += 1
				_auto_report.broken = _auto_broken
				print("AUTOPLAY_BROKEN level %d step %d tile %s combo %.0f moves %d | 人在 %s，%s | %s" % [
					main.current_level_index + 1, _auto_route_i, route[_auto_route_i - 1], main.combo, main.moves_left,
					main.to_cell(main.character.global_position), "正在跳" if main.character.is_jumping else "站着", _why_not(main, tile)])
				tile = null
	if tile == null:
		var sim := _live_sim(main)
		var cell := sim.next_move()
		if cell != sim.pos: tile = main.tile_at_cell(cell)
	var levels: Array = _auto_report.levels
	if tile == null:
		_auto_wait = 1.0          # 没处可去：多半是在等脆格长回来
		return
	var from: Vector2i = main.to_cell(main.character.global_position)
	var to: Vector2i = main.to_cell(tile.global_position)
	main.character.move_to(tile)
	if main.character.target_tile != tile:
		# 没起跳（被同一拍的别的输入抢了先，或者步数不够）：路线上的这一步不算走过，下一拍重来
		if route_tile: _auto_route_i -= 1
		_auto_wait = 0.2
		return
	_auto_n += 1
	if _auto_trace:
		print("AUTOPLAY_STEP level %d 第 %d 步 %s %s → %s combo %d moves %d" % [
			main.current_level_index + 1, _auto_n, "路线" if route_tile else "贪心", from, to, main.combo, main.moves_left])
	if levels.size() > 0:
		var rec: Dictionary = levels[levels.size() - 1]
		if int(rec.missteps.size()) == 0 or int(rec.missteps.back()) != main.level_missteps:
			rec.missteps.append(main.level_missteps)

## 棋盘上现在摆着几件东西（灯和道具，不算水车）
func _placed_count(main: Node) -> int:
	var n := 0
	for t in main.grid.tiles.values():
		if t.object != null and t.object is Fish and not t.object.is_portal: n += 1
	return n

## 这一格现在为什么跳不到（"照着路线走却跳不到"的记录里带上，省得再猜）
func _why_not(main: Node, tile: Tile) -> String:
	var why: Array[String] = []
	if not tile.is_landable(): why.append("这一格落不上去" if tile.is_blocked() else "这一格碎了")
	if tile.object != null and not tile.object.is_available(): why.append("上面的东西还不能捡")
	if tile == main.character.target_tile: why.append("人就站在这一格")
	var here := Vector2(main.character.global_position.x, main.character.global_position.z)
	why.append("离 %.2f 格、能跳 %.2f 格" % [Vector2(tile.global_position.x, tile.global_position.z).distance_to(here) / main.grid.tile_size.x, main._reach_now()])
	if main.moves_left <= 0 and not main.step_is_free(tile): why.append("没步数了")
	return "；".join(why)

func _autoplay_finish(why: String) -> void:
	var main := get_node_or_null("/root/Main")
	_auto_mode = 0
	_auto_report["result"] = why
	if main != null:
		_auto_report["score"] = main.score
		_auto_report["reached"] = main.current_level_index + 1
		_auto_report["retries"] = main.level_retries
	print("AUTOPLAY_RESULT " + JSON.stringify(_auto_report))

## 把现在的局面整理成 BoardSim 认的样子（贪心机器人靠它想下一跳）。钓竿、捞网、蒸笼这几种它不会用，
## 就当成了差不多的别的东西：都只是估个下限，不求准
func _live_sim(main: Node) -> BoardSim:
	var sim := BoardSim.new()
	var board: Dictionary = main.current_board()
	sim.cells = {}
	for cell in board.cells:
		var t: Tile = main.tile_at_cell(cell)
		sim.cells[cell] = BoardGen.BLOCKED if (t != null and t.is_broken()) else board.cells[cell]
	sim.portal = board.portal
	sim.pos = board.start
	sim.rp = main.deal_options(1).reach
	sim.moves = main.moves_left
	sim.combo = float(main.combo)
	sim.shoe = main.level_reach_bonus
	sim.dash = main.temporary_mov_distance
	sim.shields = main.shields
	sim.need = main.fish_before_end_portal
	sim.got = main.current_fish_count
	sim.portal_free = main.ruleset != null and main.ruleset.portal_free
	sim.spawns_lamps = not main.lamps_dealt()
	var last: Tile = main.grid.get_tile(main.grid.world_to_grid_position(main.character.last_position))
	sim.back = main.to_cell(last.global_position) if last else Vector2i(-99, -99)
	for cell in board.cells:
		var t: Tile = main.tile_at_cell(cell)
		if t == null or t.object == null: continue
		var fish: Fish = t.object as Fish
		if fish == null or fish.is_portal or fish.resource == null: continue
		sim.things[cell] = _kind_of(fish)
	return sim

func _kind_of(fish: Fish) -> int:
	if fish.is_fish:
		return BoardGen.Thing.BIG if fish.resource.score > 1.0 else BoardGen.Thing.LAMP
	match fish.resource.effect:
		ObjectResource.ObjectEffect.TemporaryMoveDistance: return BoardGen.Thing.UMBRELLA
		ObjectResource.ObjectEffect.ReachUp: return BoardGen.Thing.SHOE
		ObjectResource.ObjectEffect.GainCombo: return BoardGen.Thing.LOTUS
		ObjectResource.ObjectEffect.Shield: return BoardGen.Thing.HAT
		ObjectResource.ObjectEffect.AddMoves: return BoardGen.Thing.BOX
		ObjectResource.ObjectEffect.CollectNear, ObjectResource.ObjectEffect.CollectFarestFishes: return BoardGen.Thing.WHEEL
		ObjectResource.ObjectEffect.RegainMovesLeft: return BoardGen.Thing.BOX
	return BoardGen.Thing.COIN

# ================================================================ 录像 / 开场动画
## 把画面按真实时间存下来（每秒 fps 张），事后拼成视频看。按时间而不按帧数：游戏刚启动的那一两秒帧率不满 60，
## 按帧数存的话拼出来的视频开头会比真实的慢
##   call pad_adapter.gd debug_record 4 20 opening      录 4 秒、每秒 20 张，存成 <目录>/opening_0000.jpg …
##   环境变量 SW_REC 是存的目录（默认 /tmp/sw_rec）；SW_AUTOREC="秒数,每秒几张,名字" 设了的话，游戏一启动就自动开始录（录的是真正的开机画面）
##   call pad_adapter.gd debug_opening 1               在标题页上立刻重播一遍开场动画（1 到 3 是 A、B、D；不给或者给 0 就按设置里的来）
var _rec_left := 0.0
var _rec_fps := 20.0
var _rec_acc := 0.0
var _rec_name := "rec"
var _rec_frame := 0
var _rec_dir := "/tmp/sw_rec"

func _record_boot() -> void:
	if OS.get_environment("SW_REC") != "": _rec_dir = OS.get_environment("SW_REC")
	var spec := OS.get_environment("SW_AUTOREC")
	if spec == "": return
	var parts := spec.split(",")
	debug_record(float(parts[0]), float(parts[1]) if parts.size() > 1 else 20.0, parts[2] if parts.size() > 2 else "boot")

func debug_record(seconds: float, fps: float = 20.0, name: String = "rec") -> String:
	if OS.get_environment("SW_REC") != "": _rec_dir = OS.get_environment("SW_REC")
	DirAccess.make_dir_recursive_absolute(_rec_dir)
	_rec_left = seconds
	_rec_fps = maxf(fps, 1.0)
	_rec_acc = 1.0          # 第一帧马上存
	_rec_name = name
	_rec_frame = 0
	return "recording %.1f s at %.0f frames/s to %s/%s_*.jpg" % [seconds, _rec_fps, _rec_dir, name]

func _record_tick(delta: float) -> void:
	if _rec_left <= 0.0: return
	_rec_left -= delta
	_rec_acc += delta
	if _rec_acc < 1.0 / _rec_fps: return
	_rec_acc = fmod(_rec_acc, 1.0 / _rec_fps)
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/%s_%04d.jpg" % [_rec_dir, _rec_name, _rec_frame], 0.88)
	_rec_frame += 1
	if _rec_left <= 0.0: print("RECORD_DONE %s %d" % [_rec_name, _rec_frame])

func debug_opening(which: int = 0) -> String:
	var scene := get_tree().current_scene
	if scene == null: return "no current scene"
	for old in scene.get_children():
		if old is Opening:
			old._skip()
			break
	# 标题页场景的根节点就是 TitleControl（见 scene_manager 里同样的说明）
	var tc := scene as TitleControl
	if tc == null: return "not on the title screen"
	# 遥控的参数只能是整数：1 起按 Opening.NAMES 的顺序（现在是 A、B、D），0 是设置里的那一个
	var ids: Array = Opening.NAMES.keys()
	if which > 0 and which > ids.size(): return "没有第 %d 个开场（一共 %d 个）" % [which, ids.size()]
	var id: String = Game.opening if which <= 0 else str(ids[which - 1])
	if not Opening.NAMES.has(id): return "no such opening '%s'" % id
	var opening := Opening.new()
	scene.add_child(opening)
	opening.play(id, tc)
	return "opening %s (%s) playing" % [id, Opening.NAMES[id]]

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
	Engine.max_fps = 60
	_add_pad_events()
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
	if pad_connected:
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
			# 第三个参数以后的都是整数参数
			var args: Array = []
			for extra in parts.slice(3):
				args.append(int(extra))
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
	main.tutorial.show_card(not Game.tutorial_seen.has("rules"))
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
	return "label='%s' index=%d mode=%d tiles=%d types=%s available=%d broken=%d moves=%d combo=%d fish=%d/%d credits=%.1f pos=(%.1f,%.1f) score=%d records=%s" % [
		main.level_label.text, main.current_level_index, Game.game_mode, main.grid.tiles.size(), counts, available, broken,
		main.moves_left, main.combo, main.current_fish_count, main.fish_before_end_portal, main.credits, pos.x, pos.y,
		main.score, Game.best_records]

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

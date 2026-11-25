class_name SettingsControl extends VBoxContainer

const FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")

@onready var master_slider: HSlider = $Master/MasterSlider
@onready var music_slider: HSlider = $Music/MusicSlider
@onready var sfx_slider: HSlider = $SFX/SFXSlider
@onready var visuals_checkbox: CheckBox = $Visuals/VisualsCheckbox


func _ready() -> void:
	load_values()
	master_slider.value_changed.connect(func(value):
		Game.master_value = value
		Game.save()
		update()
	)
	music_slider.value_changed.connect(func(value):
		Game.music_value = value
		Game.save()
		update()
	)
	sfx_slider.value_changed.connect(func(value):
		Game.sfx_value = value
		Game.save()
		update()
	)
	visuals_checkbox.toggled.connect(func(value):
		Game.visuals_value = value
		Game.save()
	)
	await Game.loaded
	load_values()
	_add_opening_row()

## 最后加一行：开场动画选哪一个（不写进场景文件，代码搭的和别的行一个样子）
func _add_opening_row() -> void:
	var music_label: Label = $Music/Label
	var row := HBoxContainer.new()
	row.name = "OpeningRow"          # 别叫 Opening：那是开场动画那一层的名字
	row.custom_minimum_size = Vector2(0, 46)
	row.add_theme_constant_override("separation", 50)
	var label := Label.new()
	label.text = "开场"
	label.material = music_label.material
	label.custom_minimum_size = Vector2(100, 46)
	label.label_settings = music_label.label_settings
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var opt := OptionButton.new()
	opt.name = "OpeningOption"
	opt.custom_minimum_size = Vector2(200, 46)
	opt.theme = music_slider.theme
	opt.add_theme_font_override("font", FONT)
	opt.add_theme_font_size_override("font_size", 30)
	# 点开的那个菜单也用游戏自己的字体（不然是引擎默认的小字）
	var menu: PopupMenu = opt.get_popup()
	menu.add_theme_font_override("font", FONT)
	menu.add_theme_font_size_override("font_size", 28)
	var current := 0
	var i := 0
	# 第一项是每次开机随机换一个（默认）；然后是三个方案；最后是不播
	var options: Array = [["random", "每次随机"]]
	for key in Opening.NAMES:
		options.append([key, Opening.NAMES[key]])
	options.append(["off", "不播"])
	for o in options:
		opt.add_item(o[1])
		opt.set_item_metadata(i, o[0])
		if o[0] == Game.opening: current = i
		i += 1
	opt.select(current)
	opt.item_selected.connect(func(index: int):
		Game.select_opening(str(opt.get_item_metadata(index)))
	)
	row.add_child(opt)
	add_child(row)
	
## 排查用：设置页开着的时候，把它上面的东西和标题页的标志、返回按钮逐个量一遍，看有没有互相重叠、出画面
##   call settings_control.gd debug_settings_layout
func debug_settings_layout() -> String:
	if not visible:
		return "设置页没开着"
	var items: Array = []
	for row in get_children():
		if not row is Control: continue
		if row is Label:
			items.append(["标题的字", Tutorial.text_rect(row), false])
			continue
		for c in row.get_children():
			if c is Label: items.append(["%s 的字" % row.name, Tutorial.text_rect(c), false])
			elif c is Control: items.append(["%s 的控件" % row.name, Rect2(c.global_position, c.size), false])
	# 标志向标题页要（TitleControl.logo_image()），不在这儿写节点路径。
	# 设置页在 根节点/CanvasLayer/TitleControl/SettingsContainer 下面，往上三层才是挂着 TitleControl 脚本的根节点
	var title_screen: Node = get_parent().get_parent().get_parent()
	var logo: CanvasItem = title_screen.logo_image() if title_screen != null and title_screen.has_method("logo_image") else null
	if logo is TextureRect:
		items.append(["标志", _opaque_rect(logo), false])
	var back: Button = get_parent().get_node_or_null("SettingsReturnButton")
	if back != null:
		items.append(["返回", Rect2(back.global_position, back.size), false])
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var out := PackedStringArray()
	var bad := 0
	for it in items:
		# 返回按钮本来就是贴着画面底边摆的，容 1 像素
		if not view.grow(1.0).encloses(it[1]):
			bad += 1
			out.append("× %s 出了画面：%s" % [it[0], it[1]])
	for i in items.size():
		for j in range(i + 1, items.size()):
			if items[i][1].intersects(items[j][1]):
				bad += 1
				out.append("× 重叠：%s 和 %s" % [items[i][0], items[j][0]])
	for it in items:
		var r: Rect2 = it[1]
		out.append("%s  x %.0f..%.0f  y %.0f..%.0f" % [it[0], r.position.x, r.end.x, r.position.y, r.end.y])
	out.append("RESULT 设置页版面：%s（%d 项）" % ["通过" if bad == 0 else "没过，%d 处" % bad, items.size()])
	return "\n".join(out)

## 贴图上有图形的那一块在屏幕上的位置（标志四周留白很大，按整个贴图框算会冤枉人）
func _opaque_rect(r: TextureRect) -> Rect2:
	var img: Image = r.texture.get_image()
	if img.is_compressed(): img.decompress()
	var used: Rect2i = img.get_used_rect()
	# 按比例缩放、居中（和场景里标的 stretch_mode = 5 一个意思）
	var k: float = minf(r.size.x / img.get_width(), r.size.y / img.get_height())
	var drawn := Vector2(img.get_width(), img.get_height()) * k
	return Rect2(r.global_position + (r.size - drawn) / 2.0 + Vector2(used.position) * k, Vector2(used.size) * k)

func load_values():
	master_slider.value = Game.master_value
	music_slider.value = Game.music_value
	sfx_slider.value = Game.sfx_value
	visuals_checkbox.button_pressed = Game.visuals_value
	
func update():
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Master"), Game.master_value)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Music"), Game.music_value)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("SFX"), Game.sfx_value)
	

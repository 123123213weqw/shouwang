extends SceneTree
# 把工程的图标 icon.svg 转成 PNG（掌机菜单项的图标要用图片文件，不能用 SVG）。
# 仓库里存着一份转好的（tools/handheld/icon.png，掌机菜单项用）；改了 icon.svg 就在 V100 上重转一次再拷回去。
# 在 V100 上跑: Godot --headless --path <工程> --script res://tools/icon_to_png.gd -- <输出的 PNG 路径>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tex: Texture2D = load("res://icon.svg")
	if tex == null:
		push_error("读不到 res://icon.svg")
		quit(1)
		return
	var img := tex.get_image()
	var path: String = args[0] if args.size() > 0 else "/tmp/shouwang_icon.png"
	img.save_png(path)
	print("ICON_PNG ", path, " ", img.get_width(), "x", img.get_height())
	quit()

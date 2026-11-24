#!/bin/bash
# 把 tools/art/ 下所有画图脚本重跑一遍，把工程里的图重新生成出来（每张图都是由脚本画的，不手工修 PNG）。
# 每个脚本不带参数就把自己的图写进工程并自检（画完必须自检，见 doodle.py 开头的几条规矩）；
# 想顺带看预览图，单独跑那个脚本并给一个预览图的路径当参数。
# 每个脚本跑完都数一数它有没有真的重写文件：一个都没写的算失败（免得脚本悄悄地什么都没画还报成功）。
# 只用本机的 Python（Pillow、numpy），不跑 Godot，也不需要原版工程的素材。
# 用法: tools/art/regen_all.sh          在工程根目录下运行；日志在 /tmp/shouwang_art_logs/
cd "$(dirname "$0")/../.." || exit 1
mkdir -p /tmp/shouwang_art_logs
MARK=/tmp/shouwang_art_logs/.marker
fail=0
for s in tools/art/*.py; do
	n=$(basename "$s" .py)
	# 工具库、只管看图的自检工具、还有要原版素材才跑的 bake_originals.py：不画图，跳过
	case "$n" in doodle|review|a1_kit|a2_common|figure|bake_originals) continue ;; esac
	touch "$MARK"; sleep 1
	if ! python3 -I "$s" >/tmp/shouwang_art_logs/$n.log 2>&1; then
		echo "失败: $n（看 /tmp/shouwang_art_logs/$n.log）"; tail -n 3 /tmp/shouwang_art_logs/$n.log | cut -c1-170; fail=1; continue
	fi
	wrote=$(find assets icon.svg \( -name '*.png' -o -name '*.svg' \) -newer "$MARK" | wc -l | tr -d ' ')
	if [ "$wrote" = 0 ]; then
		echo "失败: $n 跑完了一个文件都没写（看 /tmp/shouwang_art_logs/$n.log）"; fail=1; continue
	fi
	if grep -q "不合格\|\[错误\]\|Traceback" /tmp/shouwang_art_logs/$n.log; then
		echo "自检没过: $n"; grep "不合格\|\[错误\]\|Traceback" /tmp/shouwang_art_logs/$n.log | head -n 5 | cut -c1-170; fail=1
	else
		echo "  $n：重写了 $wrote 个文件，自检通过"
	fi
done
rm -f "$MARK"
[ "$fail" = 0 ] && echo "全部画图脚本都跑完了" || echo "有脚本失败"
exit $fail

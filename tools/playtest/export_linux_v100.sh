#!/bin/bash
# 在 V100 上把工程导出成 Linux x86_64 的独立可执行文件（给掌机用）：资源和脚本都打包在这一个文件里。
# 第一次运行会下载 Godot 的导出模板（约 1.3 GB，来自 GitHub 上的官方发布页），和同一发布页上的
# SHA512-SUMS.txt 核对通过后才安装。
# 用法: export_linux_v100.sh <工程目录> <输出文件>
# 例:   export_linux_v100.sh /home/wzu/shouwang-agents/a7/project /home/wzu/shouwang-agents/a7/shouwang.x86_64
set -u
PROJECT="$1"; OUT="$2"
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
VER=4.7.2-stable        # 发布页的标签，URL 里用横线
VERDIR=4.7.2.stable     # Godot 期望的模板目录名，用点
TPL_DIR=~/.local/share/godot/export_templates/$VERDIR
DL=~/shouwang-build/templates
BASE=https://github.com/godotengine/godot/releases/download/$VER
NAME=Godot_v${VER}_export_templates.tpz
SUMS=SHA512-SUMS.txt
mkdir -p "$DL" "$(dirname "$OUT")"

# 校验清单每行的格式是 "<sha512>  <文件名>"，按完整文件名找
expected() { grep -a "  $NAME\$" "$DL/$SUMS" | awk '{print $1}' | head -n 1; }
actual() { sha512sum "$DL/$NAME" | awk '{print $1}'; }
verified() { [ -s "$DL/$NAME" ] && [ -n "$(expected)" ] && [ "$(expected)" = "$(actual)" ]; }

if [ ! -f "$TPL_DIR/linux_release.x86_64" ]; then
	cd "$DL" || exit 1
	if ! verified; then
		if [ ! -s "$SUMS" ]; then
			echo "下载 $SUMS ..."
			curl -fsSL --retry 8 --retry-delay 5 -o "$SUMS" "$BASE/$SUMS" || { echo "下载失败: $SUMS"; exit 1; }
		fi
		[ -n "$(expected)" ] || { echo "$SUMS 里找不到 $NAME 的校验值"; exit 1; }
		if [ -s "$NAME" ] && [ "$(actual)" = "$(expected)" ]; then
			echo "导出模板已经下载过且校验通过，跳过下载"
		else
			echo "下载 $NAME ..."
			curl -fsSL -C - --retry 8 --retry-delay 5 -o "$NAME" "$BASE/$NAME" || { echo "下载失败: $NAME"; exit 1; }
		fi
	fi
	if ! verified; then
		echo "导出模板校验失败，不安装："
		echo "  校验清单里写的是: $(expected)"
		echo "  实际算出来的是:   $(actual)"
		exit 1
	fi
	mkdir -p "$TPL_DIR"
	unzip -o -q -j "$NAME" 'templates/*' -d "$TPL_DIR" || { echo "解压失败"; exit 1; }
	echo "导出模板已安装到 $TPL_DIR（$(ls "$TPL_DIR" | wc -l) 个文件）"
fi

# 导出前先把资源导入一遍，免得带着过期的导入缓存打包
"$G" --headless --path "$PROJECT" --import > /tmp/sw_export_import.log 2>&1
rm -f "$OUT"
echo "导出 Linux 包到 $OUT ..."
"$G" --headless --path "$PROJECT" --export-release "Linux" "$OUT" > /tmp/sw_export.log 2>&1
CODE=$?
echo "导出退出码 $CODE；日志: ERROR=$(grep -c '^ERROR' /tmp/sw_export.log) SCRIPT ERROR=$(grep -c 'SCRIPT ERROR' /tmp/sw_export.log) WARNING=$(grep -c '^WARNING' /tmp/sw_export.log)"
sed "s/\x1b\[[0-9;]*m//g" /tmp/sw_export.log | grep -A3 "^ERROR\|SCRIPT ERROR" | head -n 24 | cut -c1-200
sed "s/\x1b\[[0-9;]*m//g" /tmp/sw_export.log | grep "^WARNING" | sed 's/0x[0-9a-f]*//g' | cut -c1-170 | sort | uniq -c | sort -rn | head -n 8
if [ -s "$OUT" ]; then
	ls -la "$OUT" | awk '{print "产物: " $5 " 字节  " $9}'
	file "$OUT" | cut -c1-160
else
	echo "没有生成输出文件"
	exit 1
fi
exit $CODE

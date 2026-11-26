#!/bin/bash
# 按一个"步骤文件"操作游戏并截图：启动 → 逐步执行 → 停掉。
# 用法: drive_v100.sh <工程目录> <步骤文件> <截图前缀>
# 步骤文件一行一步（# 开头的是注释）：
#   sleep 5                  等几秒
#   ui                       列出屏幕上的按钮：BTN [x,y 宽x高] 文字 <节点名>
#   click_btn 节点名          点这个按钮的正中（按 <节点名> 找，例如 PlayButton、LeaderboardButton）
#   click x y                点某个坐标
#   move x y                 把光标移到某个坐标（触发悬停）
#   key A                    按一下某个键（key Escape、key Space、key D ……）
#   call 脚本名 方法 参数      调游戏里的方法，例如 call pad_adapter.gd debug_spawn 3
#   spawn 资源路径 [次数]      把指定的那样东西放到棋盘上，例如 spawn res://resources/heart.tres 3（不清场）
#   state                    当前局面的一行摘要
#   scene                    当前场景
#   size                     画面尺寸和当前帧数
#   texts                    屏幕上的文字
#   snap 名字                截图：<前缀>_<名字>.jpg（半分辨率）和 .png（全分辨率）
#   burst 名字 [次数]         连拍（默认 10 张 = 着色器抖动的 10 个相位各一张全分辨率的图）：<前缀>_<名字>_P0.png … _P9.png
#                             某个相位一直没渲染出来（机器太慢）的话最多等 45 秒，少几张会照实报出来
#   rects                    量画面上每张贴图在屏幕上的位置、大小和 zoom（一个纹理像素 = 几个屏幕像素）
# 截图写到 $SW_RUN/shots/。环境变量同 launch_v100.sh。
PROJECT="${1%/}"; STEPS="$2"; P="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${SW_RUN:-$HOME/shouwang-run}"; SNAP="${SW_SNAP:-/tmp/sw_snap}"; LOG="${SW_LOG:-/tmp/shouwang_run.log}"
mkdir -p "$RUN/shots"
RC="bash $HERE/rc.sh"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
PORT="${SW_DEBUG_PORT:-9878}"
up=0
for i in $(seq 1 500); do
	(echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && { up=1; break; }
	# 脚本有编译错误的话端口永远起不来，不用干等
	grep -a -q "is not compiling\|Failed to create an autoload" "$LOG" 2>/dev/null && break
	sleep 1
done
if [ "$up" != 1 ]; then
	echo "500 秒内调试端口没有起来。日志末尾："; tail -n 12 "$LOG" | cut -c1-200
	bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1
fi
printf '渲染方式：%s\n' "$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -a -m1 'Using Device' | sed 's/.*- Using/Using/' | cut -c1-70)"
echo "调试端口在第 $i 秒起来"; sleep "${SW_BOOT_WAIT:-6}"
if grep -q "llvmpipe" "$LOG" && [ "${SW_RENDERER:-gl}" = nvidia ]; then
	echo "警告：这个实例没能用上显卡，落到软件渲染上了（启动和帧率都会差很多）"
fi
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-5}" $RC "$@" 2>&1 | grep -v '^$'; }
OUT="$RUN/shots/${P}_steps.out"       # 每一步的输出留一份，收尾时在它里面找"没过"
run_steps() {
while IFS= read -r line || [ -n "$line" ]; do
	line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	case "$line" in ""|\#*) continue ;; esac
	set -- $line
	cmd="$1"; shift
	case "$cmd" in
		sleep) sleep "$1" ;;
		ui) RC_READ=8 $RC ui ;;
		texts) RC_READ=8 $RC texts ;;
		scene) rcc scene ;;
		size) rcc size ;;
		state) rcc "call pad_adapter.gd debug_state" | sed 's/OK called debug_state -> //' ;;
		click_btn)
			target=$(RC_READ=8 $RC ui | grep -F "<$1>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3 / 2), int($2 + $4 / 2)}')
			if [ -n "$target" ]; then RC_WAIT=0.3 $RC "click $target" >/dev/null; else echo "找不到按钮 $1"; fi ;;
		click) RC_WAIT=0.3 $RC "click $1 $2" >/dev/null ;;
		move) RC_WAIT=0.3 RC_READ=2 $RC "move $1 $2" >/dev/null ;;
		rects) RC_WAIT=0.5 RC_READ=6 $RC "call pad_adapter.gd debug_rects" | sed 's/^OK called debug_rects -> //' ;;
		burst)
			n="${2:-10}"
			rm -f "${SNAP}"_P*.png
			RC_WAIT=0.3 RC_READ=2 $RC "call pad_adapter.gd debug_burst $n" >/dev/null
			for t in $(seq 1 36); do
				st=$(RC_WAIT=0.2 RC_READ=1 $RC "call pad_adapter.gd debug_burst_status" 2>/dev/null | tr -d '\n')
				case "$st" in *done*) break ;; esac
				sleep 0.5
			done
			sleep 3
			for i in $(seq 0 $((n - 1))); do cp "${SNAP}_P$i.png" "$RUN/shots/${P}_$1_P$i.png" 2>/dev/null; done
			echo "连拍 $1：取到 $(ls "$RUN/shots/${P}_$1_P"*.png 2>/dev/null | wc -l) 张（应为 $n；$st）" ;;
		key) RC_WAIT=0.3 $RC "key $1" >/dev/null ;;
		call) rcc "call $*" ;;
		spawn) rcc "spawn $*" ;;
		snap)
			RC_WAIT=0.3 RC_READ=8 $RC snapshot >/dev/null 2>&1; $RC full >/dev/null 2>&1
			cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg" 2>/dev/null; cp "$SNAP.png" "$RUN/shots/${P}_$1.png" 2>/dev/null
			echo "截图 $1" ;;
		*) echo "不认识的步骤: $cmd" ;;
	esac
done < "$STEPS"
}
run_steps | tee "$OUT"
echo "== 日志里的报错: SCRIPT ERROR=$(grep -c 'SCRIPT ERROR' "$LOG")   ERROR=$(grep -c '^ERROR' "$LOG")"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep "SPAWNABLE" | head -n 2 | cut -c1-1200
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A4 "SCRIPT ERROR\|^ERROR" | head -n 24 | cut -c1-220
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
# 哪一步没过，退出码就不是 0：日志里有报错；或者某一步调的检查报了"没过"（卡片版面、棋盘出框这些）。
# 屏幕上的文字里本来就有"一关没过"这种话，所以只认 RESULT 开头的结论和方括号里的那一种
fail=0
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG")
[ "$errs" = 0 ] && [ "$others" = 0 ] || { echo "[没过] 日志里有报错"; fail=1; }
grep -a -q -E "RESULT [^：]*：没过|^\[没过\]" "$OUT" && { echo "[没过] 有一步的检查没过："; grep -a -E "RESULT [^：]*：没过|^\[没过\]" "$OUT" | sort | uniq -c | head -n 6; fail=1; }
grep -a -q "^不认识的步骤" "$OUT" && { echo "[没过] 步骤文件里有不认识的步骤"; fail=1; }
[ "$fail" = 0 ] && echo "RESULT 界面操作（$P）：通过" || echo "RESULT 界面操作（$P）：没过"
exit $fail

#!/bin/bash
# 把主线 12 关各载入一遍：量棋盘在画面里的范围（整张棋盘都要在画面里），每关截一张图。
# 默认用掌机屏幕的比例（16:10，1152x720）。
# 用法: aspect_v100.sh <工程目录> [截图前缀，默认 a10] [分辨率，默认 1152x720]
# 环境变量同 launch_v100.sh（几个实例同时跑的时候各设各的）。截图写到 $SW_RUN/shots/，文件名以 <前缀>_ 开头。
PROJECT="$1"; P="${2:-a10}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export SW_RES="${3:-1152x720}"   # 掌机的逻辑分辨率是 1280x800（屏幕 2560x1600 的 2 倍缩放）
RUN="${SW_RUN:-$HOME/shouwang-run}"; SNAP="${SW_SNAP:-/tmp/sw_snap}"; LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
mkdir -p "$RUN/shots"
RC="bash $HERE/rc.sh"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
for i in $(seq 1 300); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 1; done
sleep 8
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-4}" $RC "$@" 2>&1 | grep -v '^$'; }
btn() { RC_READ=8 $RC "ui" 2>/dev/null | grep -F "<$1>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}'; }
state() { rcc "call pad_adapter.gd debug_state" | sed 's/OK called debug_state -> //'; }
brief() { echo "$1" | grep -o "label='[^']*'\|index=[0-9]*\|tiles=[0-9]*\|types={[^}]*}\|available=[0-9]*\|moves=[0-9]*" | tr '\n' ' '; }
extent() { rcc "call pad_adapter.gd debug_board_screen" | sed 's/OK called debug_board_screen -> //'; }
snap() {
	RC_WAIT=0.3 RC_READ=6 $RC snapshot >/dev/null 2>&1
	RC_WAIT=0.3 RC_READ=8 $RC full >/dev/null 2>&1
	cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg"; cp "$SNAP.png" "$RUN/shots/${P}_$1.png"
}
fail=0

echo "启动后: $(rcc "size" | head -n 1)"
snap 00_title
target=$(btn PlayButton)
[ -n "$target" ] || { echo "标题页上找不到 PlayButton 按钮，停在这里"; RC_READ=6 $RC "ui" 2>&1 | head -n 12; bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1; }
set -- $target
RC_WAIT=0.3 $RC "click $1 $2" >/dev/null 2>&1
sleep 6
rcc "call pad_adapter.gd debug_unlock_all" >/dev/null
for try in 1 2 3 4; do
	rcc "call pad_adapter.gd debug_pick_character 0" >/dev/null
	sleep 10
	scene=$(rcc "scene" | grep "^OK scene" | cut -c1-100)
	case "$scene" in *main.tscn*) break ;; esac
done
echo "进游戏: $scene"
dismiss=$(btn "<TutorialCloseButton>")      # 第一次进游戏会先弹"玩法"卡片（整局暂停）：有就点掉
[ -n "$dismiss" ] && { RC_WAIT=0.3 $RC "click $dismiss" >/dev/null 2>&1; sleep 1; echo "点掉了第一次的玩法卡片"; }
sleep 8
for lvl in 1 2 3 4 5 6 7 8 9 10 11 12; do
	if [ "$lvl" != 1 ]; then rcc "call pad_adapter.gd debug_goto_level $lvl" >/dev/null; sleep 7; fi
	line="$(brief "$(state)")"
	ext="$(extent)"
	echo "第 $lvl 关: $line"
	echo "        $ext"
	echo "$ext" | grep -q "放得下=true" || { echo "        [没过] 棋盘没有整个落在画面里"; fail=1; }
	snap "L$lvl"
done
echo "== 运行日志里的报错 =="
errs=$(grep -c 'SCRIPT ERROR' "$LOG")
others=$(grep -c '^ERROR' "$LOG")
echo "SCRIPT ERROR: $errs   ERROR: $others"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A4 "SCRIPT ERROR\|^ERROR" | head -n 16 | cut -c1-200
[ "$errs" = 0 ] && [ "$others" = 0 ] || fail=1
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$fail" = 0 ] && echo "RESULT 画面比例（$SW_RES）：通过" || echo "RESULT 画面比例（$SW_RES）：没过"
exit $fail

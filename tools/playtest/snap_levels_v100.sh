#!/bin/bash
# 进入主线后直接跳到指定的几关，各截一张图（半分辨率的 jpg 和全分辨率的 png）并量一次棋盘的范围。
# 用法: snap_levels_v100.sh <工程目录> <截图前缀> <分辨率> <关卡号>...
# 例:   snap_levels_v100.sh /home/wzu/shouwang-agents/a7/project a10 1152x720 8 9 10 12
# 进游戏之前先拍一张标题页。截图写到 $SW_RUN/shots/，文件名是 <前缀>_00_title、<前缀>_L<关卡号>。
# 环境变量同 launch_v100.sh（几个实例同时跑的时候各设各的）。
PROJECT="${1%/}"; P="$2"; export SW_RES="$3"; shift 3
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${SW_RUN:-$HOME/shouwang-run}"; SNAP="${SW_SNAP:-/tmp/sw_snap}"; LOG="${SW_LOG:-/tmp/shouwang_run.log}"
mkdir -p "$RUN/shots"
RC="bash $HERE/rc.sh"
n=$(nproc); export SW_CPUS="${SW_CPUS:-$((n-6))-$((n-1))}"
bash "$HERE/launch_v100.sh" "$PROJECT"
PORT="${SW_DEBUG_PORT:-9878}"
for i in $(seq 1 400); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 1; done
sleep 12
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-4}" $RC "$@" 2>&1 | grep -v '^$'; }
btn() { RC_READ=8 $RC "ui" 2>/dev/null | grep -F "<$1>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}'; }
state() { rcc "call pad_adapter.gd debug_state" | sed 's/OK called debug_state -> //'; }
brief() { echo "$1" | grep -o "label='[^']*'\|index=[0-9]*\|tiles=[0-9]*\|types={[^}]*}\|available=[0-9]*\|moves=[0-9]*" | tr '\n' ' '; }
extent() { rcc "call pad_adapter.gd debug_board_screen" | sed 's/OK called debug_board_screen -> //'; }
snap() {
	RC_WAIT=0.3 RC_READ=6 $RC snapshot >/dev/null 2>&1; $RC full >/dev/null 2>&1
	cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg"; cp "$SNAP.png" "$RUN/shots/${P}_$1.png"
}
echo "画面: $(rcc size | head -n 1)"
snap 00_title
target=$(btn "PlayButton")
[ -n "$target" ] || { echo "标题页上找不到 PlayButton 按钮，停在这里"; RC_READ=6 $RC ui 2>&1 | head -n 12; bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1; }
set -- $target "$@"
pos_x="$1"; pos_y="$2"; shift 2
RC_WAIT=0.3 $RC "click $pos_x $pos_y" >/dev/null 2>&1
sleep 9
for try in 1 2 3 4; do
	rcc "call pad_adapter.gd debug_pick_character 0" >/dev/null
	sleep 12
	scene=$(rcc scene | grep "^OK scene" | cut -c1-100)
	case "$scene" in *main.tscn*) break ;; esac
done
echo "进游戏: $scene"
dismiss=$(btn "<TutorialCloseButton>")      # 第一次进游戏会先弹"玩法"卡片（整局暂停）：有就点掉
[ -n "$dismiss" ] && { RC_WAIT=0.3 $RC "click $dismiss" >/dev/null 2>&1; sleep 1; echo "点掉了第一次的玩法卡片"; }
sleep 20
cur=1
for lvl in "$@"; do
	while [ "$cur" -lt "$lvl" ]; do
		rcc "call main.gd next_level" >/dev/null
		cur=$((cur + 1))
		sleep 11
	done
	echo "第 $lvl 关: $(brief "$(state)")"
	echo "        $(extent)"
	snap "L$lvl"
done
echo "== 运行日志里的报错 =="
echo "SCRIPT ERROR: $(grep -c 'SCRIPT ERROR' "$LOG")   ERROR: $(grep -c '^ERROR' "$LOG")"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A4 "SCRIPT ERROR\|^ERROR" | head -n 16 | cut -c1-200
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"

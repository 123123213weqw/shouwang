#!/bin/bash
# 过关流程测试：不直接调 next_level，而是让主角一条一条地吃鱼，吃满了跳进传送门，看会不会进下一关。
#   主线：真实地走完第 1 关和第 12 关（第 12 关走完就是通关，拍下结算画面）；中间的关卡直接跳过去，只确认都能正常载入。
#   长夜：真实地走完第 1 更和第 8 更。
# 用法: flowtest_v100.sh <工程目录> <campaign|endless> <截图前缀>
# 环境变量同 launch_v100.sh（几个实例同时跑的时候各设各的）。截图写到 $SW_RUN/shots/，文件名以 <前缀>_ 开头。
PROJECT="$1"; MODE="$2"; P="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
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
snap() {
	RC_WAIT=0.3 RC_READ=6 $RC snapshot >/dev/null 2>&1
	RC_WAIT=0.3 RC_READ=8 $RC full >/dev/null 2>&1
	cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg"; cp "$SNAP.png" "$RUN/shots/${P}_$1.png"
}
brief() { echo "$1" | grep -o "label='[^']*'\|index=[0-9]*\|tiles=[0-9]*\|fish=[0-9]*/[0-9]*\|moves=[0-9]*\|combo=[0-9]*\|score=[0-9]*" | tr '\n' ' '; }
fail=0

# 把当前这一关真实地走完：一条一条地吃鱼，吃完了跳进传送门。关卡序号变了就是进了下一关（返回 0）；
# 没鱼也没传送门了、序号却没变，是通关了（返回 2）
play_level() {
	local idle=0 before idx_before r after idx_after
	for i in $(seq 1 40); do
		before=$(state)
		idx_before=$(echo "$before" | sed -E 's/.* index=([0-9]+) .*/\1/')
		r=$(rcc "call pad_adapter.gd debug_next_fish" | sed 's/OK called debug_next_fish -> //')
		case "$r" in
			*busy*) sleep 2 ;;
			*"no fish and no portal"*) idle=$((idle + 1)); sleep 3 ;;
			*) idle=0; sleep 3 ;;
		esac
		after=$(state)
		idx_after=$(echo "$after" | sed -E 's/.* index=([0-9]+) .*/\1/')
		echo "  第 $i 跳: $r   →   $(brief "$after")"
		if [ "$idx_after" != "$idx_before" ]; then echo "  >>> 进了下一关"; return 0; fi
		[ "$idle" -ge 3 ] && { echo "  >>> 没鱼也没传送门了，序号没变"; return 2; }
	done
	return 1
}

target=$(btn PlayButton); [ "$MODE" = endless ] && target=$(btn EndlessButton)
set -- $target
[ -n "$1" ] || { echo "标题页上找不到模式的按钮（按节点名 PlayButton / EndlessButton），停在这里"; RC_READ=6 $RC "ui" 2>&1 | head -n 12; bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1; }
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
sleep 10
# 第一次进游戏会先弹"玩法"卡片（整局暂停）：有就点掉
dismiss=$(btn TutorialCloseButton)
[ -n "$dismiss" ] && { RC_WAIT=0.3 $RC "click $dismiss" >/dev/null 2>&1; sleep 1; echo "点掉了第一次的玩法卡片"; }
echo "开局: $(brief "$(state)")"
snap 01_start
echo "== 真实地走完第一关 =="
play_level || { echo "[没过] 第一关没有走进下一关"; fail=1; }
sleep 8
snap 02_after_first
echo "下一关开局: $(brief "$(state)")"

if [ "$MODE" = endless ]; then
	echo "== 跳到第 8 更，真实地走完 =="
	rcc "call pad_adapter.gd debug_goto_level 8" >/dev/null; sleep 10
	snap 03_geng8
	play_level || { echo "[没过] 第 8 更没有走进下一更"; fail=1; }
	sleep 8
	snap 04_after_geng8
else
	echo "== 第 3 到 11 关：直接跳过去，确认都能载入 =="
	for lvl in 3 4 5 6 7 8 9 10 11; do
		rcc "call pad_adapter.gd debug_goto_level $lvl" >/dev/null
		sleep 6
		line="$(brief "$(state)")"
		echo "  $line"
		echo "$line" | grep -q "index=$((lvl - 1)) " || { echo "  [没过] 第 $lvl 关没有载入"; fail=1; }
	done
	echo "== 第 12 关：真实地走完（通关） =="
	rcc "call pad_adapter.gd debug_goto_level 12" >/dev/null; sleep 6
	snap 03_level12
	play_level
	code=$?
	sleep 8
	snap 04_finished
	echo "通关后: $(brief "$(state)")"
	[ "$code" = 2 ] || { echo "[没过] 走完第 12 关后没有停下来（应该停在结算画面）"; fail=1; }
fi

echo "== 运行日志里的报错 =="
errs=$(grep -c 'SCRIPT ERROR' "$LOG")
others=$(grep -c '^ERROR' "$LOG")
echo "SCRIPT ERROR: $errs   ERROR: $others"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A3 "SCRIPT ERROR\|^ERROR" | head -n 20 | cut -c1-220
[ "$errs" = 0 ] && [ "$others" = 0 ] || fail=1
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$fail" = 0 ] && echo "RESULT 过关流程（$MODE）：通过" || echo "RESULT 过关流程（$MODE）：没过"
exit $fail

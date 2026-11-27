#!/bin/bash
# 录一段换关的过渡（样式由 SW_TRANSITION 给）：从标题页进游戏，机器人在第 1 关照着摆好的路走到水车上，过渡，进第 2 关。
# 几种样式录的都是同一段（关卡是固定的那一局、机器人走的路固定、难度固定用中等），片子能逐帧对比。
# 录像是 debug_record 让游戏按真实时间存的帧（默认每秒 30 张）。帧留在服务器的 /tmp/sw_transition_<样式>/，
# 由 agent.sh 的 transition 命令取回本机 builds/transition/<样式>/，再用 assemble_transition.sh 拼视频：
# 拼的时候按日志里的 RECORD_START 和 TRANSITION_BEGIN / TRANSITION_END 对齐，从过渡开始前一秒半截到结束后两秒半。
# 用法: record_transition_v100.sh <工程目录> <样式> [录几秒，默认 12] [每秒存几张，默认 30]
# 环境变量同 launch_v100.sh；SW_TRANSITION 由 agent.sh 传进来。
PROJECT="$1"; STYLE="${2:-tiles}"; SECS="${3:-12}"; FPS="${4:-30}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
DIR="/tmp/sw_transition_$STYLE"
RC="bash $HERE/rc.sh"
rm -rf "$DIR"
export SW_TRANSITION="$STYLE" SW_OPENING=off SW_BOOT_WAIT=2 SW_RULESET=normal SW_REC="$DIR"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
up=0
for i in $(seq 1 500); do
	(echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && { up=1; break; }
	grep -a -q "is not compiling\|Failed to create an autoload" "$LOG" 2>/dev/null && break
	sleep 1
done
if [ "$up" != 1 ]; then
	echo "调试端口没起来。日志末尾："; tail -n 12 "$LOG" | sed 's/\x1b\[[0-9;]*m//g'
	bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1
fi
sleep "${SW_BOOT_WAIT}"
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-3}" $RC "$@" 2>&1 | grep -v '^$'; }
printf '渲染方式：%s\n' "$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -a -m1 'Using Device' | sed 's/.*- Using/Using/' | cut -c1-70)"
echo "样式：$(rcc "call pad_adapter.gd debug_transition 0" | sed 's/^OK called debug_transition -> //')"
rcc "call pad_adapter.gd debug_unlock_all" >/dev/null
# 点"巡夜"（PlayButton）的正中，再选第一个同伴，进游戏
target=$(RC_READ=8 $RC ui | grep -F "<PlayButton>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3 / 2), int($2 + $4 / 2)}')
RC_WAIT=0.3 $RC "click $target" >/dev/null
sleep 2
rcc "call pad_adapter.gd debug_pick_character 0"
# 等第 1 关载入完（幕布掀开、灯都摆好了）：棋盘上有能跳的格子了才算
for i in $(seq 1 40); do
	state=$(rcc "call pad_adapter.gd debug_state" | grep -a -m1 'label=')
	case "$state" in *"available=0"*) sleep 1 ;; *"label="*) break ;; *) sleep 1 ;; esac
done
sleep 1.5
rcc "call pad_adapter.gd debug_record $SECS $FPS transition" >/dev/null
sleep 1
# 机器人照着摆好的路走（模式 1），走到水车上就换关；最多打到第 2 关
rcc "call pad_adapter.gd debug_autoplay 1 2" >/dev/null
for i in $(seq 1 $((SECS + 40))); do grep -a -q "RECORD_DONE" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 2
begin=$(grep -a 'TRANSITION_BEGIN .* level' "$LOG" | tail -n 1 | awk '{print $2}')
end=$(grep -a 'TRANSITION_END .* level' "$LOG" | tail -n 1 | awk '{print $2}')
start=$(grep -a -m1 'RECORD_START' "$LOG" | awk '{print $2}')
echo "$start ${begin:-0} ${end:-0}" > "$DIR/marks.txt"
echo "对齐（微秒，从游戏启动算起）：录像开始 ${start:-?}，过渡开始 ${begin:-没录到}，过渡结束 ${end:-没录到}"
echo "量出来：$(rcc "call pad_adapter.gd debug_transition 0" | sed 's/^OK called debug_transition -> //')"
n=$(ls "$DIR"/transition_*.jpg 2>/dev/null | wc -l | tr -d ' ')
want=$(awk -v s="$SECS" -v f="$FPS" 'BEGIN{printf "%d", s*f*0.9}')
[ "$n" -ge "$want" ] || echo "存帧跟不上：要 $SECS 秒 × 每秒 $FPS 张，只存到 $n 张"
[ -n "$begin" ] && [ -n "$end" ] || echo "没录到换关：日志里没有换关的 TRANSITION_BEGIN / TRANSITION_END"
echo "录了 $n 帧，在 $DIR"
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG"); shaders=$(grep -c 'SHADER ERROR' "$LOG")
echo "日志里的报错: SCRIPT ERROR=$errs   ERROR=$others   SHADER ERROR=$shaders"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A6 "SCRIPT ERROR\|^ERROR\|SHADER ERROR" | head -n 40
cp "$LOG" "$DIR/run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$errs" = 0 ] && [ "$others" = 0 ] && [ "$shaders" = 0 ] && [ "$n" -ge "$want" ] && [ -n "$begin" ] && [ -n "$end" ]

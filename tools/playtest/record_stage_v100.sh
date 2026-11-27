#!/bin/bash
# 录一段游戏里的背景（三种布局选一种，SW_STAGE 给）：从标题页进游戏，然后在棋盘上跳几下——看河灯在漂、主角落地时荡开的那圈。
# 录像是启动时用 SW_AUTOREC 让游戏自己从第一帧开始录的（遥控的 call 只能传整数参数，录像的名字传不过去）。
# 帧留在服务器的 /tmp/sw_stage_<布局>/，由 agent.sh 的 stage 命令取回本机 builds/stage/<布局>/，再用 assemble_stage.sh 拼成视频。
# 用法: record_stage_v100.sh <工程目录> <布局 1|2|3> [录几秒，默认 18] [每秒存几张，默认 20]
# 环境变量同 launch_v100.sh；SW_STAGE 由 agent.sh 传进来。
PROJECT="$1"; N="${2:-1}"; SECS="${3:-18}"; FPS="${4:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
DIR="/tmp/sw_stage_$N"
RC="bash $HERE/rc.sh"
rm -rf "$DIR"
export SW_STAGE="$N" SW_OPENING=off SW_BOOT_WAIT=2 SW_REC="$DIR" SW_AUTOREC="$SECS,$FPS,stage"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
up=0
for i in $(seq 1 500); do
	(echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && { up=1; break; }
	grep -a -q "is not compiling\|Failed to create an autoload" "$LOG" 2>/dev/null && break
	sleep 1
done
if [ "$up" != 1 ]; then
	echo "调试端口没起来。日志末尾："; tail -n 12 "$LOG" | cut -c1-200
	bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1
fi
sleep "${SW_BOOT_WAIT}"
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-3}" $RC "$@" 2>&1 | grep -v '^$'; }
printf '渲染方式：%s\n' "$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -a -m1 'Using Device' | sed 's/.*- Using/Using/' | cut -c1-70)"
rcc "call pad_adapter.gd debug_unlock_all" >/dev/null
# 点"巡夜"（PlayButton）的正中，再选第一个同伴，进游戏
target=$(RC_READ=8 $RC ui | grep -F "<PlayButton>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3 / 2), int($2 + $4 / 2)}')
RC_WAIT=0.3 $RC "click $target" >/dev/null
sleep 2
rcc "call pad_adapter.gd debug_pick_character 0"
sleep 4
rcc "call pad_adapter.gd debug_stage 0"
# 在棋盘上跳几下（哪边能跳就往哪边跳：四个方向各按一遍，按两轮）
for k in Right Right Down Left Up Right Down Up Left; do
	RC_WAIT=0.02 RC_READ=0.3 $RC "key $k" >/dev/null
	sleep 0.9
done
for i in $(seq 1 $((SECS + 40))); do grep -a -q "RECORD_DONE" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 2
echo "录了：$(grep -a 'RECORD_DONE' "$LOG" | tail -n 1 | sed 's/.*RECORD_DONE //') 帧，在 $DIR"
n=$(ls "$DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
want=$(awk -v s="$SECS" -v f="$FPS" 'BEGIN{printf "%d", s*f*0.9}')
[ "$n" -ge "$want" ] || echo "存帧跟不上：要 $SECS 秒 × 每秒 $FPS 张，只存到 $n 张"
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG"); shaders=$(grep -c 'SHADER ERROR' "$LOG")
echo "日志里的报错: SCRIPT ERROR=$errs   ERROR=$others   SHADER ERROR=$shaders"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A6 "SCRIPT ERROR\|^ERROR\|SHADER ERROR" | head -n 40 | cut -c1-260
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$errs" = 0 ] && [ "$others" = 0 ] && [ "$shaders" = 0 ] && [ "$n" -ge "$want" ]

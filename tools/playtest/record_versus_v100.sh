#!/bin/bash
# 录一局对战（五种里选一种）：从标题页直接开局，主角交给机器人打，对手本来就不是人。
# 录的头几秒是标题页和转场，拼视频的时侯会掐掉。帧留在服务器的 /tmp/sw_versus_<编号>/，
# 由 agent.sh 的 versus 命令取回本机 builds/versus/<编号>/，再用 tools/playtest/assemble_versus.sh 拼成视频。
# 用法: record_versus_v100.sh <工程目录> <编号 1..5> [录几秒，默认 24] [每秒存几张，默认 20]
# 环境变量同 launch_v100.sh。录像是启动时用 SW_AUTOREC 让游戏自己从第一帧开始录的。
PROJECT="$1"; N="${2:-1}"; SECS="${3:-24}"; FPS="${4:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
DIR="/tmp/sw_versus_$N"
RC="bash $HERE/rc.sh"
rm -rf "$DIR"
export SW_OPENING=off SW_BOOT_WAIT=2 SW_REC="$DIR" SW_AUTOREC="$SECS,$FPS,versus"
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
# 开局，主角交给机器人
RC_WAIT=0.3 rcc "call pad_adapter.gd debug_versus $N 1"
sleep 3
rcc "call pad_adapter.gd debug_versus 0"
for i in $(seq 1 $((SECS + 40))); do grep -a -q "RECORD_DONE" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 2
echo "录了：$(grep -a 'RECORD_DONE' "$LOG" | tail -n 1 | sed 's/.*RECORD_DONE //') 帧，在 $DIR"
rcc "call pad_adapter.gd debug_versus 0"
# 存帧的速率要和说好的一致：说好每秒 $FPS 张、录 $SECS 秒，就该有 $SECS × $FPS 张。存少了说明这台机器存不过来
n=$(ls "$DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
want=$(awk -v s="$SECS" -v f="$FPS" 'BEGIN{printf "%d", s*f*0.9}')
[ "$n" -ge "$want" ] || echo "存帧跟不上：要 $SECS 秒 × 每秒 $FPS 张，只存到 $n 张"
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG"); shaders=$(grep -c 'SHADER ERROR' "$LOG")
echo "日志里的报错: SCRIPT ERROR=$errs   ERROR=$others   SHADER ERROR=$shaders"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A6 "SCRIPT ERROR\|^ERROR\|SHADER ERROR" | head -n 40 | cut -c1-260
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$errs" = 0 ] && [ "$others" = 0 ] && [ "$shaders" = 0 ] && [ "$n" -ge "$want" ]

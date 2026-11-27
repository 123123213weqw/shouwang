#!/bin/bash
# 录一段大厅（标题页）的背景：那条夜里的河和河上的灯，外加指针划过水面、挪菜单的焦点时荡开的涟漪。
# 不播开场动画，游戏一起来就在标题页上。帧留在服务器的 /tmp/sw_lobby/，由 agent.sh 的 lobby 命令取回本机
# builds/lobby/rec/，再用 tools/playtest/assemble_lobby.sh 拼成视频。
# 用法: record_lobby_v100.sh <工程目录> [录几秒，默认 20] [每秒存几张，默认 20]
# 开头三秒是没人动的样子（河自己流），之后指针走一趟，最后挪菜单的焦点。
# 录像是启动时用 SW_AUTOREC 让游戏自己从第一帧开始录的：遥控的 call 只能传整数参数，录像的名字传不过去
# 环境变量同 launch_v100.sh。
PROJECT="$1"; SECS="${2:-20}"; FPS="${3:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
DIR="/tmp/sw_lobby_$(basename "${SW_RUN:-x}")"      # 带上标签：几个标签同时录的时侯别写进同一个目录
RC="bash $HERE/rc.sh"
rm -rf "$DIR"
export SW_OPENING=off SW_BOOT_WAIT=3 SW_REC="$DIR" SW_AUTOREC="$SECS,$FPS,lobby"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
up=0
for i in $(seq 1 500); do
	(echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && { up=1; break; }
	# 脚本有编译错误的话端口永远起不来，不用干等
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
# 河上的灯多放几盏，看得清
rcc "call pad_adapter.gd debug_lobby 2 11"
rcc "call pad_adapter.gd debug_lobby 0"
# 指针贴着水面从左下往右上走一趟（走过去的地方起涟漪、水纹亮起来），走完把菜单的焦点往下挪两格再挪回来：
# 每挪一下，那个按钮底下荡开一圈
sleep 1
for i in $(seq 0 26); do
	RC_WAIT=0.02 RC_READ=0.12 $RC "move $((150 + i * 30)) $((650 - i * 11))" >/dev/null
	sleep 0.22
done
for k in Down Down Up; do RC_WAIT=0.02 RC_READ=0.3 $RC "key $k" >/dev/null; sleep 1.0; done
for i in $(seq 1 $((SECS + 40))); do grep -a -q "RECORD_DONE" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 2
echo "录了：$(grep -a 'RECORD_DONE' "$LOG" | tail -n 1 | sed 's/.*RECORD_DONE //') 帧，在 $DIR"
# 收尾时把每一盏灯的数报出来（在哪、有多淡、光晕多亮）：画面不对的时侯对着录像看
rcc "call pad_adapter.gd debug_lobby 3"
# 存帧的速率要和说好的一致：说好每秒 $FPS 张、录 $SECS 秒，就该有 $SECS × $FPS 张。存少了说明这台机器存不过来
n=$(ls "$DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
want=$(awk -v s="$SECS" -v f="$FPS" 'BEGIN{printf "%d", s*f*0.9}')
[ "$n" -ge "$want" ] || echo "存帧跟不上：要 $SECS 秒 × 每秒 $FPS 张，只存到 $n 张"
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG"); shaders=$(grep -c 'SHADER ERROR' "$LOG")
echo "日志里的报错: SCRIPT ERROR=$errs   ERROR=$others   SHADER ERROR=$shaders"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A6 "SCRIPT ERROR\|^ERROR\|SHADER ERROR" | head -n 40 | cut -c1-260
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$errs" = 0 ] && [ "$others" = 0 ] && [ "$shaders" = 0 ] && [ "$n" -ge "$want" ]

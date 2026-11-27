#!/bin/bash
# 录一段开场动画（真正的开机画面）：启动游戏的时侯让它从第一帧起把画面逐帧存下来，录完把帧留在服务器的 /tmp/sw_opening_<方案>/，
# 由 agent.sh 的 opening 命令取回本机 builds/opening/<方案>/，再用 tools/playtest/assemble_opening.sh 拼成视频和动图。
# 用法: record_opening_v100.sh <工程目录> <A|B|D> [录几秒，默认 4.8] [每秒存几张，默认 20]
# 环境变量同 launch_v100.sh。
PROJECT="$1"; WHICH="$2"; SECS="${3:-4.8}"; FPS="${4:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
DIR="/tmp/sw_opening_$(basename "${SW_RUN:-x}")_$WHICH"      # 带上标签：几个标签同时录的时侯别写进同一个目录
rm -rf "$DIR"
export SW_REC="$DIR" SW_OPENING="$WHICH" SW_AUTOREC="$SECS,$FPS,open$WHICH"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
for i in $(seq 1 150); do grep -a -q "RECORD_DONE" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 3
echo "录了：$(grep -a 'RECORD_DONE' "$LOG" | tail -n 1 | sed 's/.*RECORD_DONE //') 帧，在 $DIR"
# 存帧的速率要和要的一致：说好每秒 $FPS 张、录 $SECS 秒，就该有 $SECS × $FPS 张。
# 存少了说明这台机器存不过来——按 $FPS 回放，画面会比声音快，"顺序"就乱了
n=$(ls "$DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
want=$(awk -v s="$SECS" -v f="$FPS" 'BEGIN{printf "%d", s*f*0.9}')
if [ "$n" -lt "$want" ]; then
	echo "存帧跟不上：要 $SECS 秒 × 每秒 $FPS 张 ≈ $(( ${SECS%.*} * ${FPS%.*} )) 张，只存到 $n 张。把每秒张数调低再录（20 张这台机器跟得上）"
fi
# 核对实际播的是不是要录的那个（存档里记的开场、环境变量没传到，都会让它播成别的）
line=$(grep -a 'OPENING_PLAY' "$LOG" | tail -n 1)
played=$(echo "$line" | sed 's/.*OPENING_PLAY //' | awk '{print $1}')
sound=$(echo "$line" | sed 's/.*sound=//' | awk '{print $1}')
wrong=0
[ "$played" = "$WHICH" ] || { echo "没录对：要录 $WHICH，游戏实际播的是 ${played:-（没播开场）}"; wrong=1; }
[ "$sound" = "ok" ] || { echo "开场没有放出声音：${line:-（没有这一行）}"; wrong=1; }
errs=$(grep -c 'SCRIPT ERROR' "$LOG"); others=$(grep -c '^ERROR' "$LOG")
echo "日志里的报错: SCRIPT ERROR=$errs   ERROR=$others"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A6 "SCRIPT ERROR\|^ERROR" | head -n 30 | cut -c1-260
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$errs" = 0 ] && [ "$others" = 0 ] && [ "$wrong" = 0 ]

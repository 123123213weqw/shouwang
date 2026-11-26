#!/bin/bash
# 把录回来的一局对战的帧（builds/versus/<编号>/versus_*.jpg，每秒 20 张）拼成视频：builds/versus/对战<编号>.mp4。
# 头上是标题页和转场的那几秒掐掉（从第 3 秒起），带上游戏里的音乐。
# 用法（在本机跑，要有 ffmpeg）: tools/playtest/assemble_versus.sh <编号 1..5> [每秒几帧，默认 20] [从第几秒开始，默认 3]
set -u
cd "$(dirname "$0")/../.." || exit 1
N="$1"; FPS="${2:-20}"; START="${3:-3}"
D="builds/versus/$N"
first=$(awk -v s="$START" -v f="$FPS" 'BEGIN{printf "%d", s*f}')
n=$(ls "$D"/versus_*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -gt "$first" ] || { echo "对战 ${N}：没有足够的帧（只有 ${n} 张）；先录：tools/playtest/agent.sh a7 versus ${N}"; exit 1; }
music="assets/audio/GameOff_Mus_01 Loop.wav"
if [ -f "$music" ]; then
	ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$first" -i "$D/versus_%04d.jpg" -i "$music" \
		-c:v libx264 -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k -shortest "builds/versus/对战${N}.mp4" || { echo "拼视频失败"; exit 1; }
else
	ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$first" -i "$D/versus_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -crf 17 "builds/versus/对战${N}.mp4" || { echo "拼视频失败"; exit 1; }
fi
echo "对战 ${N}：$((n - first)) 帧 → builds/versus/对战${N}.mp4（$(du -h "builds/versus/对战${N}.mp4" | cut -f1)）"

#!/bin/bash
# 把录回来的游戏里背景的帧（builds/stage/<布局>/stage_*.jpg，每秒 20 张）拼成视频：builds/stage/stage<布局>.mp4。
# 头上是标题页、点进游戏的那几秒不录进去（START 以后才开始，默认第 8 秒起），带上游戏里的音乐。
# 用法（在本机跑，要有 ffmpeg）: tools/playtest/assemble_stage.sh <布局 1|2|3> [每秒几帧，默认 20] [从第几秒开始，默认 8]
set -u
cd "$(dirname "$0")/../.." || exit 1
N="$1"; FPS="${2:-20}"; START="${3:-8}"
D="builds/stage/$N"
first=$(awk -v s="$START" -v f="$FPS" 'BEGIN{printf "%d", s*f}')
n=$(ls "$D"/stage_*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -gt "$first" ] || { echo "布局 ${N}：没有足够的帧（只有 $n 张）；先跑 SW_STAGE=$N tools/playtest/agent.sh a7 stage $N"; exit 1; }
music="assets/audio/GameOff_Mus_01 Loop.wav"
if [ -f "$music" ]; then
	ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$first" -i "$D/stage_%04d.jpg" -i "$music" \
		-c:v libx264 -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k -shortest "builds/stage/stage$N.mp4" || { echo "拼视频失败"; exit 1; }
else
	ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$first" -i "$D/stage_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -crf 17 "builds/stage/stage$N.mp4" || { echo "拼视频失败"; exit 1; }
fi
ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$first" -i "$D/stage_%04d.jpg" -vf "fps=10,scale=640:-1:flags=lanczos" "builds/stage/stage$N.gif" || echo "拼动图失败"
echo "布局 ${N}：$((n - first)) 帧 → builds/stage/stage${N}.mp4（$(du -h "builds/stage/stage${N}.mp4" | cut -f1)）和 stage${N}.gif（$(du -h "builds/stage/stage${N}.gif" | cut -f1)）"

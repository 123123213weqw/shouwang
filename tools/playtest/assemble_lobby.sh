#!/bin/bash
# 把录回来的大厅背景的帧（builds/lobby/rec/lobby_*.jpg）拼成视频，放在 builds/lobby/：
#   lobby.mp4   和游戏里一样大，带着标题页自己的音乐（从曲子开头取和画面一样长的一段）
#   lobby.gif   640 宽、每秒 10 帧、没有声音，发给别人看用
# 用法（在本机跑，要有 ffmpeg）: tools/playtest/assemble_lobby.sh [每秒几帧，默认 20]
set -u
cd "$(dirname "$0")/../.." || exit 1
FPS="${1:-20}"
D="builds/lobby/rec"
n=$(ls "$D"/lobby_*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -gt 0 ] || { echo "没有帧：先跑 tools/playtest/agent.sh a7 lobby"; exit 1; }
dur=$(awk -v n="$n" -v f="$FPS" 'BEGIN{printf "%.3f", n/f}')
music="assets/audio/GameOff_Mus_02 MainTitle 143bpm Loop.wav"
if [ -f "$music" ]; then
	ffmpeg -loglevel error -y -framerate "$FPS" -i "$D/lobby_%04d.jpg" -i "$music" -t "$dur" \
		-c:v libx264 -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k builds/lobby/lobby.mp4 || { echo "拼视频失败"; exit 1; }
	how="带标题音乐"
else
	ffmpeg -loglevel error -y -framerate "$FPS" -i "$D/lobby_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -crf 17 builds/lobby/lobby.mp4 || { echo "拼视频失败"; exit 1; }
	how="没有声音（找不到 $music）"
fi
ffmpeg -loglevel error -y -framerate "$FPS" -i "$D/lobby_%04d.jpg" -vf "fps=10,scale=640:-1:flags=lanczos" builds/lobby/lobby.gif || echo "拼动图失败"
echo "${n} 帧 → builds/lobby/lobby.mp4（${dur} 秒，${how}，$(du -h builds/lobby/lobby.mp4 | cut -f1)）和 lobby.gif（$(du -h builds/lobby/lobby.gif | cut -f1)）"

#!/bin/bash
# 把录回来的开场动画的帧（builds/opening/<方案>/*.jpg，每秒 20 张）拼成视频和动图，放在同一个目录里：
#   open<A>.mp4   1152×720，每秒 20 帧，带着这一段的声音（assets/audio/opening/open<A>.wav），看效果用这个
#   open<A>.gif   640 宽，每秒 10 帧，没有声音，发给别人看用
# 三个方案都有帧的时侯再拼两张：
#   openALL.mp4 / openALL.gif     三宫格对照：左 A、中 B、右 D，每一格角上写着方案的名字（三段声音不能一起放，这张没有声音）
#   openABD.mp4                   三段挨个放一遍，带着声音，听三段是不是一套的
# 用法（在本机跑，要有 ffmpeg；拼对照图还要 Python 和 Pillow）: tools/playtest/assemble_opening.sh [方案或者 ALL，默认全部] [每秒几帧，默认 20]
# 写这个脚本要小心一处：变量名后面紧跟中文标点的时侯 bash 会把标点的字节也算进变量名里（报「unbound variable」），一律写成 ${w} 这样。
set -u
cd "$(dirname "$0")/../.." || exit 1
WHICH="${1:-}"; FPS="${2:-}"
FPS="${FPS:-20}"
for d in builds/opening/*/; do
	w="$(basename "$d")"
	[ -z "$WHICH" ] || [ "$w" = "$WHICH" ] || continue
	n=$(ls "$d"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
	[ "$n" -gt 0 ] || { echo "$w：没有帧"; continue; }
	audio="assets/audio/opening/open${w}.wav"
	if [ -f "$audio" ]; then
		# 声音按画面实际的长度裁：存帧不一定和名义帧率一致，硬用固定秒数裁，声音就会和画面对不上
		vdur=$(awk -v n="$n" -v f="$FPS" 'BEGIN{printf "%.3f", n/f}')
		ffmpeg -loglevel error -y -framerate "$FPS" -i "$d/open${w}_%04d.jpg" -i "$audio" \
			-c:v libx264 -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k -t "$vdur" "builds/opening/open${w}.mp4" || { echo "${w}：拼视频失败"; continue; }
		how="带声音"
	else
		ffmpeg -loglevel error -y -framerate "$FPS" -i "$d/open${w}_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -crf 17 "builds/opening/open${w}.mp4" || { echo "${w}：拼视频失败"; continue; }
		how="没有声音（$audio 不存在）"
	fi
	ffmpeg -loglevel error -y -framerate "$FPS" -i "$d/open${w}_%04d.jpg" -vf "fps=10,scale=640:-1:flags=lanczos" "builds/opening/open${w}.gif" || { echo "${w}：拼动图失败"; continue; }
	echo "${w}：${n} 帧 → builds/opening/open${w}.mp4（${how}，$(du -h "builds/opening/open${w}.mp4" | cut -f1)）和 open${w}.gif（$(du -h "builds/opening/open${w}.gif" | cut -f1)）"
done
[ -z "$WHICH" ] || [ "$WHICH" = ALL ] || exit 0
for w in A B D; do
	[ -f "builds/opening/open${w}.mp4" ] || { echo "对照图没拼：没有 open${w}.mp4"; exit 1; }
done

# 方案的名字用游戏自己的字体画成小图，再用 ffmpeg 叠到每一格的左上角（本机的 ffmpeg 没带画字的滤镜）
mkdir -p builds/opening/.labels
python3 - <<'PY' || exit 1
from PIL import Image, ImageDraw, ImageFont
import os
# 名字用游戏自己的字体；开头的字母这个字体画得像个方块，换一支寻常的无衬线体（找不到就还用游戏的字体）
name_font = ImageFont.truetype("assets/fonts/ZCOOLKuaiLe-Regular.ttf", 30)
letter_font = None
for path in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Helvetica.ttc",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
    if os.path.exists(path):
        letter_font = ImageFont.truetype(path, 30)
        break
if letter_font is None: letter_font = name_font
names = {"A": "一灯破夜", "B": "水墨惊雷", "D": "守夜人点灯"}
for key, text in names.items():
    lb, nb = letter_font.getbbox(key), name_font.getbbox(text)
    w = (lb[2] - lb[0]) + 12 + (nb[2] - nb[0])
    h = max(lb[3] - lb[1], nb[3] - nb[1])
    im = Image.new("RGBA", (w + 28, h + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=10, fill=(6, 20, 18, 190), outline=(214, 232, 220, 230), width=2)
    d.text((14 - lb[0], 10 - lb[1]), key, font=letter_font, fill=(255, 214, 120, 255))
    d.text((14 + (lb[2] - lb[0]) + 12 - nb[0], 10 - nb[1]), text, font=name_font, fill=(246, 250, 246, 255))
    im.save("builds/opening/.labels/%s.png" % key)
PY

FRAMES=()
for w in A B D; do FRAMES+=(-framerate "$FPS" -i "builds/opening/$w/open${w}_%04d.jpg"); done
LABELS=()
for w in A B D; do LABELS+=(-i "builds/opening/.labels/$w.png"); done

# 三宫格对照：每一格 576×360
ffmpeg -loglevel error -y "${FRAMES[@]}" "${LABELS[@]}" \
	-filter_complex "[0:v]scale=576:360[a];[1:v]scale=576:360[b];[2:v]scale=576:360[c];\
[a][3:v]overlay=14:12[aa];[b][4:v]overlay=14:12[bb];[c][5:v]overlay=14:12[cc];\
[aa][bb][cc]hstack=inputs=3[out]" \
	-map "[out]" -c:v libx264 -pix_fmt yuv420p -crf 17 builds/opening/openALL.mp4 \
	&& ffmpeg -loglevel error -y -i builds/opening/openALL.mp4 -vf "fps=10,scale=640:-1:flags=lanczos" builds/opening/openALL.gif \
	&& echo "对照图 → builds/opening/openALL.mp4（$(du -h builds/opening/openALL.mp4 | cut -f1)）和 openALL.gif（$(du -h builds/opening/openALL.gif | cut -f1)），没有声音" \
	|| { echo "三宫格没拼出来"; exit 1; }

# 三段挨个放：按 A、B、D 的文件顺序直接把三段接起来（每段自己的声音跟着自己的画面走，
# 不用固定长度去切声音——之前那样切，听到的是上一段的曲子配下一段的画面）
if [ -f assets/audio/opening/openD.wav ]; then
	LIST=builds/opening/.concat.txt
	: > "$LIST"
	for w in A B D; do echo "file 'open${w}.mp4'" >> "$LIST"; done
	ffmpeg -loglevel error -y -f concat -safe 0 -i "$LIST" -c copy builds/opening/openABD.mp4 \
		&& echo "三段连放 → builds/opening/openABD.mp4（带声音，$(du -h builds/opening/openABD.mp4 | cut -f1)；画面共 $(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 builds/opening/openABD.mp4) 秒）" \
		|| echo "三段连放没拼出来"
else
	echo "三段连放没拼：没有 assets/audio/opening/ 里的声音"
fi

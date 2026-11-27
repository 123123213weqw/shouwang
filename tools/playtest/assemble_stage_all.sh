#!/bin/bash
# 三个布局并排的一段视频（builds/stage/三个布局并排.mp4，每一格角上写着布局的名字）：
# 三段录像同一个时刻起、同样长，左 长河、中 远岸、右 月下。三段都有帧的时侯才拼。没有声音（三段一样，听一段就够）。
# 用法（在本机跑，要有 ffmpeg 和 Python、Pillow）: tools/playtest/assemble_stage_all.sh [每秒几帧，默认 20] [从第几秒开始，默认 8]
set -u
cd "$(dirname "$0")/../.." || exit 1
FPS="${1:-20}"; START="${2:-8}"
first=$(awk -v s="$START" -v f="$FPS" 'BEGIN{printf "%d", s*f}')
for n in 1 2 3; do
	[ -f "builds/stage/$n/stage_$(printf '%04d' "$((first + 180))").jpg" ] || { echo "布局 $n 的帧不够（要从第 ${first} 帧起至少 181 张）；先录：tools/playtest/agent.sh a7 stage $n"; exit 1; }
done
mkdir -p builds/stage/.labels
python3 - <<'PY' || exit 1
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype("assets/fonts/ZCOOLKuaiLe-Regular.ttf", 30)
for n, text in ((1, "一 长河"), (2, "二 远岸"), (3, "三 月下")):
    b = font.getbbox(text)
    im = Image.new("RGBA", (b[2] - b[0] + 30, b[3] - b[1] + 22), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=10, fill=(6, 20, 18, 190), outline=(214, 232, 220, 230), width=2)
    d.text((15 - b[0], 11 - b[1]), text, font=font, fill=(255, 226, 150, 255))
    im.save("builds/stage/.labels/%d.png" % n)
PY
ffmpeg -loglevel error -y \
	-framerate "$FPS" -start_number "$first" -i "builds/stage/1/stage_%04d.jpg" \
	-framerate "$FPS" -start_number "$first" -i "builds/stage/2/stage_%04d.jpg" \
	-framerate "$FPS" -start_number "$first" -i "builds/stage/3/stage_%04d.jpg" \
	-i builds/stage/.labels/1.png -i builds/stage/.labels/2.png -i builds/stage/.labels/3.png \
	-filter_complex "[0:v]scale=576:360[a];[1:v]scale=576:360[b];[2:v]scale=576:360[c];\
[a][3:v]overlay=14:12[aa];[b][4:v]overlay=14:12[bb];[c][5:v]overlay=14:12[cc];\
[aa][bb][cc]hstack=inputs=3[out]" -map "[out]" -frames:v 181 \
	-c:v libx264 -pix_fmt yuv420p -crf 17 builds/stage/三个布局并排.mp4 \
	&& echo "三个布局并排 → builds/stage/三个布局并排.mp4（$(du -h "builds/stage/三个布局并排.mp4" | cut -f1)，约 9 秒，没有声音）" \
	|| { echo "没拼出来"; exit 1; }

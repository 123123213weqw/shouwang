#!/bin/bash
# 把录回来的换关过渡的帧（builds/transition/<样式>/transition_*.jpg 或者 .png）拼成视频。在本机跑，要有 ffmpeg（并排那种还要 Python 的 Pillow）。
# 对齐靠的是录制时记在 builds/transition/<样式>/marks.txt 里的数：录像开始、过渡开始、过渡结束三个时刻（微秒），和实际每秒几帧
#（存 PNG 每帧慢，会比要求的每秒 30 张少，时间按实际的算）。
#   tools/playtest/assemble_transition.sh <样式> [每秒几帧=30] [开始前几秒=1.5] [结束后几秒=2.5]
#       builds/transition/<样式>.mp4       从过渡开始前 1.5 秒到结束后 2.5 秒，带上游戏里的音乐（服务器上录不到声音）
#       builds/transition/<样式>_slow.mp4  同一段放慢 2.5 倍，没有声音：看细节
#       builds/transition/<样式>_sheet.jpg 每隔几帧抽一张拼成的图：一眼看过场的全过程
#   tools/playtest/assemble_transition.sh compare <样式> [<样式> …]
#       builds/transition/compare.mp4      几种样式并排，都对齐到"过渡开始"的那一帧，从它前 1.5 秒到它后 3 秒
#       builds/transition/compare_sheet.jpg 同样内容的拼图
set -u
cd "$(dirname "$0")/../.." || exit 1
D="builds/transition"
MUSIC="assets/audio/GameOff_Mus_01 Loop.wav"
FPS="${2:-30}"; PRE="${3:-1.5}"; POST="${4:-2.5}"

EXT=jpg        # 这一种样式的帧是什么格式
RFPS=30        # 实际每秒几帧

# 这一种样式的帧是什么格式、实际每秒几帧（marks.txt 的第四个数；没有就按要求的算）
frames() {
	EXT=jpg
	[ -f "$D/$1/transition_0000.png" ] && EXT=png
	RFPS="$FPS"
	if [ -f "$D/$1/marks.txt" ]; then
		read -r _ _ _ r _ < "$D/$1/marks.txt"
		[ -n "${r:-}" ] && RFPS="$r"
	fi
	return 0
}

# <样式> → "过渡开始前 PRE 秒是第几帧  过渡结束后 POST 秒是第几帧"；没录到就返回不是 0
window() {
	frames "$1"
	[ -f "$D/$1/marks.txt" ] || return 1
	read -r start begin end _ < "$D/$1/marks.txt"
	[ "${begin:-0}" != 0 ] && [ "${end:-0}" != 0 ] || return 1
	awk -v s="$start" -v b="$begin" -v e="$end" -v f="$RFPS" -v pre="$PRE" -v post="$POST" 'BEGIN{
		a = (b - s) / 1000000 * f - pre * f; if (a < 0) a = 0
		printf "%d %d\n", a, (e - s) / 1000000 * f + post * f }'
}

one() {
	S="$1"
	read -r first last < <(window "$S") || { echo "样式 ${S}：没有录到换关的过渡（builds/transition/$S/ 里没有帧，或者 marks.txt 里没记下过渡）。先录：tools/playtest/agent.sh a7 transition $S"; return 1; }
	n=$(ls "$D/$S"/transition_*."$EXT" 2>/dev/null | wc -l | tr -d ' ')
	[ "$n" -gt 0 ] || { echo "样式 ${S}：builds/transition/$S/ 里没有帧"; return 1; }
	[ "$last" -lt "$n" ] || last=$((n - 1))
	count=$((last - first + 1))
	# 两路输入（帧、音乐）都写在前面，输出的选项都写在后面：写在 -i 前面的会被当成那一路输入自己的选项
	music=(); [ -f "$MUSIC" ] && music=(-i "$MUSIC")
	sound=(); [ -f "$MUSIC" ] && sound=(-c:a aac -b:a 192k -shortest)
	ffmpeg -loglevel error -y -framerate "$RFPS" -start_number "$first" -i "$D/$S/transition_%04d.$EXT" "${music[@]}" \
		-frames:v "$count" "${sound[@]}" -c:v libx264 -pix_fmt yuv420p -crf 17 "$D/$S.mp4" || { echo "样式 ${S}：拼视频失败"; return 1; }
	slow=$(awk -v f="$RFPS" 'BEGIN{printf "%.4f", f / 2.5}')
	ffmpeg -loglevel error -y -framerate "$slow" -start_number "$first" -i "$D/$S/transition_%04d.$EXT" -frames:v "$count" \
		-c:v libx264 -pix_fmt yuv420p -crf 17 "$D/${S}_slow.mp4" || { echo "样式 ${S}：拼慢放的失败"; return 1; }
	# 拼图：每 4 帧抽 1 帧，排成 6 列
	ffmpeg -loglevel error -y -framerate "$RFPS" -start_number "$first" -i "$D/$S/transition_%04d.$EXT" -frames:v "$count" \
		-vf "select='not(mod(n\,4))',scale=384:-1:flags=lanczos,tile=6x6" -frames:v 1 "$D/${S}_sheet.jpg" || echo "样式 ${S}：拼图失败"
	echo "样式 ${S}：第 $first 到 $last 帧（$count 帧，$count / $RFPS 帧每秒；$EXT）→ $D/$S.mp4（$(du -h "$D/$S.mp4" | cut -f1)）、${S}_slow.mp4、${S}_sheet.jpg"
}

case "${1:-}" in
	"") echo "用法见文件开头：assemble_transition.sh <样式> […]，或者 assemble_transition.sh compare <样式> …"; exit 1 ;;
	compare)
		shift                                   # 这一种用法里位置参数都是样式名，不是帧率：从过渡开始前 1.5 秒起，到它后 3 秒
		[ $# -gt 0 ] || { echo "compare 后面要写样式名"; exit 1; }
		FPS=30; PRE=1.5
		mkdir -p "$D"
		python3 - "$D" "$PRE" 3.0 30 "$@" <<'PY' || exit 1
# 几种样式并排：每一种都从"过渡开始前 pre 秒"的那一帧起，按时间对齐到每秒 out_fps 帧。帧拼成一张张的大图，再用 ffmpeg 拼成视频
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont
D, pre, post, out_fps = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
styles = sys.argv[5:]
def info(s):
    try:
        start, begin, end = (int(x) for x in open(f"{D}/{s}/marks.txt").read().split()[:3])
    except (OSError, ValueError):
        return None
    if begin == 0 or end == 0: return None
    ext = "png" if os.path.exists(f"{D}/{s}/transition_0000.png") else "jpg"
    fps = 30.0
    try:
        fps = float(open(f"{D}/{s}/marks.txt").read().split()[3])
    except (IndexError, ValueError):
        pass
    n = len([f for f in os.listdir(f"{D}/{s}") if f.startswith("transition_") and f.endswith("." + ext)])
    return max(0, int((begin - start) / 1e6 * fps - pre * fps)), n, ext, fps
firsts = {}
for s in styles:
    w = info(s)
    if w is None or w[1] == 0:
        print(f"样式 {s}：没有录到换关的过渡，先录：tools/playtest/agent.sh a7 transition {s}"); sys.exit(1)
    firsts[s] = w
count = int((pre + post) * out_fps)
cols = 3 if len(styles) > 2 else len(styles)
rows = (len(styles) + cols - 1) // cols
CW, CH = 384, 240
font = None
for p in ["/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"]:
    if os.path.exists(p):
        try:
            font = ImageFont.truetype(p, 22); break
        except OSError:
            pass
tmp = tempfile.mkdtemp(prefix="sw_compare_")
sheet = Image.new("RGB", (CW * cols, CH * rows * 6), (255, 255, 255))
sheet_k = 0
for i in range(count):
    big = Image.new("RGB", (CW * cols, CH * rows), (255, 255, 255))
    for k, s in enumerate(styles):
        first, n, ext, fps = firsts[s]
        idx = min(first + round(i * fps / out_fps), n - 1)
        path = f"{D}/{s}/transition_{idx:04d}.{ext}"
        if not os.path.exists(path): continue
        im = Image.open(path).convert("RGB").resize((CW, CH), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, CW, 30], fill=(0, 0, 0))
        d.text((8, 3), f"{s}   {i / out_fps - pre:+.2f}s", fill=(255, 255, 255), font=font)
        big.paste(im, ((k % cols) * CW, (k // cols) * CH))
    big.save(f"{tmp}/{i:04d}.png")
    # 拼图：每半秒一帧，每一行是同一个时刻
    if i % int(out_fps / 2) == 0 and sheet_k < 6:
        sheet.paste(big, (0, sheet_k * CH * rows))
        sheet_k += 1
sheet.save(f"{D}/compare_sheet.jpg", quality=90)
music = "assets/audio/GameOff_Mus_01 Loop.wav"
args = ["-i", music, "-c:a", "aac", "-b:a", "192k", "-shortest"] if os.path.exists(music) else []
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", f"{out_fps:g}", "-i", f"{tmp}/%04d.png", *args,
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", f"{D}/compare.mp4"], check=True)
for f in os.listdir(tmp): os.remove(f"{tmp}/{f}")
os.rmdir(tmp)
print(f"并排对比（{len(styles)} 种，各 {count} 帧）：{D}/compare.mp4（{os.path.getsize(D + '/compare.mp4') // 1024} KB）和 compare_sheet.jpg")
PY
		;;
	*) one "$1" ;;
esac

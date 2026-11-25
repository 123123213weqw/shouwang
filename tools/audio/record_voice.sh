#!/bin/bash
# 录开场旁白的某一句（在本机跑，要用到麦克风和 ffmpeg）。录 4 秒，存到 builds/voice/voice<A>_raw.wav，
# 之后用 tools/audio/voice.py 收拾干净、放进游戏。用法（在工程根目录）: tools/audio/record_voice.sh <A|B|D>
set -u
cd "$(dirname "$0")/../.." || exit 1
W="${1:-}"
case "$W" in
	A|B|D) ;;
	*) echo "用法: tools/audio/record_voice.sh <A|B|D>"; exit 1 ;;
esac
LINE=$(python3 -I - "$W" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("voice", os.path.join("tools", "audio", "voice.py"))
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)
print(voice.LINES[sys.argv[1]])
PY
) || exit 1
mkdir -p builds/voice
OUT="builds/voice/voice${W}_raw.wav"
echo "这一句：「${LINE}」"
echo "按回车开始录（一共 4 秒，稍等一下再开口，从容地念完一遍，两秒钟以内）："
read -r _
ffmpeg -hide_banner -loglevel error -f avfoundation -framerate 30 -i ":0" -t 4 \
	-af "highpass=f=80,aformat=channel_layouts=mono" -ar 48000 -ac 1 -y "$OUT" || { echo "没录上：确认这个终端有麦克风的权限"; exit 1; }
echo "录好了：${OUT}。收拾干净并放进游戏：python3 tools/audio/voice.py ${W}；不满意就再录一遍"

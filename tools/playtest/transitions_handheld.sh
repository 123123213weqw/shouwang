#!/bin/bash
# 在掌机上把换关的过渡每种样式各就地放两遍，量盖住、掀开各多久、最长的一帧多长。掌机的显卡比服务器弱得多、窗口又是 2560×1600，
# 这几种着色器在掌机上行不行，只有在这里量了才算。
# 会占住掌机的屏幕，还会重启正在跑的游戏：只能在确认没人在掌机上玩的时候用，并且要带上参数 yes。
# 用法（从本机把脚本送过去执行）: ssh -J WZU_V100 RWKV_Tail 'bash -s yes' < tools/playtest/transitions_handheld.sh
# 调试遥控只监听掌机本机的 127.0.0.1:9878（游戏里 pad_adapter.gd）
rc() { exec 3<>/dev/tcp/127.0.0.1/9878 || return 1; printf "%s\n" "$1" >&3; sleep "${2:-0.8}"; timeout "${3:-8}" cat <&3 | grep -v '^$' | head -n "${4:-6}"; exec 3>&- 3<&-; }
if [ "${1:-}" != yes ]; then
	echo "没有带参数 yes：没确认过掌机上没人在玩，不启动"; exit 3
fi
STYLES="${2:-tiles lanterns steps wheel ink}"
bash ~/apps/shouwang/launch.sh
for i in $(seq 1 60); do (echo > /dev/tcp/127.0.0.1/9878) 2>/dev/null && break; sleep 1; done
sleep 12            # 第一次启动要编译着色器，读早了 ui 会返回空
echo "画面: $(rc "size" 1 | head -n 1)   包: $(sha256sum "$HOME/apps/shouwang/shouwang.x86_64" | cut -c1-16)…"
rc "call pad_adapter.gd debug_unlock_all" >/dev/null
target=""
for attempt in 1 2 3; do
	target=$(rc "ui" 1 10 30 | grep -F "<PlayButton>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}')
	[ -n "$target" ] && break
	sleep 3
done
[ -n "$target" ] || { echo "标题页上找不到巡夜按钮（游戏可能已经被别人操作过了），停在这里"; exit 4; }
rc "click $target" 1 >/dev/null
sleep 6
rc "call pad_adapter.gd debug_pick_character 0" 1 >/dev/null
sleep 16
echo "平时一帧多长（进游戏、什么都不做）：$(rc "call pad_adapter.gd debug_frame_time 3" 4 10 | sed 's/^OK called debug_frame_time -> //')"
for S in $STYLES; do
	rc "call pad_adapter.gd debug_transition $S" 1 >/dev/null
	# 放两遍：头一趟不判，第二趟的数才是稳的（见 SceneTransitionControl.report）
	for k in 1 2; do
		rc "call pad_adapter.gd debug_transition_test 0.5" 1 >/dev/null
		sleep 4
	done
	echo "$S：$(rc "call pad_adapter.gd debug_transition 0" 1 | sed 's/^OK called debug_transition -> //' | cut -c1-220)"
done
echo "随机：$(rc "call pad_adapter.gd debug_transition random" 1 | sed 's/^OK called debug_transition -> //')"
errs=$(grep -c 'SCRIPT ERROR' "$HOME/apps/shouwang/game.log" 2>/dev/null)
echo "日志里的报错: SCRIPT ERROR=${errs:-0}"

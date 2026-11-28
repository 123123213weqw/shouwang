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
STYLES="${2:-ink}"
bash ~/apps/shouwang/launch.sh
for i in $(seq 1 60); do (echo > /dev/tcp/127.0.0.1/9878) 2>/dev/null && break; sleep 1; done
# 新包第一次启动要重新编译着色器，开场动画放得慢：等到巡夜按钮出现为止（最多等一分半钟），开场放完按钮才露出来
echo "画面: $(rc "size" 1 | head -n 1)   包: $(sha256sum "$HOME/apps/shouwang/shouwang.x86_64" | cut -c1-16)…"
rc "call pad_adapter.gd debug_unlock_all" >/dev/null
target=""
for attempt in $(seq 1 45); do
	target=$(rc "ui" 1 10 30 | grep -F "<PlayButton>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}')
	[ -n "$target" ] && break
	sleep 2
done
[ -n "$target" ] || { echo "标题页上找不到巡夜按钮（游戏可能已经被别人操作过了），停在这里"; exit 4; }
rc "click $target" 1 >/dev/null
sleep 6
rc "call pad_adapter.gd debug_pick_character 0" 1 >/dev/null
sleep 16
# 遥控不等带等待的函数：debug_frame_time 发出去就返回，量在游戏里做，过几秒再取结果
rc "call pad_adapter.gd debug_frame_time 3" 1 >/dev/null
sleep 5
echo "平时一帧多长（进游戏、什么都不做）：$(rc "call pad_adapter.gd debug_frame_time" 1 | sed 's/^OK called debug_frame_time -> //')"
for S in $STYLES; do
	echo "固定成 $S：$(rc "call pad_adapter.gd debug_transition $S" 1 | sed 's/^OK called debug_transition -> //')"
	# 放三遍：遥控不等"就地放"做完，每遍放完等几秒。头一趟不判，报的是最后一遍的数（见 SceneTransitionControl.report）
	for k in 1 2 3; do
		rc "call pad_adapter.gd debug_transition_test 0.5" 1 >/dev/null
		sleep 4
	done
	for back in 0 1 2; do
		echo "  第 $((3 - back)) 遍：$(rc "call pad_adapter.gd debug_transition 0 $back" 1 | sed 's/^OK called debug_transition -> //' | cut -c1-220)"
	done
done
echo "改回平时那一种：$(rc "call pad_adapter.gd debug_transition ink" 1 | sed 's/^OK called debug_transition -> //')"
# 真的换两回关（跳到别的关），量真实换关时的数：和就地放的不一样，盖住是从水车那儿开始的
for lv in 4 7; do
	rc "call pad_adapter.gd debug_goto_level $lv" 1 >/dev/null
	sleep 5
done
for back in 0 1; do
	echo "  真换关（往回数第 $back 趟）：$(rc "call pad_adapter.gd debug_transition 0 $back" 1 | sed 's/^OK called debug_transition -> //' | cut -c1-220)"
done
errs=$(grep -c 'SCRIPT ERROR' "$HOME/apps/shouwang/game.log" 2>/dev/null)
echo "日志里的报错: SCRIPT ERROR=${errs:-0}"

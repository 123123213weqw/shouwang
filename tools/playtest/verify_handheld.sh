#!/bin/bash
# 在掌机上试跑：启动 → 标题页 → 选人页 → 进游戏 → 跳到棋盘最大的第 12 关摆一棋盘的东西，每一步截一张全分辨率的图，
# 最后把游戏关掉。截图写到掌机的 /tmp/hh_*.png。
#
# 会占住掌机的屏幕，还会重启、关掉正在跑的游戏：只能在确认没人在掌机上玩的时候用。
#   游戏正在跑的时候直接停下，不动它。
#   必须带上参数 yes（确认过没人在玩）才会启动，不然只报状态就退出。
# 用法（从本机把脚本送过去执行）: ssh -J WZU_V100 RWKV_Tail 'bash -s yes' < tools/playtest/verify_handheld.sh
# 调试遥控只监听掌机本机的 127.0.0.1:9878（游戏里 pad_adapter.gd）
rc() { exec 3<>/dev/tcp/127.0.0.1/9878 || return 1; printf "%s\n" "$1" >&3; sleep "${2:-0.6}"; timeout "${3:-8}" cat <&3 | grep -v '^$' | head -n "${4:-6}"; exec 3>&- 3<&-; }
snap() { rc "full" 1 >/dev/null 2>&1; cp /tmp/sw_snap.png "/tmp/hh_$1.png"; echo "截图 hh_$1.png"; }
LOG=~/apps/shouwang/game.log
if pgrep -x shouwang.x86_64 >/dev/null; then
	echo "掌机上的游戏正在运行，不做试跑（不动它）"; exit 2
fi
if [ "${1:-}" != yes ]; then
	echo "没有带参数 yes：没确认过掌机上没人在玩，不启动游戏"; exit 3
fi
bash ~/apps/shouwang/launch.sh
for i in $(seq 1 60); do (echo > /dev/tcp/127.0.0.1/9878) 2>/dev/null && break; sleep 1; done
sleep 12            # 第一次启动要编译着色器，读早了 ui 会返回空
echo "画面: $(rc "size" 1 | head -n 1)   （调试端口在第 $i 秒起来）"
snap title
# 按钮表偶尔读不到（游戏正忙，遥控那一头超时返回空）：再试两次
target=""
for attempt in 1 2 3; do
	target=$(rc "ui" 1 10 30 | grep -F "<PlayButton>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}')
	[ -n "$target" ] && break
	sleep 3
done
if [ -z "$target" ]; then echo "标题页上找不到 PlayButton 按钮（游戏可能已经被别人操作过了），停在这里，不再往下做"; rc "ui" 1 8 20; exit 4; fi
rc "call pad_adapter.gd debug_unlock_all" 1
rc "click $target" 1 >/dev/null
sleep 6
snap select
rc "call pad_adapter.gd debug_pick_character 0" 1
sleep 16
echo "第 1 关: $(rc "call pad_adapter.gd debug_state" 1 | sed 's/OK called debug_state -> //' | cut -c1-150)"
snap level1
rc "call pad_adapter.gd debug_goto_level 12" 1
sleep 16
rc "call pad_adapter.gd debug_spawn_all 0" 1 >/dev/null
rc "spawn res://resources/heart.tres 2" 1 >/dev/null
rc "spawn res://resources/upgrades/chest.tres 2" 1 >/dev/null
rc "spawn res://resources/upgrades/combooo.tres 8" 1 >/dev/null
sleep 6
echo "第 12 关: $(rc "call pad_adapter.gd debug_state" 1 | sed 's/OK called debug_state -> //' | cut -c1-150)"
snap level12
errs=$(grep -c 'SCRIPT ERROR' "$LOG" 2>/dev/null)
others=$(grep -c '^ERROR' "$LOG" 2>/dev/null)
echo "日志里的报错: SCRIPT ERROR=${errs:-0}   ERROR=${others:-0}"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" 2>/dev/null | grep -A4 "SCRIPT ERROR\|^ERROR" | head -n 12 | cut -c1-200
for p in $(pgrep -x shouwang.x86_64); do kill "$p" 2>/dev/null; done
echo "试跑结束，游戏已关掉"

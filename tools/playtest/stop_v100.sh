#!/bin/bash
# 停掉游戏和虚拟显示，只动自己这个实例的。
# 用法: stop_v100.sh [工程目录]
#   主要认启动时记下的进程号（$SW_RUN/game.pid）；给了工程目录的话，再按它兜底找一遍没记上的游戏进程
RUN="${SW_RUN:-/home/wzu/shouwang-run}"
n=0
if [ -f "$RUN/game.pid" ]; then
	pid=$(cat "$RUN/game.pid")
	if kill "$pid" 2>/dev/null; then n=$((n + 1)); fi
	# 等它退出；两秒还不走就强杀
	for i in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
	kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
fi
if [ -n "$1" ] && [ -d "$1" ]; then
	for p in $(pgrep -u wzu -f -- "--path ${1%/} "); do kill "$p" 2>/dev/null && n=$((n + 1)); done
fi
if [ -f "$RUN/xvfb.pid" ]; then kill "$(cat "$RUN/xvfb.pid")" 2>/dev/null; rm -f "$RUN/xvfb.pid"; fi
if [ -f "$RUN/display" ]; then rm -rf "/tmp/sw-disp-$(cat "$RUN/display").lock"; rm -f "$RUN/display"; fi
rm -f "$RUN/game.pid"
echo "这个实例的 Godot 进程：停掉了 $n 个"

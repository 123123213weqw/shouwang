#!/bin/bash
# 在掌机上从应用菜单启动《守望》，全屏。每次启动都先关掉上一次没退干净的游戏。
# 部署脚本（tools/playtest/deploy_handheld.sh）会把它装到掌机的 ~/apps/shouwang/launch.sh，可执行文件在同一个目录里。
BIN="$HOME/apps/shouwang/shouwang.x86_64"
RUN="$HOME/apps/shouwang"
for p in $(pgrep -u "$(id -un)" -x shouwang.x86_64); do kill "$p" 2>/dev/null; done
sleep 1
cd "$HOME"
export XDG_RUNTIME_DIR="/run/user/$(id -u)" WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
setsid nohup "$BIN" --fullscreen </dev/null >"$RUN/game.log" 2>&1 &
echo launched

#!/bin/bash
# 向游戏里的调试遥控发命令（每个参数是一条完整的命令），打印回复。
# 环境变量：SW_DEBUG_PORT 端口（默认 9878）；RC_WAIT 发完每条命令后等几秒（默认 1）；RC_READ 一共读几秒（默认 3）
exec 3<>/dev/tcp/127.0.0.1/"${SW_DEBUG_PORT:-9878}" || exit 1
for cmd in "$@"; do printf "%s\n" "$cmd" >&3; sleep "${RC_WAIT:-1}"; done
timeout "${RC_READ:-3}" cat <&3

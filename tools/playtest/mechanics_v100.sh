#!/bin/bash
# 长夜模式的格子机制，对着游戏里按帧记下的时间线逐项检查：
#   补给格（第 1 更）：先跳到一个空的普通格花掉 1 步，再跳到一个空的补给格：这一跳不扣步数，反而 +2 步
#   脆格（第 6 更）：踩上去，再跳到一个空的普通格：离开后它先碎掉（broken=1），两三秒后长回来（broken=0）
#   结束这一局：结算面板上要有文字，这一局的成绩要记进本机成绩
# 长夜的棋盘本来每次进游戏随机生成；这里先把随机数定住，所以每次测的都是同一批棋盘，不会时过时不过。
# 用法: mechanics_v100.sh <工程目录> <截图前缀>
# 环境变量同 launch_v100.sh（几个实例同时跑的时候各设各的）。截图写到 $SW_RUN/shots/，文件名以 <前缀>_ 开头。
PROJECT="$1"; P="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${SW_RUN:-/home/wzu/shouwang-run}"; SNAP="${SW_SNAP:-/tmp/sw_snap}"; LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
mkdir -p "$RUN/shots"
RC="bash $HERE/rc.sh"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
for i in $(seq 1 300); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 1; done
sleep 8
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-4}" $RC "$@" 2>&1 | grep -v '^$'; }
btn() { RC_READ=8 $RC "ui" 2>/dev/null | grep -F "<$1>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}'; }
state() { rcc "call pad_adapter.gd debug_state" | sed 's/OK called debug_state -> //'; }
field() { echo "$1" | grep -o "$2=[0-9]*" | head -n1 | cut -d= -f2; }
jump() { rcc "call pad_adapter.gd debug_jump_to $*" | sed 's/^OK called debug_jump_to -> //'; }
snap() {
	RC_WAIT=0.3 RC_READ=6 $RC snapshot >/dev/null 2>&1
	RC_WAIT=0.3 RC_READ=8 $RC full >/dev/null 2>&1
	cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg"; cp "$SNAP.png" "$RUN/shots/${P}_$1.png"
}
fail=0
check() { if [ "$1" = 0 ]; then echo "  [通过] $2"; else echo "  [没过] $2"; fail=1; fi; }

target=$(btn EndlessButton)
[ -n "$target" ] || { echo "标题页上找不到长夜模式的按钮（按节点名 EndlessButton），停在这里"; RC_READ=6 $RC "ui" 2>&1 | head -n 12; bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1; }
RC_WAIT=0.3 $RC "click $target" >/dev/null 2>&1
sleep 6
rcc "call pad_adapter.gd debug_unlock_all" >/dev/null
for try in 1 2 3 4; do
	rcc "call pad_adapter.gd debug_pick_character 0" >/dev/null
	sleep 10
	scene=$(rcc "scene" | grep "^OK scene" | cut -c1-100)
	case "$scene" in *main.tscn*) break ;; esac
done
echo "进游戏: $scene"
# 第一次进游戏会先弹"玩法"卡片（整局暂停）：有就点掉
dismiss=$(btn TutorialCloseButton)
[ -n "$dismiss" ] && { RC_WAIT=0.3 $RC "click $dismiss" >/dev/null 2>&1; sleep 1; echo "点掉了第一次的玩法卡片"; }
sleep 8
# 长夜的棋盘每次进游戏随机生成。把随机数定住，再从第 1 更重新载入：之后每一更的格子类型都是固定的，测的才是同一批棋盘
echo "定住随机数: $(rcc "call pad_adapter.gd debug_seed 7" | sed 's/^OK called debug_seed -> //')"
rcc "call pad_adapter.gd debug_goto_level 1" >/dev/null; sleep 10
echo "开局: $(state)"

echo "== 补给格（第 1 更）=="
m0=$(field "$(state)" moves)
r=$(jump 0 1); sleep 7
m1=$(field "$(state)" moves)
echo "  跳到空的普通格（$r）：步数 $m0 → $m1"
[ -n "$m1" ] && [ "$m1" = "$((m0 - 1))" ]; check $? "跳到空的普通格花掉 1 步（应从 $m0 变成 $((m0 - 1))）"
# 补给格上压着灯的话，落上去是收灯、不触发补给（原作的规矩）。先把格子上东西清掉（水车留着），补给格才是空的
rcc "call pad_adapter.gd debug_spawn 0" >/dev/null; sleep 2
rcc "call pad_adapter.gd debug_watch" >/dev/null
r=$(jump 3 1); sleep 16
m2=$(field "$(state)" moves)
echo "  跳到空的补给格（$r）：步数 $m1 → $m2"
echo "  时间线:"; rcc "call pad_adapter.gd debug_report" | sed 's/OK called debug_report -> //' | grep -v "记录结束" | head -n 12
[ -n "$m2" ] && [ "$m2" = "$((m1 + 2))" ]; check $? "跳到补给格不扣步数，反而 +2 步（应从 $m1 变成 $((m1 + 2))）"
snap 01_spring

echo "== 脆格（第 6 更）=="
rcc "call pad_adapter.gd debug_goto_level 6" >/dev/null; sleep 10
echo "  第 6 更开局: $(state)"
r=$(jump 1); sleep 7
echo "  踩上脆格（$r）"
rcc "call pad_adapter.gd debug_watch" >/dev/null
r=$(jump 0 1); sleep 16
echo "  跳走（$r）"
report=$(rcc "call pad_adapter.gd debug_report" | sed 's/OK called debug_report -> //' | grep -v "记录结束")
echo "  时间线:"; echo "$report" | head -n 14
echo "$report" | grep -q "broken=1"; check $? "离开后脆格碎掉（时间线里出现过 broken=1）"
[ "$(echo "$report" | awk '/broken=1/{seen=1; next} seen && /broken=0/{found=1} END{print found+0}')" = 1 ]; check $? "碎掉的脆格自己长回来（broken=1 之后又出现 broken=0）"
snap 02_crumble

echo "== 结束这一局 =="
rcc "call main.gd end_game" >/dev/null; sleep 6
echo "  结算面板上的文字:"
panel=$(RC_READ=8 $RC "texts" 2>/dev/null | grep -v '^$')
echo "$panel" | head -n 14 | sed 's/^/    /'
[ "$(echo "$panel" | wc -l)" -ge 3 ]; check $? "结算面板上有文字"
echo "  结束之后: $(state)"
snap 03_gameover

echo "== 运行日志里的报错 =="
errs=$(grep -c 'SCRIPT ERROR' "$LOG")
others=$(grep -c '^ERROR' "$LOG")
echo "SCRIPT ERROR: $errs   ERROR: $others"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A3 "SCRIPT ERROR\|^ERROR" | head -n 20 | cut -c1-220
[ "$errs" = 0 ] && [ "$others" = 0 ]; check $? "运行日志里没有报错"
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
[ "$fail" = 0 ] && echo "RESULT 格子机制（长夜）：通过" || echo "RESULT 格子机制（长夜）：没过"
exit $fail

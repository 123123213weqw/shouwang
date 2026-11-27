#!/bin/bash
# 让机器人真机玩一局（真渲染、真计时、真规则），玩到结束或者打到指定的关数。
#   机器人 1：照着摆棋的那条路线走。它必须一步不错、每关都过：哪一跳引擎说跳不到，就是摆棋的模型和引擎对不上（AUTOPLAY_BROKEN）
#   机器人 2：贪心打法（够得着的灯里挑最近的），当作"随手玩的玩家"的下限。它输赢都行，看的是成绩
# 用法: autoplay_v100.sh <工程目录> <campaign|endless> <1|2> [最多打到第几关] [截图前缀]
# 环境变量同 launch_v100.sh。每换一关截一张图；结束时打印一行结果（JSON）。
# 退出码：机器人 1 没通关 / 没打到指定的关数、或者出现过"跳不到"、或者日志里有报错，就是 1
PROJECT="$1"; MODE="$2"; BOT="${3:-1}"; MAX="${4:-999}"; P="${5:-auto_${MODE}_$BOT}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="${SW_RUN:-$HOME/shouwang-run}"; SNAP="${SW_SNAP:-/tmp/sw_snap}"; LOG="${SW_LOG:-/tmp/shouwang_run.log}"
PORT="${SW_DEBUG_PORT:-9878}"
TIMEOUT="${SW_AUTO_TIMEOUT:-1500}"
mkdir -p "$RUN/shots"
RC="bash $HERE/rc.sh"
bash "$HERE/launch_v100.sh" "$PROJECT" || exit 1
for i in $(seq 1 300); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 1; done
sleep 8
rcc() { RC_WAIT="${RC_WAIT:-1}" RC_READ="${RC_READ:-4}" $RC "$@" 2>&1 | grep -v '^$'; }
btn() { RC_READ=8 $RC "ui" 2>/dev/null | grep -F "<$1>" | head -n1 | sed -E 's/^BTN \[([0-9.-]+),([0-9.-]+) ([0-9]+)x([0-9]+)\].*/\1 \2 \3 \4/' | awk '{print int($1 + $3/2), int($2 + $4/2)}'; }
state() { rcc "call pad_adapter.gd debug_state" | sed 's/OK called debug_state -> //'; }
snap() {
	RC_WAIT=0.3 RC_READ=6 $RC snapshot >/dev/null 2>&1
	RC_WAIT=0.3 RC_READ=8 $RC full >/dev/null 2>&1
	cp "$SNAP.jpg" "$RUN/shots/${P}_$1.jpg"; cp "$SNAP.png" "$RUN/shots/${P}_$1.png"
}

target=$(btn PlayButton); [ "$MODE" = endless ] && target=$(btn EndlessButton)
[ -n "$target" ] || { echo "标题页上找不到模式的按钮，停在这里"; bash "$HERE/stop_v100.sh" "$PROJECT"; exit 1; }
RC_WAIT=0.3 $RC "click $target" >/dev/null 2>&1
sleep 6
rcc "call pad_adapter.gd debug_unlock_all" >/dev/null
scene=""
for try in 1 2 3 4; do
	rcc "call pad_adapter.gd debug_pick_character 0" >/dev/null
	sleep 10
	scene=$(rcc "scene" | grep "^OK scene" | cut -c1-100)
	case "$scene" in *main.tscn*) break ;; esac
done
echo "进游戏: $scene"
dismiss=$(btn TutorialCloseButton)      # 第一次进游戏会先弹"玩法"卡片（整局暂停）：有就点掉
[ -n "$dismiss" ] && { RC_WAIT=0.3 $RC "click $dismiss" >/dev/null 2>&1; sleep 1; echo "点掉了第一次的玩法卡片"; }
sleep 6
echo "难度: $(rcc "call pad_adapter.gd debug_rules_state" | sed 's/^OK called debug_rules_state -> //' | cut -d'|' -f1 | tr -d '\n')"
# 有夜巡的档：进关以后脚本先空等了十几秒，蜡已经烧掉一截。给机器人续上一支长的（跳第一下的时侯自动回到一支蜡的长度）。
# 没有夜巡的档这一步什么都不变。想试"想得久会怎样"，用 SW_AUTO_PACE 设每步等多久，别靠这里的空等
rcc "call pad_adapter.gd debug_night 90" >/dev/null
rcc "call pad_adapter.gd debug_autoplay $BOT $MAX"
snap 01_start

last=""; t0=$(date +%s); result=""
while :; do
	if grep -a -q "AUTOPLAY_RESULT" "$LOG"; then break; fi
	[ $(( $(date +%s) - t0 )) -gt "$TIMEOUT" ] && { echo "等了 $TIMEOUT 秒还没玩完，不等了"; break; }
	idx=$(state | sed -E 's/.* index=([0-9]+) .*/\1/')
	if [ "$idx" != "$last" ] && [ "$idx" = "$(echo "$idx" | sed -E 's/[0-9]+//')" ]; then :; fi
	if [ -n "$idx" ] && [ "$idx" != "$last" ]; then sleep 5; snap "L$((idx + 1))"; last="$idx"; fi
	sleep 4
done
rcc "call pad_adapter.gd debug_autoplay 0" >/dev/null
sleep 3
snap 99_end
echo "== 机器人的记录（每关：开头分数 → 这关里踩空数的先后）=="
line=$(grep -a "AUTOPLAY_RESULT" "$LOG" | tail -n 1 | sed 's/.*AUTOPLAY_RESULT //')
if [ -n "$line" ] && command -v python3 >/dev/null; then
	printf '%s' "$line" | python3 -c '
import json, sys
r = json.loads(sys.stdin.read())
print("结果: %s   走到第 %s 关   总分 %s   重来 %s 次   跳不到 %s 次   放灯 %s 次   难度 %s   机器人 %s   每步 %s 秒" % (
    r.get("result"), r.get("reached"), r.get("score"), r.get("retries"), r.get("broken"), r.get("placed", 0), r.get("ruleset"), r.get("mode"), r.get("pace", 0.4)))
for lv in r.get("levels", []):
    m = lv.get("missteps", [])
    print("  第 %2d 关 %-10s 开头分数 %5d，带着 %s 步进来，收 %s 盏，风 %s   踩空: %s   这关错了 %d 步" % (
        lv.get("level"), lv.get("name"), lv.get("score0"), lv.get("moves0"), lv.get("lamps"), lv.get("wind"), " → ".join(str(x) for x in m) or "—", (m[-1] if m else 0)))
'
else
	echo "没有拿到机器人的记录（${line:-空})"
fi
broken=$(grep -a -c "AUTOPLAY_BROKEN" "$LOG")
[ "$broken" = 0 ] || grep -a "AUTOPLAY_BROKEN" "$LOG" | head -n 10 | cut -c1-200
echo "== 换关后机器人多久动手（灯摆得慢的关，机器人会等它载入完）=="
grep -a "AUTOPLAY_WAIT" "$LOG" | cut -c1-160 | head -n 12
slow=$(grep -a -c "AUTOPLAY_WAIT" "$LOG")
[ "$slow" = 0 ] && echo "每一关都在机器人动手之前就载入完了"
if [ -n "${SW_AUTO_TRACE:-}" ]; then echo "== 机器人每一步 =="; grep -a "AUTOPLAY_STEP" "$LOG" | cut -c1-140; fi
echo "== 运行日志里的报错 =="
errs=$(grep -c 'SCRIPT ERROR' "$LOG")
others=$(grep -c '^ERROR' "$LOG")
echo "SCRIPT ERROR: $errs   ERROR: $others"
sed "s/\x1b\[[0-9;]*m//g" "$LOG" | grep -A4 "SCRIPT ERROR\|^ERROR" | head -n 20 | cut -c1-220
cp "$LOG" "$RUN/shots/${P}_run.log"
bash "$HERE/stop_v100.sh" "$PROJECT"
fail=0
[ "$errs" = 0 ] && [ "$others" = 0 ] || { echo "[没过] 日志里有报错"; fail=1; }
[ "$broken" = 0 ] || { echo "[没过] 有 $broken 次照着路线走却跳不到"; fail=1; }
badboard=$(grep -a -c "AUTOPLAY_BOARD_BAD" "$LOG")
[ "$badboard" = 0 ] || { echo "[没过] 有 $badboard 次查出棋盘上的登记不对（同一盏灯登记在几个格子上，或者格子指着一个已经不存在的灯）"; fail=1; }
# 贪心打法走进死路（剩下的灯它够不着）的时侯机器人会自己收工，记作 stuck：那是它的成绩，不算测试没过
if [ "$BOT" = 1 ]; then
	[ -z "$line" ] && { echo "[没过] 机器人没有玩完"; fail=1; }
	echo "$line" | grep -q '"result":"stuck' && { echo "[没过] 照着路线走的机器人没处可去了：摆好的路线它走不完"; fail=1; }
	if [ "$MODE" = campaign ]; then
		echo "$line" | grep -q '"result":"completed"' || { echo "[没过] 照着路线走没能通关"; fail=1; }
	elif [ "$MAX" != 999 ]; then
		echo "$line" | grep -q "reached level limit $MAX" || { echo "[没过] 照着路线走没能打到第 $MAX 关"; fail=1; }
	fi
fi
[ "$fail" = 0 ] && echo "RESULT 机器人试玩（$MODE，机器人 $BOT）：通过" || echo "RESULT 机器人试玩（$MODE，机器人 $BOT）：没过"
exit $fail

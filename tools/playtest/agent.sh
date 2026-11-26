#!/bin/bash
# 在 V100（没有显示器的编译服务器）上测试工程的入口。在工程根目录下用：
#   tools/playtest/agent.sh <标签> <命令>
# 每个标签在 V100 上有一套自己的环境（/home/wzu/shouwang-agents/<标签>/）：工程目录、调试端口、虚拟显示各用各的，
# 互不影响，所以几个任务可以同时跑。标签是 base 或者 a1 到 a9；base 是带着音频的底版，别的标签建环境时从它复制音频，
# 所以第一次用要先跑一次 tools/playtest/agent.sh base setup。平时只用一个标签的话用 a7。
# 命令：
#   setup                   在 V100 上建这个标签的目录，上传测试脚本
#   sync                    把当前工程同步到 V100 上这个标签的工程目录（音频不传，从 base 复制）
#   import                  在 V100 上导入两遍，打印报错（不是 0 就是有问题）
#   boards                  棋盘的自动测试（不开窗口，直接跑脚本）
#   flow [campaign|endless] [前缀]     过关流程：真实地走完第一关（和最后一关），中间的关卡确认都能载入
#   aspect [分辨率] [前缀]   主线 12 关各载入一遍，量棋盘是不是整个在画面里（默认 1152x720，掌机的比例）
#   mechanics [前缀]         长夜模式的格子机制：补给格加步数、脆格碎掉后长回来、结算面板和本机成绩
#   auto [campaign|endless] [1|2] [最多打到第几关] [前缀]
#   opening [A|B|D] [秒数] [每秒几张]   录一段开场动画（真正的开机画面），帧取回到 builds/opening/<方案>/
#   lobby [秒数=20] [每秒几张=20]   录一段大厅（标题页）的背景：那条夜里的河、河上的灯、指针划过和挪焦点时荡开的涟漪，
#                             帧取回到 builds/lobby/rec/，再拼视频：tools/playtest/assemble_lobby.sh
#                             机器人真机玩一局。1 = 照着摆好的路线走（必须一步不错、关关都过）；2 = 贪心打法（随手玩的玩家的下限）
#   drive <步骤文件> [前缀]  按步骤文件操作游戏并截图（步骤怎么写见 drive_v100.sh 的开头）
#   export                  在 V100 上把工程导出成 Linux 可执行文件（给掌机用），放在 V100 的 shouwang-agents/<标签>/shouwang.x86_64
#   fetch                   把导出的可执行文件取回到本地 builds/linux/shouwang.x86_64
#   smoke <步骤文件> [前缀]  试跑导出来的可执行文件（先 export）：启动 → 按步骤操作 → 截图取回，同 drive
#   pull <前缀>             把 V100 上这个标签的截图取回来（文件名以 <前缀>_ 开头的）
#   stop                    只停掉这个标签在 V100 上的游戏
#   clean                   停掉并删掉 V100 上这个标签的目录（做完以后一定要执行，base 不用删）
#   all                     一轮完整回归：import → boards → flow campaign → flow endless → aspect → mechanics → auto campaign 1，哪一步没过就停在那一步
# 截图取回到 $SW_OUT（默认 builds/shots/<标签>/）。开了游戏的命令哪一步没过，退出码就不是 0。
# 临时指定玩法方案：SW_RULESET=hard tools/playtest/agent.sh a7 auto campaign 2（六套的 id 见 resources/rulesets/）
# 机器人每一步都打进日志（查它为什么跳不到的时侯用）：SW_AUTO_TRACE=1 tools/playtest/agent.sh a7 auto campaign 1
# 游戏里背景的三种布局（1 长河、2 远岸、3 月下；平时是月下）：SW_STAGE=2 tools/playtest/agent.sh a7 drive tools/playtest/steps_stage.txt 远岸
#   versus <1..5> [秒数=24] [每秒几张=20]   录一局对战（1 抢灯、2 追影、3 夺岸、4 轮战、5 对弈），主角交给机器人打，
#                             帧取回到 builds/versus/<编号>/，再拼视频：tools/playtest/assemble_versus.sh <编号>
#   stage <布局 1|2|3> [秒数=18] [每秒几张=20]   录一段游戏里的背景：进游戏、在棋盘上跳几下（河灯在漂、落地荡开的那圈），
#                             帧取回到 builds/stage/<布局>/，再拼视频：tools/playtest/assemble_stage.sh <布局>
# 让机器人换关后只等 0.2 秒（平时 1.5 秒），试它在灯还没摆完的时侯会不会乱动：SW_AUTO_EAGER=1 tools/playtest/agent.sh a7 auto campaign 1
# 渲染方式默认是游戏真正用的 Forward+（跑在服务器自带的显卡上，一个实例占 264 MB 显存）；SW_RENDERER=gl 是软件 OpenGL，不碰显卡
TAG="$1"; CMD="$2"
case "$TAG" in
	base) IDX=0 ;;
	a[1-9]) IDX="${TAG#a}" ;;
	*) echo "标签只能是 base 或者 a1 到 a9"; exit 1 ;;
esac
set -o pipefail
SSH="ssh -o ConnectTimeout=30 -o BatchMode=yes -o ServerAliveInterval=15"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROOTS="/home/wzu/shouwang-agents"
REMOTE="$ROOTS/$TAG"
OUT="${SW_OUT:-$ROOT/builds/shots/$TAG}"
# 每个标签一套：端口 9910+编号，最多 5 个渲染线程，虚拟显示从 200+编号 试起
export SW_RUN="$REMOTE" SW_LOG="$REMOTE/run.log" SW_DEBUG_PORT="$((9910 + IDX))" SW_SNAP="/tmp/sw_snap_$TAG"
export SW_THREADS=5 SW_DISPLAYS="$((200 + IDX)) $((210 + IDX)) $((220 + IDX)) $((230 + IDX)) $((240 + IDX)) $((250 + IDX))"
# 默认用游戏真正的渲染方式（Forward+，跑在服务器自带的 NVIDIA 显卡上）。不要去设 SW_GPU：这台机器上编号 1 是软件渲染、
# 编号 2 起不来，只有默认的第 0 块卡可靠。不想碰显卡就设 SW_RENDERER=gl（软件 OpenGL，画面略有差别）
export SW_RES="${SW_RES:-1152x720}" SW_RENDERER="${SW_RENDERER:-nvidia}"
export SW_AUTO_TRACE="${SW_AUTO_TRACE:-}"    # 设了（任何值）就把自动试玩的机器人每一步都打进游戏日志
export SW_AUTO_EAGER="${SW_AUTO_EAGER:-}"    # 设了（任何值）机器人换关后只等 0.2 秒就动手（平时 1.5 秒）
export SW_OPENING="${SW_OPENING:-}"          # 临时指定开场动画（A / B / C / D），不写存档
export SW_BOOT_WAIT="${SW_BOOT_WAIT:-}"      # 游戏起来以后第一步之前等几秒才动手（平时 6 秒；查开场的时侯设 1）
export SW_OPENING_TRACE="${SW_OPENING_TRACE:-}"   # 设了就把开场每一处创建的时刻打进日志（查卡顿用）
export SW_RULESET="${SW_RULESET:-}"          # 临时指定玩法方案（灯谱 dealt / 流水 flow / 长明 hard / 万灯 party / 疾走 rush / 旧灯 legacy），不写存档
export SW_STAGE="${SW_STAGE:-}"              # 游戏里背景的布局：1 长河、2 远岸、3 月下；不写是平时用的「月下」，给 0 是原来那块网纹的水
pull() {
	mkdir -p "$OUT"
	rsync -a -e "$SSH" --include "${1}_*" --exclude '*' "WZU_V100:$REMOTE/shots/" "$OUT/" && echo "截图已取回到 ${OUT}（文件名以 ${1}_ 开头）"
}
ENVS="SW_RUN=$SW_RUN SW_LOG=$SW_LOG SW_DEBUG_PORT=$SW_DEBUG_PORT SW_SNAP=$SW_SNAP SW_THREADS=$SW_THREADS SW_DISPLAYS='$SW_DISPLAYS' SW_RES=$SW_RES SW_RENDERER=$SW_RENDERER SW_RULESET=$SW_RULESET SW_AUTO_TRACE=$SW_AUTO_TRACE SW_AUTO_EAGER=$SW_AUTO_EAGER SW_OPENING=$SW_OPENING SW_BOOT_WAIT=$SW_BOOT_WAIT SW_OPENING_TRACE=$SW_OPENING_TRACE SW_STAGE=$SW_STAGE"
BIN="$REMOTE/shouwang.x86_64"
EXCLUDE="--exclude .git --exclude .godot --exclude builds --exclude .DS_Store --exclude *.tmp --exclude __pycache__ --exclude tools/playtest"
# 原作的两首曲子和音效很大，建环境的时侯从 base 复制过来，平时同步不传；开场动画的声音是我们自己的、很小，照常同步
[ "$TAG" != base ] && EXCLUDE="$EXCLUDE --include assets/audio/opening --include 'assets/audio/opening/***' --exclude 'assets/audio/*'"
case "$CMD" in
	setup)
		$SSH WZU_V100 "mkdir -p $REMOTE/project $REMOTE/bin $REMOTE/shots; if [ '$TAG' != base ] && [ ! -e $REMOTE/project/project.godot ] && [ -d $ROOTS/base/project ]; then cp -a $ROOTS/base/project/. $REMOTE/project/; fi" \
			&& scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT"/tools/playtest/{rc,launch_v100,stop_v100,drive_v100,snap_levels_v100,flowtest_v100,aspect_v100,mechanics_v100,autoplay_v100,record_opening_v100,record_lobby_v100,record_stage_v100,record_versus_v100}.sh "WZU_V100:$REMOTE/bin/" \
			&& echo "V100 上的环境已建好：${REMOTE}（端口 ${SW_DEBUG_PORT}，渲染线程 ${SW_THREADS}）" ;;
	sync)
		rsync -a --delete $EXCLUDE -e "$SSH" "$ROOT/" "WZU_V100:$REMOTE/project/" \
			&& echo "已同步到 ${REMOTE}/project" ;;
	# 同步过去再导入，Godot 会改写一部分 .import 文件（导入缓存的路径），也会给新脚本生成 .uid 文件：都取回来，仓库里存的才是对的
	import)
		$SSH WZU_V100 bash -s "$REMOTE" <<'REMOTE_SH'
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
R="$1"; cd "$R/project" || exit 1
$G --headless --path . --import > "$R/import1.log" 2>&1
$G --headless --path . --import > "$R/import2.log" 2>&1
e=$(grep -c 'SCRIPT ERROR' "$R/import2.log"); o=$(grep -c '^ERROR' "$R/import2.log")
echo "导入: SCRIPT ERROR=$e ERROR=$o（都应为 0）"
sed 's/\x1b\[[0-9;]*m//g' "$R/import2.log" | grep -A4 'SCRIPT ERROR\|^ERROR' | head -n 20 | cut -c1-220
# 再不开窗口启动一回（跑三帧就退）：自动加载的脚本和主场景都会被编译一遍。
# 导入那一遍只处理资源，脚本里有编译错误它不一定报（2026-11-25 就这样导出过一个脚本跑不起来的包）
timeout 90 $G --headless --path . --quit-after 3 > "$R/boot.log" 2>&1
p=$(grep -c 'SCRIPT ERROR\|is not compiling\|Failed to create an autoload' "$R/boot.log")
echo "启动检查: 脚本报错 $p 条（应为 0）"
sed 's/\x1b\[[0-9;]*m//g' "$R/boot.log" | grep -A4 'SCRIPT ERROR\|is not compiling\|Failed to create an autoload' | head -n 24 | cut -c1-220
[ "$e" = 0 ] && [ "$o" = 0 ] && [ "$p" = 0 ]
REMOTE_SH
		code=$?
		# 原作音频的 .import 本来就在仓库里，不用取；开场声音的 .import 是新导入出来的，要取回来
		rsync -a -e "$SSH" --exclude '.godot/' --include 'assets/audio/opening/' --include 'assets/audio/opening/*.import' --exclude 'assets/audio/*' --include '*/' --include '*.import' --include '*.uid' --exclude '*' "WZU_V100:$REMOTE/project/" "$ROOT/"
		exit $code ;;
	boards)
		$SSH WZU_V100 bash -s "$REMOTE" <<'REMOTE_SH'
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
cd "$1/project" || exit 1
$G --headless --path . --script res://tools/test_boards.gd > "$1/boards.log" 2>&1
code=$?
errs=$(grep -a -c 'SCRIPT ERROR\|^ERROR: Failed to load' "$1/boards.log")
grep -a 'RESULT\|^FAIL\|SCRIPT ERROR' "$1/boards.log" | head -n 30 | cut -c1-220
grep -a '共检查' "$1/boards.log"
# 测试脚本中途崩掉的时候 Godot 照样可能以 0 退出，所以日志里有没有脚本报错也要看
if [ "$code" = 0 ] && [ "$errs" = 0 ] && grep -a -q 'RESULT failures=0' "$1/boards.log"; then
	echo "RESULT 棋盘自动测试：通过"
else
	echo "RESULT 棋盘自动测试：没过（退出码 $code，脚本报错 $errs 条，完整日志在 $1/boards.log）"
	exit 1
fi
REMOTE_SH
		;;
	drive)
		STEPS="$3"; PREFIX="${4:-run}"
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$STEPS" "WZU_V100:$REMOTE/steps.txt" || exit 1
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/drive_v100.sh $REMOTE/project $REMOTE/steps.txt $PREFIX" | cut -c1-600
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	flow)
		MODE="${3:-campaign}"; PREFIX="${4:-flow_$MODE}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/flowtest_v100.sh $REMOTE/project $MODE $PREFIX" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	aspect)
		RES="${3:-1152x720}"; PREFIX="${4:-aspect}"
		$SSH WZU_V100 "SW_RES=$RES $ENVS bash $REMOTE/bin/aspect_v100.sh $REMOTE/project $PREFIX $RES" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	auto)
		MODE="${3:-campaign}"; BOT="${4:-1}"; MAXL="${5:-999}"; PREFIX="${6:-auto_${MODE}_$BOT}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/autoplay_v100.sh $REMOTE/project $MODE $BOT $MAXL $PREFIX" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	opening)
		WHICH="${3:-A}"; SECS="${4:-4.8}"; FPS="${5:-20}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/record_opening_v100.sh $REMOTE/project $WHICH $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/opening/$WHICH" && rm -f "$ROOT/builds/opening/$WHICH/"*.jpg
		rsync -a -e "$SSH" "WZU_V100:/tmp/sw_opening_$WHICH/" "$ROOT/builds/opening/$WHICH/" && echo "帧已取回到 builds/opening/$WHICH/（$(ls "$ROOT/builds/opening/$WHICH" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_opening.sh $WHICH"
		exit $code ;;
	lobby)
		SECS="${3:-20}"; FPS="${4:-20}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/record_lobby_v100.sh $REMOTE/project $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/lobby/rec" && rm -f "$ROOT/builds/lobby/rec/"*.jpg
		rsync -a -e "$SSH" "WZU_V100:/tmp/sw_lobby/" "$ROOT/builds/lobby/rec/" && echo "帧已取回到 builds/lobby/rec/（$(ls "$ROOT/builds/lobby/rec" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_lobby.sh $FPS"
		exit $code ;;
	stage)
		N="${3:-1}"; SECS="${4:-18}"; FPS="${5:-20}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/record_stage_v100.sh $REMOTE/project $N $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/stage/$N" && rm -f "$ROOT/builds/stage/$N/"*.jpg
		rsync -a -e "$SSH" "WZU_V100:/tmp/sw_stage_$N/" "$ROOT/builds/stage/$N/" && echo "帧已取回到 builds/stage/$N/（$(ls "$ROOT/builds/stage/$N" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_stage.sh $N $FPS"
		exit $code ;;
	versus)
		N="${3:-1}"; SECS="${4:-24}"; FPS="${5:-20}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/record_versus_v100.sh $REMOTE/project $N $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/versus/$N" && rm -f "$ROOT/builds/versus/$N/"*.jpg
		rsync -a -e "$SSH" "WZU_V100:/tmp/sw_versus_$N/" "$ROOT/builds/versus/$N/" && echo "帧已取回到 builds/versus/$N/（$(ls "$ROOT/builds/versus/$N" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_versus.sh $N"
		exit $code ;;
	mechanics)
		PREFIX="${3:-mechanics}"
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/mechanics_v100.sh $REMOTE/project $PREFIX" | cut -c1-900
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	export)
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT/tools/playtest/export_linux_v100.sh" "WZU_V100:$REMOTE/bin/" || exit 1
		$SSH WZU_V100 "bash $REMOTE/bin/export_linux_v100.sh $REMOTE/project $BIN" | cut -c1-400 ;;
	fetch)
		mkdir -p "$ROOT/builds/linux"
		rsync -a --partial -e "$SSH" "WZU_V100:$BIN" "$ROOT/builds/linux/shouwang.x86_64" && ls -la "$ROOT/builds/linux/shouwang.x86_64" | awk '{print "已取回到 builds/linux/shouwang.x86_64，" $5 " 字节"}' ;;
	smoke)
		STEPS="$3"; PREFIX="${4:-smoke}"
		$SSH WZU_V100 "test -x $BIN" || { echo "V100 上还没有导出的可执行文件，先跑 export"; exit 1; }
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$STEPS" "WZU_V100:$REMOTE/steps.txt" || exit 1
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/drive_v100.sh $BIN $REMOTE/steps.txt $PREFIX" | cut -c1-600
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	pull)
		[ -n "${3:-}" ] || { echo "用法: agent.sh $TAG pull <截图前缀>"; exit 1; }
		pull "$3" ;;
	stop)
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/stop_v100.sh $REMOTE/project" ;;
	clean)
		$SSH WZU_V100 "$ENVS bash $REMOTE/bin/stop_v100.sh $REMOTE/project; rm -rf $REMOTE /tmp/sw_snap_$TAG.jpg /tmp/sw_snap_$TAG.png /tmp/sw_snap_${TAG}_P*.png; echo \"已删除 V100 上的 $REMOTE\"" ;;
	all)
		for step in import boards "flow campaign" "flow endless" aspect mechanics "auto campaign 1"; do
			echo "========== $step =========="
			"$0" "$TAG" $step || { echo "RESULT 完整回归：没过，停在「$step」"; exit 1; }
		done
		echo "RESULT 完整回归：通过" ;;
	*) echo "不认识的命令: ${CMD}"; exit 1 ;;
esac

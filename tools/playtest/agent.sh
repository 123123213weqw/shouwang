#!/bin/bash
# 在 V100（没有显示器的编译服务器）上测试工程的入口。在工程根目录下用：
#   tools/playtest/agent.sh <标签> <命令>
# 每个标签在服务器上有一套自己的环境（家目录下的 shouwang-agents/<标签>/）：工程目录、调试端口、虚拟显示各用各的，
# 互不影响，所以几个任务可以同时跑。标签是 base 或者 a1 到 a9；base 是带着音频的底版，别的标签建环境时从它复制音频，
# 所以第一次用要先跑一次 tools/playtest/agent.sh base setup。平时只用一个标签的话用 a7。
# 命令：
#   setup                   在 V100 上建这个标签的目录，上传测试脚本
#   sync                    把当前工程同步到 V100 上这个标签的工程目录（音频不传，从 base 复制）
#   rates [局数=200] [每步想几秒=1.0] [档的id，逗号隔开] ['set=名字=值 …']   难度四档的过关率：机器人（随手玩的打法）每一档打多少局、
#                             每关过了多少（tools/tier_rates.gd）。最后的参数临时改 .tres 里的数再量，例如 'set=moves_cap_add=0 set=moves_bonus=2'
#   check                   只检查脚本解析不解析得过，报出哪一行有错（比导入快；写代码的时侯先过这一道）
#   import                  在 V100 上导入两遍，打印报错（不是 0 就是有问题）
#   boards                  棋盘的自动测试（不开窗口，直接跑脚本）
#   flow [campaign|endless] [前缀]     过关流程：真实地走完第一关（和最后一关），中间的关卡确认都能载入
#   aspect [分辨率] [前缀]   主线 12 关各载入一遍，量棋盘是不是整个在画面里（默认 1152x720，掌机的比例）
#   mechanics [前缀]         长夜模式的格子机制：补给格加步数、脆格碎掉后长回来、结算面板和本机成绩
#   auto [campaign|endless] [1|2] [最多打到第几关] [前缀]
#                             机器人真机玩一局。1 = 照着摆好的路线走（必须一步不错、关关都过）；2 = 贪心打法（随手玩的玩家的下限）
#   opening [A|B|D] [秒数] [每秒几张]   录一段开场动画（真正的开机画面），帧取回到 builds/opening/<方案>/
#   lobby [秒数=20] [每秒几张=20]   录一段大厅（标题页）的背景：那条夜里的河、河上的灯、指针划过和挪焦点时荡开的涟漪，
#                             帧取回到 builds/lobby/rec/，再拼视频：tools/playtest/assemble_lobby.sh
#   stage <布局 1|2|3> [秒数=18] [每秒几张=20]   录一段游戏里的背景：进游戏、在棋盘上跳几下（河灯在漂、落地荡开的那圈），
#                             帧取回到 builds/stage/<布局>/，再拼视频：tools/playtest/assemble_stage.sh <布局>
#   versus <1..5> [秒数=24] [每秒几张=20]   录一局对战（1 抢灯、2 追影、3 夺岸、4 轮战、5 对弈），主角交给机器人打，
#                             帧取回到 builds/versus/<编号>/，再拼视频：tools/playtest/assemble_versus.sh <编号>
#   transition <样式> [秒数=12] [每秒几张=30] [存成什么=jpg|png]   录一段换关的过渡（第 1 关踩上水车到进第 2 关，机器人打的），几种样式录的是同一段，
#                             要给人看的片子用 png（无损；暗色的画面存 JPG 会偏色），帧会稀一点，拼的时侯按实际的帧数算帧率
#                             帧取回到 builds/transition/<样式>/，再拼视频：tools/playtest/assemble_transition.sh <样式>；几种并排：… compare <样式> …
#   drive <步骤文件> [前缀]  按步骤文件操作游戏并截图（步骤怎么写见 drive_v100.sh 的开头）
#   export                  在 V100 上把工程导出成 Linux 可执行文件（给掌机用），放在 V100 的 shouwang-agents/<标签>/shouwang.x86_64
#   fetch                   把导出的可执行文件取回到本地 builds/linux/shouwang.x86_64
#   smoke <步骤文件> [前缀]  试跑导出来的可执行文件（先 export）：启动 → 按步骤操作 → 截图取回，同 drive
#   pull <前缀>             把 V100 上这个标签的截图取回来（文件名以 <前缀>_ 开头的）
#   stop                    只停掉这个标签在 V100 上的游戏
#   clean                   停掉并删掉 V100 上这个标签的目录（做完以后一定要执行，base 不用删）
#   all                     一轮完整回归：import → boards → flow campaign → flow endless → aspect → mechanics → auto campaign 1，哪一步没过就停在那一步
# 截图取回到 $SW_OUT（默认 builds/shots/<标签>/）。开了游戏的命令哪一步没过，退出码就不是 0。
# 换一台服务器跑（比如和别的任务错开）：SW_HOST 设成 ~/.ssh/config 里的别名就行，别的不用动。默认是 WZU_V100。
#   SW_HOST=V100_222_TS tools/playtest/agent.sh a7 all
#   （外部那台把 Xvfb 和 Vulkan 的加载库解在 ~/apps/xvfb/root/ 里：有这个目录就自动用，不用再指定）
# 那台服务器上要有 Godot 4.7.2（默认在 ~/apps/godot/ 下，不在就用 SW_GODOT 指定）、Xvfb（默认从 PATH 里找，
#   不在 PATH 里就用 SW_XVFB 指定）。各标签的根目录默认在家目录下的 shouwang-agents/，想放别处用 SW_ROOTS。
#   Godot 缺动态库（比如 Vulkan 的加载库装在自己的目录里）就用 SW_LD_LIBRARY_PATH 加搜索路径。
# 第一次在一台新服务器上用：先跑 SW_FULL=1 <标签> setup，把工程连同音频整份传过去当底版
# 临时指定难度：SW_RULESET=hard tools/playtest/agent.sh a7 auto campaign 2（四档的 id 见 resources/rulesets/）
# 让机器人按真人每走一步想多久来走（默认 0.4 秒；夜巡是真的计时，机器人想都不想就量不出蜡烛的影响）：SW_AUTO_PACE=5 tools/playtest/agent.sh a7 auto campaign 2
# 机器人每一步都打进日志（查它为什么跳不到的时侯用）：SW_AUTO_TRACE=1 tools/playtest/agent.sh a7 auto campaign 1
# 游戏里背景的三种布局（1 长河、2 远岸、3 月下；平时是月下）：SW_STAGE=2 tools/playtest/agent.sh a7 drive tools/playtest/steps_stage.txt 远岸
## 让机器人换关后只等 0.2 秒（平时 1.5 秒），试它在灯还没摆完的时侯会不会乱动：SW_AUTO_EAGER=1 tools/playtest/agent.sh a7 auto campaign 1
## 换关的过渡换成某一种（默认 tiles 是原来的石砖墙；别的见 scripts/uis/transitions/）：SW_TRANSITION=ripple tools/playtest/agent.sh a7 drive tools/playtest/steps_transition.txt 过渡
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
HOST="${SW_HOST:-WZU_V100}"           # ssh 配置里的别名。换一台服务器就设 SW_HOST
# 各标签的根目录：默认在那台服务器自己的家目录下（问它一声 $HOME，多一次连接而已）。SW_ROOTS 可以改
RHOME="${SW_REMOTE_HOME:-$($SSH "$HOST" 'echo $HOME' 2>/dev/null | tail -n 1)}"      # 那台服务器的家目录（问它一声，只问这一次）
ROOTS="${SW_ROOTS:-$RHOME/shouwang-agents}"
# 家目录那一问要是返回了空的（连接时好时坏的时侯会有），根目录就成了 /shouwang-agents：后面的同步、导入都会对着一个不存在的目录空跑，还不报错。
# 所以家目录本身必须是非空的
[ -n "${ROOTS%/shouwang-agents}" ] || { echo "连不上 ${HOST}，或者读不到它的家目录（可以用 SW_ROOTS、SW_REMOTE_HOME 直接指定）"; exit 1; }
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
export SW_GODOT="${SW_GODOT:-}"              # 服务器上 Godot 可执行文件的位置（空 = 那台服务器家目录下的 apps/godot/）
export SW_XVFB="${SW_XVFB:-}"                # 服务器上 Xvfb 的位置（空 = PATH 里的 Xvfb）
export SW_LD_LIBRARY_PATH="${SW_LD_LIBRARY_PATH:-}"   # 服务器上 Godot 要多找的动态库目录（空 = 不加）
export SW_AUDIO="${SW_AUDIO:-}"              # 音频驱动（Dummy / ALSA）。不写：没有声卡也不声音频服务在跑的机器上自动用 Dummy
# 那台服务器上自己装了 Xvfb（没装系统包、解在家目录的 apps/xvfb/root/ 里，V100_222 就是这样）：默认就用它，
# 顺带把它那一目录里可能有的 Vulkan 加载库也带上。SW_XVFB、SW_LD_LIBRARY_PATH 给了就以给的为准
if [ -z "${SW_XVFB:-}" ] && [ -n "$RHOME" ] && $SSH "$HOST" "test -d $RHOME/apps/xvfb/root" 2>/dev/null; then
	SW_XVFB="$RHOME/apps/xvfb/root/usr/bin/Xvfb"
	SW_LD_LIBRARY_PATH="${SW_LD_LIBRARY_PATH:-$RHOME/apps/xvfb/root/usr/lib/x86_64-linux-gnu}"
fi
export SW_RULESET="${SW_RULESET:-}"          # 临时指定难度（简单 easy / 中等 normal / 困难 hard / 非常困难 extreme），不写存档
export SW_AUTO_PACE="${SW_AUTO_PACE:-}"      # 自动试玩的机器人每走一步等多久（秒），平时 0.4
export SW_STAGE="${SW_STAGE:-}"              # 游戏里背景的布局：1 长河、2 远岸、3 月下；不写是平时用的「月下」，给 0 是原来那块网纹的水
export SW_TRANSITION="${SW_TRANSITION:-}"    # 换关过渡的样式：tiles 原来的石砖墙（不写就是它）；别的见 scripts/uis/transitions/。不写存档
pull() {
	mkdir -p "$OUT"
	rsync -a -e "$SSH" --include "${1}_*" --exclude '*' "$HOST:$REMOTE/shots/" "$OUT/" && echo "截图已取回到 ${OUT}（文件名以 ${1}_ 开头）"
}
ENVS="SW_RUN=$SW_RUN SW_LOG=$SW_LOG SW_DEBUG_PORT=$SW_DEBUG_PORT SW_SNAP=$SW_SNAP SW_THREADS=$SW_THREADS SW_DISPLAYS='$SW_DISPLAYS' SW_RES=$SW_RES SW_RENDERER=$SW_RENDERER SW_RULESET=$SW_RULESET SW_AUTO_TRACE=$SW_AUTO_TRACE SW_AUTO_EAGER=$SW_AUTO_EAGER SW_OPENING=$SW_OPENING SW_BOOT_WAIT=$SW_BOOT_WAIT SW_OPENING_TRACE=$SW_OPENING_TRACE SW_STAGE=$SW_STAGE SW_GODOT=$SW_GODOT SW_XVFB=$SW_XVFB SW_LD_LIBRARY_PATH=$SW_LD_LIBRARY_PATH SW_AUDIO=$SW_AUDIO SW_AUTO_PACE=$SW_AUTO_PACE SW_TRANSITION=$SW_TRANSITION"
BIN="$REMOTE/shouwang.x86_64"
EXCLUDE="--exclude .git --exclude .godot --exclude builds --exclude .DS_Store --exclude *.tmp --exclude __pycache__ --exclude tools/playtest"
# 原作的两首曲子和音效很大，建环境的时侯从 base 复制过来，平时同步不传；开场动画的声音是我们自己的、很小，照常同步
[ "$TAG" != base ] && EXCLUDE="$EXCLUDE --include assets/audio/opening --include 'assets/audio/opening/***' --exclude 'assets/audio/*'"
case "$CMD" in
	setup)
		$SSH "$HOST" "mkdir -p $REMOTE/project $REMOTE/bin $REMOTE/shots; if [ '$TAG' != base ] && [ ! -e $REMOTE/project/project.godot ] && [ -d $ROOTS/base/project ]; then cp -a $ROOTS/base/project/. $REMOTE/project/; fi" \
			&& scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT"/tools/playtest/{rc,launch_v100,stop_v100,drive_v100,snap_levels_v100,flowtest_v100,aspect_v100,mechanics_v100,autoplay_v100,record_opening_v100,record_lobby_v100,record_stage_v100,record_versus_v100,record_transition_v100,check_scripts}.sh "$HOST:$REMOTE/bin/" \
			&& echo "V100 上的环境已建好：${REMOTE}（端口 ${SW_DEBUG_PORT}，渲染线程 ${SW_THREADS}）" ;;
	sync)
		[ "${SW_FULL:-}" = 1 ] && EXCLUDE="--exclude .git --exclude .godot --exclude builds --exclude .DS_Store --exclude *.tmp --exclude __pycache__ --exclude tools/playtest"   # 整份传（连音频），当底版
		rsync -a --delete $EXCLUDE -e "$SSH" "$ROOT/" "$HOST:$REMOTE/project/" \
			&& echo "已同步到 ${REMOTE}/project" ;;
	# 只检查脚本能不能解析（比导入快，写代码的时侯先过这一道）。导入日志里只报"依赖它的脚本编译不过"，
	# 出错的那一行不一定打出来，所以这里把脚本逐个解析一遍
	check)
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT/tools/playtest/check_scripts.sh" "$HOST:$REMOTE/bin/" || exit 1
		$SSH "$HOST" "bash $REMOTE/bin/check_scripts.sh $REMOTE" | cut -c1-230
		exit ${PIPESTATUS[0]} ;;
	# 同步过去再导入，Godot 会改写一部分 .import 文件（导入缓存的路径），也会给新脚本生成 .uid 文件：都取回来，仓库里存的才是对的
	import)
		$SSH "$HOST" bash -s "$REMOTE" <<'REMOTE_SH'
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
		rsync -a -e "$SSH" --exclude '.godot/' --include 'assets/audio/opening/' --include 'assets/audio/opening/*.import' --exclude 'assets/audio/*' --include '*/' --include '*.import' --include '*.uid' --exclude '*' "$HOST:$REMOTE/project/" "$ROOT/"
		exit $code ;;
	boards)
		$SSH "$HOST" bash -s "$REMOTE" <<'REMOTE_SH'
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
	rates)
		# 难度四档的过关率：每一档打 RUNS 局（巡夜 + 游戏里摆好的 12 局 + 长夜）。THINK 是机器人每走一步想几秒（只对夜巡有用）。
		# EXTRA 是临时改数的参数，例如 'set=moves_cap_add=0 set=moves_bonus=2'（可以写好几回）。
		# 给 godot 的参数在这儿就拼成一串，放在远端的环境变量里带过去：ssh 不保留引号，当普通参数传的话带空格的会被拆开
		RUNS="${3:-200}"; THINK="${4:-1.0}"; TIERS="${5:-}"; EXTRA="${6:-}"
		USER_ARGS="runs=$RUNS think=$THINK"
		[ -n "$TIERS" ] && USER_ARGS="$USER_ARGS tiers=$TIERS"
		[ -n "$EXTRA" ] && USER_ARGS="$USER_ARGS $EXTRA"
		$SSH "$HOST" "SW_RATES_ARGS='$USER_ARGS' bash -s '$REMOTE'" <<'REMOTE_SH' | cut -c1-260
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
R="$1"; cd "$R/project" || exit 1
$G --headless --path . --script res://tools/tier_rates.gd -- $SW_RATES_ARGS ascii=1 > "$1/rates.log" 2>&1
code=$?
errs=$(grep -a -c 'SCRIPT ERROR' "$1/rates.log")
# 字符画（游戏里摆好的那 12 局长什么样）每一行都以"    | "开头，看总表的时侯滤掉；要看就到服务器上读 rates.log
grep -a -v '^    | ' "$1/rates.log" | head -n 190
[ "$errs" = 0 ] || { grep -a -A6 'SCRIPT ERROR' "$1/rates.log" | head -n 24; }
if [ "$code" = 0 ] && [ "$errs" = 0 ] && grep -a -q 'RESULT failures=0' "$1/rates.log"; then
	echo "RESULT 难度过关率：通过（完整日志在 $1/rates.log，字符画也在里面）"
else
	echo "RESULT 难度过关率：没过（退出码 $code，脚本报错 $errs 条，完整日志在 $1/rates.log）"
	exit 1
fi
REMOTE_SH
		exit ${PIPESTATUS[0]} ;;
	drive)
		STEPS="$3"; PREFIX="${4:-run}"
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$STEPS" "$HOST:$REMOTE/steps.txt" || exit 1
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/drive_v100.sh $REMOTE/project $REMOTE/steps.txt $PREFIX" | cut -c1-600
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	flow)
		MODE="${3:-campaign}"; PREFIX="${4:-flow_$MODE}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/flowtest_v100.sh $REMOTE/project $MODE $PREFIX" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	aspect)
		RES="${3:-1152x720}"; PREFIX="${4:-aspect}"
		$SSH "$HOST" "SW_RES=$RES $ENVS bash $REMOTE/bin/aspect_v100.sh $REMOTE/project $PREFIX $RES" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	auto)
		MODE="${3:-campaign}"; BOT="${4:-1}"; MAXL="${5:-999}"; PREFIX="${6:-auto_${MODE}_$BOT}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/autoplay_v100.sh $REMOTE/project $MODE $BOT $MAXL $PREFIX" | cut -c1-400
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	opening)
		WHICH="${3:-A}"; SECS="${4:-4.8}"; FPS="${5:-20}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/record_opening_v100.sh $REMOTE/project $WHICH $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/opening/$WHICH" && rm -f "$ROOT/builds/opening/$WHICH/"*.jpg
		rsync -a -e "$SSH" "$HOST:/tmp/sw_opening_$(basename "${SW_RUN:-x}")_$WHICH/" "$ROOT/builds/opening/$WHICH/" && echo "帧已取回到 builds/opening/$WHICH/（$(ls "$ROOT/builds/opening/$WHICH" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_opening.sh $WHICH"
		exit $code ;;
	lobby)
		SECS="${3:-20}"; FPS="${4:-20}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/record_lobby_v100.sh $REMOTE/project $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/lobby/rec" && rm -f "$ROOT/builds/lobby/rec/"*.jpg
		rsync -a -e "$SSH" "$HOST:/tmp/sw_lobby_$(basename "${SW_RUN:-x}")/" "$ROOT/builds/lobby/rec/" && echo "帧已取回到 builds/lobby/rec/（$(ls "$ROOT/builds/lobby/rec" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_lobby.sh $FPS"
		exit $code ;;
	stage)
		N="${3:-1}"; SECS="${4:-18}"; FPS="${5:-20}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/record_stage_v100.sh $REMOTE/project $N $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/stage/$N" && rm -f "$ROOT/builds/stage/$N/"*.jpg
		rsync -a -e "$SSH" "$HOST:/tmp/sw_stage_$(basename "${SW_RUN:-x}")_$N/" "$ROOT/builds/stage/$N/" && echo "帧已取回到 builds/stage/$N/（$(ls "$ROOT/builds/stage/$N" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_stage.sh $N $FPS"
		exit $code ;;
	versus)
		N="${3:-1}"; SECS="${4:-24}"; FPS="${5:-20}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/record_versus_v100.sh $REMOTE/project $N $SECS $FPS" | cut -c1-300
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/versus/$N" && rm -f "$ROOT/builds/versus/$N/"*.jpg
		rsync -a -e "$SSH" "$HOST:/tmp/sw_versus_$(basename "${SW_RUN:-x}")_$N/" "$ROOT/builds/versus/$N/" && echo "帧已取回到 builds/versus/$N/（$(ls "$ROOT/builds/versus/$N" | wc -l | tr -d ' ') 张）；拼视频：tools/playtest/assemble_versus.sh $N"
		exit $code ;;
# 录一段换关的过渡。样式放进 SW_TRANSITION 带过去（ENVS 里那一个是空的，会把先给的冲掉，所以先 export 再用）
	transition)
		STYLE="${3:-tiles}"; SECS="${4:-12}"; FPS="${5:-30}"; FMT="${6:-jpg}"
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT/tools/playtest/record_transition_v100.sh" "$HOST:$REMOTE/bin/" || exit 1
		export SW_TRANSITION="$STYLE"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/record_transition_v100.sh $REMOTE/project $STYLE $SECS $FPS $FMT" | LC_ALL=C cut -c1-400
		code=${PIPESTATUS[0]}
		mkdir -p "$ROOT/builds/transition/$STYLE" && rm -f "$ROOT/builds/transition/$STYLE/"*
		# 取帧：网络慢的时侯会断。断了就接着传，最多试五回；取回来数一数，不够就不算成功（帧还在服务器上，再跑一遍这个命令就接着传）
		for try in 1 2 3 4 5; do
			rsync -a --partial --timeout=60 -e "$SSH" "$HOST:/tmp/sw_transition_$(basename "$REMOTE")_$STYLE/" "$ROOT/builds/transition/$STYLE/" && break
			sleep 3
		done
		remote_n=$($SSH "$HOST" "ls /tmp/sw_transition_$(basename "$REMOTE")_$STYLE/ 2>/dev/null | grep -c '^transition_'" 2>/dev/null | tail -n 1)
		local_n=$(ls "$ROOT/builds/transition/$STYLE/" | grep -c '^transition_')
		[ "${local_n:-0}" -ge "${remote_n:-1}" ] || { echo "帧没取全：服务器上有 ${remote_n} 个，本机只有 ${local_n} 个。再跑一遍这个命令就接着传"; [ "$code" = 0 ] && code=6; }
		echo "帧已取回到 builds/transition/$STYLE/（$(ls "$ROOT/builds/transition/$STYLE" | grep 'transition_' | sed 's/.*\.//' | sort | uniq -c | awk '{printf "%s 格式 %s 帧 ", $NF, $1}')）；拼视频：tools/playtest/assemble_transition.sh $STYLE"
		exit $code ;;
	mechanics)
		PREFIX="${3:-mechanics}"
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/mechanics_v100.sh $REMOTE/project $PREFIX" | cut -c1-900
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	export)
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT/tools/playtest/export_linux_v100.sh" "$HOST:$REMOTE/bin/" || exit 1
		$SSH "$HOST" "bash $REMOTE/bin/export_linux_v100.sh $REMOTE/project $BIN" | cut -c1-400 ;;
	fetch)
		mkdir -p "$ROOT/builds/linux"
		rsync -a --partial -e "$SSH" "$HOST:$BIN" "$ROOT/builds/linux/shouwang.x86_64" && ls -la "$ROOT/builds/linux/shouwang.x86_64" | awk '{print "已取回到 builds/linux/shouwang.x86_64，" $5 " 字节"}' ;;
	smoke)
		STEPS="$3"; PREFIX="${4:-smoke}"
		$SSH "$HOST" "test -x $BIN" || { echo "V100 上还没有导出的可执行文件，先跑 export"; exit 1; }
		scp -q -o ConnectTimeout=30 -o BatchMode=yes "$STEPS" "$HOST:$REMOTE/steps.txt" || exit 1
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/drive_v100.sh $BIN $REMOTE/steps.txt $PREFIX" | cut -c1-600
		code=${PIPESTATUS[0]}
		pull "$PREFIX"
		exit $code ;;
	pull)
		[ -n "${3:-}" ] || { echo "用法: agent.sh $TAG pull <截图前缀>"; exit 1; }
		pull "$3" ;;
	stop)
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/stop_v100.sh $REMOTE/project" ;;
	clean)
		$SSH "$HOST" "$ENVS bash $REMOTE/bin/stop_v100.sh $REMOTE/project; rm -rf $REMOTE /tmp/sw_snap_$TAG.jpg /tmp/sw_snap_$TAG.png /tmp/sw_snap_${TAG}_P*.png; echo \"已删除 V100 上的 $REMOTE\"" ;;
	all)
		for step in import boards "flow campaign" "flow endless" aspect mechanics "auto campaign 1"; do
			echo "========== $step =========="
			"$0" "$TAG" $step || { echo "RESULT 完整回归：没过，停在「$step」"; exit 1; }
		done
		# 四档的规矩在游戏里的样子（旗子、蜡烛、放灯、灯灭、重来按钮），每一档各跑一遍
		for t in easy normal hard extreme; do
			echo "========== 规矩自检 $t =========="
			SW_RULESET=$t "$0" "$TAG" drive tools/playtest/steps_rules.txt "rules_$t" || { echo "RESULT 完整回归：没过，停在「规矩自检 $t」"; exit 1; }
		done
		# 玩到一半换难度：暂停菜单里的加减器、结算面板上的加减器
		echo "========== 换难度 =========="
		"$0" "$TAG" drive tools/playtest/steps_difficulty.txt difficulty || { echo "RESULT 完整回归：没过，停在「换难度」"; exit 1; }
		# 临时指定的难度、开场不写进共用的测试存档
		echo "========== 存档隔离 =========="
		SW_RULESET=hard SW_OPENING=off "$0" "$TAG" drive tools/playtest/steps_save.txt save_isolation || { echo "RESULT 完整回归：没过，停在「存档隔离」"; exit 1; }
		# 标题页那条河上的灯画在界面底下（难度页的字被河灯盖住过）：河上凑满灯，开着难度页、设置页各量一遍
		echo "========== 河灯的层级 =========="
		SW_OPENING=off SW_BOOT_WAIT=2 "$0" "$TAG" drive tools/playtest/steps_river_layers.txt riverlayers || { echo "RESULT 完整回归：没过，停在「河灯的层级」"; exit 1; }
		# 对战（scripts/versus/）：标题页的入口和选择面板；五种玩法各打一局（主角交给机器人），顺便查对战的局没套标题页上选的难度
		#（所以那一步故意带着 SW_RULESET=extreme）；"重来"刷新一局；要在棋盘上选目标的技能；关卡左上角的"返回"先叫出暂停菜单；
		# 技能只在游戏里放（菜单开着、光标停在按钮上都不放）
		for v in versus:对战入口 versus_play:五种对战 restart:对战重来 aim:技能选目标 aim2:钓叟收灯 hud_back:关卡里的返回 skill:技能只在游戏里放; do
			f="${v%%:*}"; name="${v#*:}"
			echo "========== ${name} =========="
			extra=""
			[ "$f" = versus_play ] && extra="SW_RULESET=extreme"
			env SW_OPENING=off SW_BOOT_WAIT=2 ${extra:+"$extra"} "$0" "$TAG" drive "tools/playtest/steps_${f}.txt" "$f" || { echo "RESULT 完整回归：没过，停在「${name}」"; exit 1; }
		done
# 换关的过渡：scripts/uis/transitions/ 里有的每一种，再加上原来的那一种（tiles），各量两趟——盖住、掀开的时侯卡没卡、长短对不对
		echo "========== 换关的过渡 =========="
		for f in "$ROOT"/scripts/uis/transitions/transition_*.gd; do
			[ -e "$f" ] || continue
			name="$(basename "$f" .gd)"; name="${name#transition_}"
			echo "---------- 过渡 $name ----------"
			SW_TRANSITION="$name" SW_OPENING=off SW_BOOT_WAIT=2 "$0" "$TAG" drive tools/playtest/steps_transition.txt "trans_$name" || { echo "RESULT 完整回归：没过，停在「换关的过渡 $name」"; exit 1; }
		done
		echo "---------- 过渡 tiles（原来的）----------"
		SW_TRANSITION= SW_OPENING=off SW_BOOT_WAIT=2 "$0" "$TAG" drive tools/playtest/steps_transition.txt trans_tiles || { echo "RESULT 完整回归：没过，停在「换关的过渡 tiles」"; exit 1; }
		echo "RESULT 完整回归：通过" ;;
	*) echo "不认识的命令: ${CMD}"; exit 1 ;;
esac

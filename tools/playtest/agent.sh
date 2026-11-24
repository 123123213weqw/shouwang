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
#   drive <步骤文件> [前缀]  按步骤文件操作游戏并截图（步骤怎么写见 drive_v100.sh 的开头）
#   export                  在 V100 上把工程导出成 Linux 可执行文件（给掌机用），放在 V100 的 shouwang-agents/<标签>/shouwang.x86_64
#   fetch                   把导出的可执行文件取回到本地 builds/linux/shouwang.x86_64
#   smoke <步骤文件> [前缀]  试跑导出来的可执行文件（先 export）：启动 → 按步骤操作 → 截图取回，同 drive
#   pull <前缀>             把 V100 上这个标签的截图取回来（文件名以 <前缀>_ 开头的）
#   stop                    只停掉这个标签在 V100 上的游戏
#   clean                   停掉并删掉 V100 上这个标签的目录（做完以后一定要执行，base 不用删）
#   all                     一轮完整回归：import → boards → flow campaign → flow endless → aspect → mechanics，哪一步没过就停在那一步
# 截图取回到 $SW_OUT（默认 builds/shots/<标签>/）。开了游戏的命令哪一步没过，退出码就不是 0。
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
pull() {
	mkdir -p "$OUT"
	rsync -a -e "$SSH" --include "${1}_*" --exclude '*' "WZU_V100:$REMOTE/shots/" "$OUT/" && echo "截图已取回到 ${OUT}（文件名以 ${1}_ 开头）"
}
ENVS="SW_RUN=$SW_RUN SW_LOG=$SW_LOG SW_DEBUG_PORT=$SW_DEBUG_PORT SW_SNAP=$SW_SNAP SW_THREADS=$SW_THREADS SW_DISPLAYS='$SW_DISPLAYS' SW_RES=$SW_RES SW_RENDERER=$SW_RENDERER"
BIN="$REMOTE/shouwang.x86_64"
EXCLUDE="--exclude .git --exclude .godot --exclude builds --exclude .DS_Store --exclude *.tmp --exclude __pycache__ --exclude tools/playtest"
[ "$TAG" != base ] && EXCLUDE="$EXCLUDE --exclude assets/audio"
case "$CMD" in
	setup)
		$SSH WZU_V100 "mkdir -p $REMOTE/project $REMOTE/bin $REMOTE/shots; if [ '$TAG' != base ] && [ ! -e $REMOTE/project/project.godot ] && [ -d $ROOTS/base/project ]; then cp -a $ROOTS/base/project/. $REMOTE/project/; fi" \
			&& scp -q -o ConnectTimeout=30 -o BatchMode=yes "$ROOT"/tools/playtest/{rc,launch_v100,stop_v100,drive_v100,snap_levels_v100,flowtest_v100,aspect_v100,mechanics_v100}.sh "WZU_V100:$REMOTE/bin/" \
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
[ "$e" = 0 ] && [ "$o" = 0 ]
REMOTE_SH
		code=$?
		rsync -a -e "$SSH" --exclude '.godot/' --exclude 'assets/audio/' --include '*/' --include '*.import' --include '*.uid' --exclude '*' "WZU_V100:$REMOTE/project/" "$ROOT/"
		exit $code ;;
	boards)
		$SSH WZU_V100 bash -s "$REMOTE" <<'REMOTE_SH'
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
cd "$1/project" || exit 1
$G --headless --path . --script res://tools/test_boards.gd > "$1/boards.log" 2>&1
code=$?
grep -a 'RESULT\|^FAIL' "$1/boards.log" | head -n 30
grep -a '共检查' "$1/boards.log"
[ "$code" = 0 ] && echo "RESULT 棋盘自动测试：通过" || echo "RESULT 棋盘自动测试：没过（退出码 $code，完整日志在 $1/boards.log）"
[ "$code" = 0 ]
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
		for step in import boards "flow campaign" "flow endless" aspect mechanics; do
			echo "========== $step =========="
			"$0" "$TAG" $step || { echo "RESULT 完整回归：没过，停在「$step」"; exit 1; }
		done
		echo "RESULT 完整回归：通过" ;;
	*) echo "不认识的命令: ${CMD}"; exit 1 ;;
esac

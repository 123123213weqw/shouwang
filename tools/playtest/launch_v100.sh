#!/bin/bash
# 在 V100（无显示器）上启动一份工程做截图：自己起一个 Xvfb + 软件 Vulkan。
# 软件渲染很吃 CPU：每个实例最多用 SW_THREADS 个渲染线程（lavapipe 的 LP_NUM_THREADS）。
# 不绑核、不降优先级：这台机器上有优先级很高（-10）的多线程任务，绑在固定的核上又降到最低优先级的话，
# 一旦那个核上有高优先级线程，游戏只能分到不到 1% 的 CPU；用普通优先级则争抢时仍然让着它们，只吃空闲的算力。
# 用法: launch_v100.sh <工程目录或者导出来的可执行文件>
# 几个互不相干的测试实例可以同时跑，靠环境变量各用各的（不设就是最早那一套的默认值）：
#   SW_RUN         这个实例的目录（进程号文件）        默认 家目录/shouwang-run
#   SW_GODOT / SW_XVFB / SW_LD_LIBRARY_PATH   Godot 和 Xvfb 在哪、要多找哪个动态库目录（见 agent.sh 的开头）
#   SW_AUDIO       用哪个音频驱动（Dummy / ALSA）。不写：没有声卡也不声音频服务在跑的机器上自动用 Dummy
#   SW_LOG         游戏的日志                          默认 /tmp/shouwang_run.log
#   SW_RES         窗口分辨率                          默认 1280x720
#   SW_THREADS     渲染线程数                          默认 5
#   SW_DISPLAYS    虚拟显示可以用的编号（空格隔开）     默认 98 到 105
#   SW_RENDERER   用哪种方式渲染（见下面 RENDER 那一段）   默认 gl
#   SW_GPU        SW_RENDERER=nvidia 时用第几块显卡。这台机器上别设（编号 1 是软件渲染，编号 2 起不来）
#   SW_DEBUG_PORT / SW_SNAP   游戏里调试遥控的端口、截图的临时文件（原样传给游戏）
# 只停这个实例自己上一次启动的游戏，不动别人的
G="${SW_GODOT:-$HOME/apps/godot/Godot_v4.7.2-stable_linux.x86_64}"   # 位置可以用 SW_GODOT 改
[ -x "$G" ] || { echo "找不到 Godot：$G（用 SW_GODOT 指定，或者放到 ~/apps/godot/ 下）"; exit 1; }
XVFB="${SW_XVFB:-Xvfb}"                    # 虚拟显示的服务程序。装在自己目录里的时侯用 SW_XVFB 指定
[ -x "$XVFB" ] || command -v "$XVFB" >/dev/null 2>&1 || { echo "找不到 Xvfb：$XVFB（用 SW_XVFB 指定）"; exit 1; }
# 音频：既没有声卡、也没有 PulseAudio / PipeWire 在跑的机器上，ALSA 打开输出设备会在日志里报一条错（每次都判没过）。
# 那就直接用"哑"驱动：声音照常"放"（流在走、时间在过，查声音的步骤照常能查），只是不出声。SW_AUDIO 可以硬指定
if [ -z "${SW_AUDIO:-}" ]; then
	if ! ls /dev/snd/pcm* >/dev/null 2>&1 && ! pgrep -u "$(id -un)" -f "pipewire|pulseaudio" >/dev/null 2>&1; then SW_AUDIO=Dummy; fi
fi
AUDIO=""
[ -n "${SW_AUDIO:-}" ] && AUDIO="--audio-driver $SW_AUDIO"
# Godot 要多找的动态库（比如装在自己目录里的 Vulkan 加载库）
[ -n "${SW_LD_LIBRARY_PATH:-}" ] && export LD_LIBRARY_PATH="$SW_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PROJECT="${1%/}"
RUN="${SW_RUN:-$HOME/shouwang-run}"
LOG="${SW_LOG:-/tmp/shouwang_run.log}"
RES="${SW_RES:-1280x720}"
N=$(nproc)
THREADS="${SW_THREADS:-5}"
mkdir -p "$RUN"
[ -f "$RUN/game.pid" ] && { kill "$(cat "$RUN/game.pid")" 2>/dev/null; rm -f "$RUN/game.pid"; }
[ -f "$RUN/xvfb.pid" ] && { kill "$(cat "$RUN/xvfb.pid")" 2>/dev/null; rm -f "$RUN/xvfb.pid"; }
[ -f "$RUN/display" ] && { rm -rf "/tmp/sw-disp-$(cat "$RUN/display").lock"; rm -f "$RUN/display"; }
sleep 1
disp=""
for n in ${SW_DISPLAYS:-98 99 100 101 102 103 104 105}; do
	# 用一个目录当锁：几个实例同时启动时不会挑到同一个编号
	mkdir "/tmp/sw-disp-$n.lock" 2>/dev/null || continue
	"$XVFB" ":$n" -screen 0 1280x720x24 </dev/null >/dev/null 2>&1 &
	echo $! > "$RUN/xvfb.pid"
	# 这台机器的 /tmp 里留着很多失效的 X 锁文件和 socket（别的任务被杀后留下的），不能拿它们判断占没占用：
	# 编号真被占着的话 Xvfb 自己会启动失败，失效的锁它会接管。所以直接试，再看它活没活
	for i in $(seq 1 30); do [ -S "/tmp/.X11-unix/X$n" ] && break; sleep 0.5; done
	sleep 1
	if ! kill -0 "$(cat "$RUN/xvfb.pid")" 2>/dev/null; then
		echo "Xvfb 在 :$n 上没起来（可能被占着），换一个编号"; rm -rf "/tmp/sw-disp-$n.lock"; rm -f "$RUN/xvfb.pid"; continue
	fi
	disp=$n; break
done
[ -z "$disp" ] && { echo "没有能用的虚拟显示编号"; exit 1; }
echo "$disp" > "$RUN/display"
cd "$HOME"
export DISPLAY=":$disp" SDL_VIDEODRIVER=x11
# 渲染方式有三种，试过的启动时间（到调试端口起来为止）和帧数：
#   gl      OpenGL 3 + llvmpipe，纯软件、不碰显卡：9 秒、40 帧。平时迭代用这个
#   nvidia  游戏真正用的 Forward+，跑在服务器自带的 NVIDIA 显卡上：6 秒、60 帧。显卡上有别人的大模型服务
#           （两张卡各只剩 5 到 7 GB 显存），一个实例占三四百 MB，只在做最终验收时用，而且一次只开一两个实例
#   lvp     Forward+ 跑在软件 Vulkan（lavapipe）上：105 秒（启动时单线程编译着色器管线），留作对照
unset VK_ICD_FILENAMES VK_DRIVER_FILES
RENDER="--rendering-driver opengl3 --rendering-method gl_compatibility"
case "${SW_RENDERER:-gl}" in
	gl) ;;
	nvidia) RENDER="--rendering-driver vulkan"; [ -n "${SW_GPU:-}" ] && RENDER="$RENDER --gpu-index $SW_GPU" ;;
	lvp)
		export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
		export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
		RENDER="--rendering-driver vulkan" ;;
	*) echo "不认识的 SW_RENDERER: $SW_RENDERER（只能是 gl、nvidia、lvp）"; rm -rf "/tmp/sw-disp-$disp.lock" "$RUN/display"; kill "$(cat "$RUN/xvfb.pid")"; exit 1 ;;
esac
export LP_NUM_THREADS="$THREADS"
# 命令行末尾带一个标记（"--" 后面的参数 Godot 不处理，原样留给工程）：靠它来找这一个实例的进程，不会误伤别人的
MARK="shouwang-test-$PORT-$disp"
if [ -d "$PROJECT" ]; then
	setsid nohup "$G" --path "$PROJECT" $RENDER $AUDIO --resolution "$RES" -- "$MARK" </dev/null >"$LOG" 2>&1 &
else
	setsid nohup "$PROJECT" $RENDER $AUDIO --resolution "$RES" -- "$MARK" </dev/null >"$LOG" 2>&1 &
fi
# 记下游戏的进程号，停的时候只停它
for i in $(seq 1 20); do
	pid=$(pgrep -u "$(id -un)" -f -- "$MARK" | head -n 1)
	[ -n "$pid" ] && break
	sleep 0.5
done
[ -n "$pid" ] && echo "$pid" > "$RUN/game.pid"
echo "已启动 $PROJECT：显示 :$disp，${SW_RENDERER:-gl}，渲染线程 $THREADS，调试端口 ${SW_DEBUG_PORT:-9878}${SW_AUDIO:+，音频 $SW_AUDIO}"

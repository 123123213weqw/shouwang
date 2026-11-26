#!/bin/bash
# 把 V100 上导出的游戏包装到掌机上（Legion Go，Ubuntu）。只换文件：不启动游戏。用法（在本机跑）：
# 游戏正在跑的时候默认不换：导出的包是一整个可执行文件，跑着的时候把它换掉，游戏下次要读资源（比如回主菜单）
# 就会读到半新半旧的东西，直接卡死（2026-11-26 就这么卡住过一次）。确认了要换再加 SW_FORCE=1：
#   SW_FORCE=1 tools/playtest/deploy_handheld.sh
#   tools/playtest/agent.sh a7 setup && tools/playtest/agent.sh a7 sync && tools/playtest/agent.sh a7 export
#   tools/playtest/deploy_handheld.sh [V100 上的包]    默认 /home/wzu/shouwang-agents/a7/shouwang.x86_64
# 掌机用 ~/.ssh/config 里的别名连（默认 RWKV_Tail：地址、用户名、钥匙都写在那里，这个脚本不写死；想换别名就设 SW_HANDHELD），
# 只能经 V100 跳过去。
# 传包走 V100 → 掌机 直连（两台机之间快），不绕本机这条慢链路：推的时候用本机起的一个一次性 ssh 代理带着掌机的钥匙，
# 用完就关，私钥不离开本机；掌机的主机指纹沿用本机已经信任的那一条（从本机的 known_hosts 里取出来，交给 V100 去核对）。
# 掌机上的布局（启动脚本、菜单项、图标都在仓库的 tools/handheld/ 里，每次部署都会重新装一遍）：
#   ~/apps/shouwang/{shouwang.x86_64, launch.sh, icon.png}   应用菜单项 ~/.local/share/applications/shouwang.desktop
# 换上去之前先核对校验和；旧的包留作 shouwang.x86_64.prev，想回退把它改回原名就行。
set -u
SRC="${1:-/home/wzu/shouwang-agents/a7/shouwang.x86_64}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ALIAS="${SW_HANDHELD:-RWKV_Tail}"
V100="ssh -o ConnectTimeout=30 -o BatchMode=yes WZU_V100"
HH="ssh -o BatchMode=yes -o ConnectTimeout=25 -J WZU_V100 $ALIAS"
NOISE='^Warning: Permanently added|^$'

# 在掌机上跑一段脚本（脚本从标准输入给，参数跟在后面），滤掉 ssh 的提示行；返回的是掌机上那段脚本的退出码。
# 连不上掌机时 ssh 的退出码也不是 0，调用的地方靠这个停下来
on_handheld() {
	$HH 'bash -s' "$@" 2>&1 | grep -v -E "$NOISE"
	return "${PIPESTATUS[0]}"
}

# 地址、用户名、钥匙都从 ssh 的配置里读
read -r HH_HOST HH_USER HH_KEY < <(ssh -G "$ALIAS" 2>/dev/null | awk '/^hostname /{h=$2} /^user /{u=$2} /^identityfile /{if (!k) k=$2} END{print h, u, k}')
[ -n "${HH_HOST:-}" ] && [ -n "${HH_USER:-}" ] && [ -n "${HH_KEY:-}" ] || { echo "ssh 配置里读不到「$ALIAS」这个别名的地址、用户名和钥匙"; exit 1; }
HH_KEY="${HH_KEY/#\~/$HOME}"

want=$($V100 "sha256sum $SRC" | cut -c1-64)
[ ${#want} -eq 64 ] || { echo "V100 上找不到包：${SRC}"; exit 1; }
size=$($V100 "stat -c %s $SRC")
echo "要部署的包：${SRC}（${size} 字节，${want:0:16}…）"
if [ "${SW_FORCE:-}" != 1 ] && $HH 'pgrep -x shouwang.x86_64 >/dev/null || pgrep -x newgame.x86_64 >/dev/null' >/dev/null 2>&1; then
	echo "掌机上的游戏正在运行，不换包（换掉会让它在下次读资源时卡死）。退出游戏以后再跑这个脚本，"
	echo "或者确认可以打断，用 SW_FORCE=1 tools/playtest/deploy_handheld.sh 强制换"
	exit 5
fi

echo "== 掌机现在的状态（只查看）=="
on_handheld <<'REMOTE' || { echo "掌机连不上（经 V100 跳板，别名 $ALIAS）"; exit 1; }
if pgrep -x newgame.x86_64 >/dev/null; then
	echo "改名前装的那一版正在运行：不动它。新版装好以后要先把它关掉，再从菜单启动（新版的启动脚本只认新的名字）"
elif pgrep -x shouwang.x86_64 >/dev/null; then
	echo "游戏正在运行：不动它，下次启动才是新的"
else
	echo "游戏没在运行"
fi
[ -f "$HOME/apps/shouwang/shouwang.x86_64" ] && echo "现在的包：$(sha256sum "$HOME/apps/shouwang/shouwang.x86_64" | cut -c1-16)…"
exit 0
REMOTE

echo "== 装启动脚本、图标和菜单项 =="
# 早期装在 ~/apps/newgame、菜单项叫 newgame.desktop：先把旧目录整个改名，再往新目录里装东西
#（顺序不能反：新目录已经在了的话，mv 会把旧目录塞进新目录里面）
on_handheld <<'REMOTE' || { echo "掌机上的旧安装没能改名，停在这里（没有动任何文件）"; exit 1; }
old="$HOME/apps/newgame"
if [ -d "$old" ]; then
	if [ -e "$HOME/apps/shouwang" ] || [ -L "$HOME/apps/shouwang" ]; then
		echo "~/apps/newgame 和 ~/apps/shouwang 同时在，不知道该留哪个：停在这里，请手动处理"
		exit 1
	fi
	mv "$old" "$HOME/apps/shouwang"
	for f in newgame.x86_64 newgame.x86_64.prev; do
		[ -f "$HOME/apps/shouwang/$f" ] && mv "$HOME/apps/shouwang/$f" "$HOME/apps/shouwang/${f/newgame/shouwang}"
	done
	rm -f "$HOME/.local/share/applications/newgame.desktop"
	echo "把以前装的 ~/apps/newgame 换成了 ~/apps/shouwang"
fi
mkdir -p "$HOME/apps/shouwang"
exit 0
REMOTE
# 这三个文件都很小，直接从本机经 V100 送过去；大的游戏包在后面走 V100 → 掌机 直连。
# COPYFILE_DISABLE 和 --no-xattrs：在 macOS 上打包时不带上扩展属性，免得掌机上多出几个 ._ 开头的文件
COPYFILE_DISABLE=1 tar --no-xattrs -C "$HERE/../handheld" -cf - launch.sh shouwang.desktop icon.png | $HH 'tar -C "$HOME/apps/shouwang" -xf -' 2>&1 | grep -v -E "$NOISE"
[ "${PIPESTATUS[1]}" = 0 ] || { echo "启动脚本没送上去，停在这里"; exit 1; }
on_handheld <<'REMOTE' || { echo "掌机上没装好，停在这里"; exit 1; }
set -e
apps="$HOME/.local/share/applications"
mkdir -p "$apps"
chmod +x "$HOME/apps/shouwang/launch.sh"
# 菜单项里的 @HOME@ 换成这台机器上的家目录（安装目录里留着的那份是模板）
sed "s|@HOME@|$HOME|g" "$HOME/apps/shouwang/shouwang.desktop" > "$apps/shouwang.desktop"
if command -v update-desktop-database >/dev/null; then update-desktop-database "$apps" 2>/dev/null || :; fi
echo "已装好：~/apps/shouwang/{launch.sh, icon.png}，菜单项 shouwang.desktop（名称：守望）"
REMOTE

echo "== 从 V100 推到掌机 =="
kh=/tmp/sw_handheld_known_hosts
ssh-keygen -F "$HH_HOST" -f "$HOME/.ssh/known_hosts" 2>/dev/null | grep -v "^#" > "$kh"
[ -s "$kh" ] || { echo "本机的 known_hosts 里没有掌机（$HH_HOST）的主机指纹（先用别的办法连一次掌机）"; exit 1; }
scp -q -o BatchMode=yes "$kh" WZU_V100:/tmp/sw_handheld_known_hosts || exit 1
eval "$(ssh-agent -s)" >/dev/null
trap 'kill "$SSH_AGENT_PID" 2>/dev/null; $V100 "rm -f /tmp/sw_handheld_known_hosts"' EXIT
ssh-add -q "$HH_KEY" 2>/dev/null
K="-o UserKnownHostsFile=/tmp/sw_handheld_known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=25"
ssh -A -o ConnectTimeout=30 -o BatchMode=yes WZU_V100 "scp $K $SRC $HH_USER@$HH_HOST:apps/shouwang/shouwang.x86_64.new" || { echo "传输失败"; exit 1; }

echo "== 在掌机上换包 =="
on_handheld "$want" <<'REMOTE' || exit 1
cd "$HOME/apps/shouwang" || exit 1
got=$(sha256sum shouwang.x86_64.new | cut -c1-64)
if [ "$got" != "$1" ]; then echo "新包校验不对，不换：$got"; rm -f shouwang.x86_64.new; exit 1; fi
chmod +x shouwang.x86_64.new
# 掌机上已经是同一个包了就不换：.prev 里留着的那一版（真正能回退用的那一版）不动
if [ "$(sha256sum shouwang.x86_64 2>/dev/null | cut -c1-64)" = "$got" ]; then
	rm -f shouwang.x86_64.new
	echo "掌机上已经是这个包了，没有换；上一版还在 shouwang.x86_64.prev"
	exit 0
fi
rm -f shouwang.x86_64.prev
[ -f shouwang.x86_64 ] && mv shouwang.x86_64 shouwang.x86_64.prev
mv shouwang.x86_64.new shouwang.x86_64
echo "已换好：现在生效的是 ${got:0:16}…，上一版留作 shouwang.x86_64.prev"
ls -la | awk 'NR > 3 {print "  " $5 "  " $9}'
exit 0
REMOTE

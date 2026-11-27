#!/bin/bash
# 只做语法和编译检查（不开窗口、不跑游戏）：把 scripts/ 和 tools/ 下的脚本逐个让 Godot 解析一遍，报出哪一行有错。
# 写代码的时侯先过这一道，比导入快：导入日志里只报"依赖它的脚本编译不过"，出错的那一行不一定打出来。
# 这个办法不加载自动加载的节点，脚本里用到 Game、SceneManager、PadAdapter 这些名字会报"找不到"——那是这里查不了的，
# 不算错；"依赖的脚本编译不过""解析不了全局类"也是连带的。只认脚本自己的 Parse Error 和别的 Compile Error。
# 用法（在本机）: tools/playtest/agent.sh a7 check      先要 sync 过。退出码：都解析得过是 0
R="$1"; cd "$R/project" || exit 1
G=~/apps/godot/Godot_v4.7.2-stable_linux.x86_64
fail=0
for f in $(ls scripts/*.gd scripts/*/*.gd tools/*.gd 2>/dev/null); do
	# 每条报错两行：报错的那一行、"at:" 指的文件和行号。只留这个脚本自己的
	out=$($G --headless --path . --check-only --script "res://$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
		| grep -A1 'SCRIPT ERROR: \(Parse\|Compile\) Error' \
		| grep -v 'Could not parse global class\|Could not resolve class\|Failed to compile depended scripts\|Identifier not found: \(Game\|SceneManager\|PadAdapter\)$\|^--$' \
		| grep -B1 "at: GDScript::reload (res://$f:" | grep 'SCRIPT ERROR' | sort -u | head -n 12)
	if [ -n "$out" ]; then
		echo "== $f"; echo "$out" | cut -c1-230; fail=1
	fi
done
[ "$fail" = 0 ] && echo "RESULT 脚本检查：都解析得过" || echo "RESULT 脚本检查：有脚本解析不过"
exit $fail

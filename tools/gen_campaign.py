#!/usr/bin/env python3
"""主线关卡的唯一定义处：12 张棋盘（3 章 × 4 关）。

棋盘用字符画表示，一行一个字符串，x 向右、z 向下：
    .   普通格          空格 水（没有格子）
    S   起点（整张图只能有一个）       P   终点传送门（只能有一个）
    c   脆格：离开后碎掉，过一会儿重新长出来
    x   障碍：不能落上去
    s   补给格：踩上去不扣步数，反而加步数，每格每关一次

起点旁边至少要有两个能走的格子：开局只有一条路可走的话，第一步就是被逼的。

运行这个脚本会先校验所有棋盘，再把它们写成 Godot 的资源文件 resources/campaign/*.tres。
只用到标准库。用法: python3 gen_campaign.py <工程根目录>
"""
import os
import sys

# (文件名, 关卡名, 章, 棋盘, 吃几条鱼开传送门, 起始资源数)
LEVELS = [
    # 第一章：只看形状，学会"连击越大跳得越远"
    ("c1_1", "石步", 1, [
        "S....",
        ".....",
        "....P",
    ], 6, 5),
    ("c1_2", "环桥", 1, [
        " ..... ",
        " .   . ",
        ".S....P",
        " .   . ",
        " ..... ",
    ], 7, 5),
    ("c1_3", "荷塘", 1, [
        "S....",
        ".....",
        "..... ...P",
        "     .....",
    ], 6, 6),
    ("c1_4", "十字河", 1, [
        "  ...  ",
        "  ...  ",
        ".S....P",
        "  ...  ",
        "  ...  ",
    ], 6, 6),
    # 第二章：脆格
    ("c2_1", "断桥", 2, [
        "S....ccccc....P",
        ".....ccccc.....",
    ], 10, 6),
    ("c2_2", "回廊", 2, [
        ".....",
        "S....",
        "...c.",
        ".ccc.",
        "....P",
    ], 10, 6),
    ("c2_3", "碑林", 2, [
        "S..c...c..P",
        "...c...c...",
    ], 8, 7),
    ("c2_4", "鼓亭", 2, [
        "S..s..c..s..P",
        ".....c...c...",
    ], 9, 7),
    # 第三章：障碍，加上前面所有东西
    ("c3_1", "巷陌", 3, [
        "S...x...x..P",
        "....x...x...",
        "............",
        "....x...x...",
        "....x...x...",
    ], 14, 7),
    ("c3_2", "堡墙", 3, [
        ".xxxxxxxxxxx.",
        ".x.........x.",
        ".x.xxxxxxx.x.",
        ".x.x..P..x.x.",
        ".x.x.....x.x.",
        ".x.xxx.xxx.x.",
        ".x.........x.",
        ".xxx..x..xxx.",
        "S...cc.cc....",
    ], 15, 7),
    ("c3_3", "城垛", 3, [
        "S....x....P",
        ".....x.....",
        "..x..x..x..",
        ".....x.....",
        "....x....s.",
    ], 13, 8),
    ("c3_4", "远巡", 3, [
        "S....cc....x....",
        ".....cc....x..s.",
        ".x..............",
        ".x..cccc..x.....",
        "....c...c..x..P.",
        "....c...c..x....",
    ], 18, 8),
]

# 每章一个主色，取的是传统颜料色，也是这一章的景色（水面、够得着的格子都跟着这个颜色走）：
#   第 1 章 水乡生活：石绿（青绿的河水）   第 2 章 家族传承：赭石（灯火映着的暖色）
#   第 3 章 节庆巡游：朱砂（一片红）
CHAPTER_COLORS = {
    1: "Color(0.13, 0.52, 0.44, 1)",
    2: "Color(0.70, 0.45, 0.16, 1)",
    3: "Color(0.80, 0.20, 0.13, 1)",
}
WALKABLE = set(".SPcs")
# 跳跃范围：1.0 + 0.1 的余量，再加满连击的 2.0，即最远约 3.1 格；这里按 3.1 的平方算
MAX_JUMP2 = 3.1 * 3.1


def validate(name, rows):
    """检查一张棋盘：恰好一个起点和一个传送门，且所有能走的格子四方向连通"""
    starts = [(x, z) for z, row in enumerate(rows) for x, ch in enumerate(row) if ch == "S"]
    portals = [(x, z) for z, row in enumerate(rows) for x, ch in enumerate(row) if ch == "P"]
    if len(starts) != 1:
        raise SystemExit("%s: 起点应有 1 个，实际 %d 个" % (name, len(starts)))
    if len(portals) != 1:
        raise SystemExit("%s: 传送门应有 1 个，实际 %d 个" % (name, len(portals)))
    bad = sorted({ch for row in rows for ch in row} - WALKABLE - set("x "))
    if bad:
        raise SystemExit("%s: 有不认识的字符 %s" % (name, bad))
    cells = {(x, z) for z, row in enumerate(rows) for x, ch in enumerate(row) if ch in WALKABLE}
    # 开局要有得选：起点旁边至少有两个能走的格子，否则第一步就是被逼的
    sx, sz = starts[0]
    around = sum(((sx + dx, sz + dz) in cells) for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    if around < 2:
        raise SystemExit("%s: 起点旁边只有 %d 个能走的格子，开局只有一条路可走" % (name, around))
    # 按"满连击时最大能跳约 3 格"来判连通：只要求相邻一步能走到的格子必须四方向相连，
    # 隔着沟的岛允许存在，但沟的宽度不能超过一跳
    seen, queue = {starts[0]}, [starts[0]]
    while queue:
        x, z = queue.pop()
        for nx, nz in cells:
            if (nx, nz) not in seen and (nx - x) ** 2 + (nz - z) ** 2 <= MAX_JUMP2:
                seen.add((nx, nz))
                queue.append((nx, nz))
    if seen != cells:
        lost = sorted(cells - seen)
        raise SystemExit("%s: 有 %d 个能走的格子连满连击也跳不到，例如 %s" % (name, len(lost), lost[:4]))
    kinds = {ch: sum(row.count(ch) for row in rows) for ch in ".SPcsx"}
    return kinds


def tres(name, title, chapter, rows, fish, credits):
    lines = [
        "[gd_resource type=\"Resource\" script_class=\"LevelResource\" load_steps=2 format=3]",
        "",
        "[ext_resource type=\"Script\" path=\"res://scripts/level_resource.gd\" id=\"1_lr\"]",
        "",
        "[resource]",
        "script = ExtResource(\"1_lr\")",
        "level_name = \"%s\"" % title,
        "chapter = %d" % chapter,
        "map = Array[String](%s)" % json_strings(rows),
        "base_color = %s" % CHAPTER_COLORS[chapter],
        "fish_before_end_portal = %d" % fish,
        "starting_credits = %d" % credits,
        "",
    ]
    return "\n".join(lines)


def json_strings(rows):
    # Godot 的字符串字面量与 JSON 一致：双引号包裹，反斜杠和双引号要转义
    def q(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return "[" + ", ".join(q(r) for r in rows) + "]"


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    out_dir = os.path.join(root, "resources", "campaign")
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, title, chapter, rows, fish, credits in LEVELS:
        kinds = validate(name, rows)
        total += 1
        with open(os.path.join(out_dir, name + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(tres(name, title, chapter, rows, fish, credits))
        print("%-5s %-9s 第%d章  %2d 行 × 宽 %-2d  能走 %2d 格（脆格 %d 补给 %d）障碍 %2d  鱼 %2d  资源 %d" % (
            name, title, chapter, len(rows), max(len(r) for r in rows),
            kinds["."] + kinds["S"] + kinds["P"] + kinds["c"] + kinds["s"], kinds["c"], kinds["s"], kinds["x"], fish, credits))
    print("校验通过并写出 %d 个关卡文件到 %s" % (total, os.path.relpath(out_dir, root)))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""把 tools/tier_rates.gd 的输出（tools/playtest/agent.sh a7 rates … 打出来的字）整理成表，换进 tools/playtest/rates.md。

rates.md 里有两段是用数据生成的，各用一对记号围起来；别的话（怎么量的、试过哪些数、夜巡的敏感性）是手写的，不动：
    <!-- 结论：开始 --> … <!-- 结论：结束 -->          四档的总结表
    <!-- 每一关：开始 --> … <!-- 每一关：结束 -->      每一档巡夜、长夜、游戏里摆好的 12 局

用法（在本机，工程根目录下）:
    tools/playtest/agent.sh a7 rates 200 > builds/rates.txt        # 先量一遍（四档各 200 局）
    python3 tools/playtest/rates_report.py builds/rates.txt         # 把表换进 tools/playtest/rates.md
    python3 tools/playtest/rates_report.py builds/easy.txt builds/rest.txt   # 分几回量的也行：同一档以靠后的那个为准
只依赖 Python 自带的东西，不跑 Godot。
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MD = os.path.join(HERE, "rates.md")
ORDER = ["简单", "中等", "困难", "非常困难"]


def load(paths):
    """读几份输出，按档名合并（靠后的文件里的同一档覆盖前面的）。返回 {档名: 那一档的正文}"""
    blocks = {}
    for path in paths:
        text = open(path, encoding="utf-8").read()
        for piece in re.split(r"\n==== ", "\n" + text):
            m = re.match(r"(.+?) ====\n(.*)", piece, re.S)
            if m:
                blocks[m.group(1).split("（")[0].strip()] = m.group(2).strip("\n")
    return blocks


def table(block, head, stop):
    """head 那一行标题到 stop 那一行之间的表：每一行拆成几栏（一关一行）"""
    m = re.search(re.escape(head) + r"[^\n]*\n(.*?)\n   " + stop, block, re.S)
    if not m:
        raise SystemExit("输出里找不到「%s」这一段。是不是没用 agent.sh a7 rates 跑出来的？" % head)
    rows = []
    for line in m.group(1).split("\n")[1:]:
        p = line.split()
        if p and p[0].isdigit():
            rows.append(p)
    return rows


def one(block, pattern):
    m = re.search(pattern, block)
    return m.group(1) if m else "?"


def fixed(block):
    """游戏里摆好的那 12 局下面的几行结论（字符画的行以"    | "开头，跳过）"""
    lines = []
    on = False
    for line in block.split("\n"):
        if line.startswith("游戏里摆好的那 12 局"):
            on = True
            continue
        if not on:
            continue
        if line.startswith("长夜前") or line.startswith("===="):
            break
        if line.strip() and not line.startswith("    | "):
            lines.append(line.strip())
    return lines


def md_table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for p in rows:
        out.append("| " + " | ".join(p) + " |")
    return "\n".join(out) + "\n"


def summary(blocks):
    out = ["| 难度 | 巡夜整局打通 | 巡夜每关平均 | 长夜 12 更全过 | 摆好的 12 局：照路线走 | 摆好的 12 局：贪心，每关带满步数 |", "|---|---|---|---|---|---|"]
    for name in ORDER:
        b = blocks[name]
        f = fixed(b)
        route = re.sub(r"^.*：", "", f[0]).strip() if len(f) > 0 else "?"
        greedy = re.sub(r"^.*：", "", f[2]).strip() if len(f) > 2 else "?"
        out.append("| %s | %s%% | %s%% | %s%% | %s | %s |" % (
            name, one(b, r"整局打通 ([\d.]+)%"), one(b, r"每一关平均过关率 ([\d.]+)%"), one(b, r"\d+ 更全过 ([\d.]+)%"), route, greedy))
    return "\n".join(out) + "\n"


def per_tier(blocks):
    out = []
    for name in ORDER:
        b = blocks[name]
        rules = re.search(r"==== [^\n]+\n   ([^\n]+)", b)
        out.append("### %s\n" % name)
        if rules:
            out.append("`%s`\n" % rules.group(1).strip())
        out.append("巡夜，%s 局（每局从第一关打起，没过就停；步数带过关的档，下一关带着上一关剩下的步数）：" % one(b, r"巡夜 (\d+) 局"))
        out.append("")
        out.append(md_table(["关", "名称", "到了", "过了", "过关率", "平均踩空", "平均放灯", "蜡烛烧完", "换过风向", "摆不出来"],
                            [p[:10] for p in table(b, "巡夜 ", "整局打通")]))
        out.append("整局打通 **%s%%**，每关平均 **%s%%**。\n" % (one(b, r"整局打通 ([\d.]+)%"), one(b, r"每一关平均过关率 ([\d.]+)%")))
        out.append("长夜前 12 更，%s 局（长夜里每一档都带步数，每更补一步）：" % one(b, r"长夜前 \d+ 更，(\d+) 局"))
        out.append("")
        # 长夜的行是"1  第 1 更  到了 过了 …"：名称占了三栏
        out.append(md_table(["更", "到了", "过了", "过关率", "平均踩空", "平均放灯", "蜡烛烧完", "换过风向", "摆不出来"],
                            [[p[0]] + p[4:12] for p in table(b, "长夜前 ", r"\d+ 更全过")]))
        out.append("12 更全过 **%s%%**。\n" % one(b, r"\d+ 更全过 ([\d.]+)%"))
        f = fixed(b)
        if f:
            out.append("游戏里摆好的那 12 局：\n")
            out.extend("- " + line for line in f)
            out.append("")
    return "\n".join(out) + "\n"


def swap(text, name, body):
    a = "<!-- %s：开始 -->" % name
    z = "<!-- %s：结束 -->" % name
    if text.count(a) != 1 or text.count(z) != 1:
        raise SystemExit("rates.md 里找不到一对「%s」记号" % name)
    i = text.index(a) + len(a)
    j = text.index(z)
    return text[:i] + "\n" + body + text[j:]


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    blocks = load(argv)
    missing = [n for n in ORDER if n not in blocks]
    if missing:
        raise SystemExit("输出里没有这几档：%s（认出来的档名：%s）" % ("、".join(missing), "、".join(blocks)))
    text = open(MD, encoding="utf-8").read()
    text = swap(text, "结论", summary(blocks))
    text = swap(text, "每一关", per_tier(blocks))
    open(MD, "w", encoding="utf-8", newline="").write(text)
    print("已把 %s 的结论表和每一关的表换进 %s" % ("、".join(argv), os.path.relpath(MD, os.getcwd())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

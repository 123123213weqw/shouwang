#!/usr/bin/env python3
"""渔娘（bomber.png，选人卡片上第 3 张）：渔家姑娘——头发梳得溜圆，两边各垂一条辫子，辫梢打到胸口，
鬓边别一朵小花。

和原版的图一样是 236×248 的画布，图形落在原版 bomber.png 的范围里（x 58..176、y 73..174）。
轮廓是个"Π"字：圆头在中间，两条一节一节（外沿是连着的鼓包）的辫子垂在两边，辫子和脸之间留着一道
朝下张开的口子——别的角色都没有这个形状。范围只有 119 像素宽，分给两条辫子各 18、两道口子各 11，
脸就只有 63 像素宽（和守夜人的脸差不多）。

游戏里镜头是俯视的，头在屏幕上竖向只压到一半多一点：竖着量的东西（辫子的长短、口子的深浅）都会变短，
横着量的东西（辫子多粗、口子多宽）不变，所以辫子画到 18 像素粗、口子 11 像素宽。

用法: python3 -I netgirl.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 bomber.png。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


fig = _load("figure")
doodle = fig.doodle
REL = "assets/sprites/characters/bomber.png"
CX = 117.5                        # 这张图的中线


def head():
    """头发和脸：头顶溜圆（顶在 y 73，范围的顶），往脸收进去一点，下巴圆"""
    d = doodle.Mask(236, 248)
    d.shape([
        (87, 112),
        (81, 100),
        (83, 88),
        (92, 78),
        (106, 73.5),
        (117.5, 72.8),
        (129, 73.5),
        (143, 78),
        (152, 88),
        (154, 100),
        (148, 112),
        (147, 140),
        (144, 154),
        (136, 164),
        (127, 168.5),
        (117.5, 169.5),
        (108, 168.5),
        (99, 164),
        (91, 154),
        (88, 140),
    ])
    return d


def braids():
    """两条辫子：各是一串圆鼓包，从鬓角垂下来，底在 y 174（范围的底）。
    每条 4 个鼓包，外沿一收一放就是辫子的节"""
    d = doodle.Mask(236, 248)
    for side in (1, -1):
        for x, y, r in ((74, 101, 9), (67, 118, 8.5), (66.6, 135, 8.5), (66.6, 152, 8.5), (67, 166.6, 8)):
            x = CX + side * (x - CX)
            d.ellipse((x - r, y - r, x + r, y + r))
    return d


def flower():
    """鬓边的小花：右边辫子根上、头发鼓出来的地方，五个花瓣"""
    d = doodle.Mask(236, 248)
    cx, cy, R = 149, 84, 6.5
    for k in range(5):
        a = -math.pi / 2 + k * 2 * math.pi / 5
        x, y = cx + R * math.cos(a), cy + R * math.sin(a)
        d.ellipse((x - 5, y - 5, x + 5, y + 5))
    d.ellipse((cx - 5.5, cy - 5.5, cx + 5.5, cy + 5.5))
    return d


def build():
    h = head()
    h.union(braids())
    h.union(flower())
    h.soften(1.2)                # 鼓包之间的节抹圆一点，花和头发接上
    h.cut(fig.eyes([(105, 133), (130, 133)], 7.5, 8.5))
    return h.alpha()


if __name__ == "__main__":
    img = fig.to_canvas(build())
    ok = fig.verify(img, REL)
    if not fig.pure_white(img):
        print("  [不合格] 有不是纯白的不透明像素"); ok = False
    print("自检：%s" % ("合格" if ok else "不合格"))
    chars = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "sprites", "characters"))
    out = fig.write(img, sys.argv[2] if len(sys.argv) > 2 else None, "bomber.png")
    if len(sys.argv) > 1:
        fig.preview(sys.argv[1], "渔娘 bomber.png", out, os.path.join(chars, "body.png"), REL, fig.CHARS + "body.png")

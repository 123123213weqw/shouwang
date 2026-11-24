#!/usr/bin/env python3
"""货郎的技能图标：原版是美元符号 → 铜钱串。

画布 311×316，图形落在原版的范围里（x 103..210， y 71..245），纯白实心。
三枚铜钱（外圆、中间一个方孔）竖着串成一串，一枚压着上一枚的下沿，左右略略错开，像挂在绳上自然垂着；
最上面那枚的顶上露出打了一个结的绳头。
游戏里这个图标只有 34×56 屏幕像素（HUD 的技能按钮，zoom 0.32）：铜钱 22 个屏幕像素大，
方孔 5 个多屏幕像素宽，每枚铜钱都露出大半个圆，认得出是三枚。

用法: python3 -I coin_string.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/dollar.png
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/dollar.png"
CANVAS = (311, 316)
W, H = 107, 174                 # 设计范围 = 原版的图形范围

D = 70.0                        # 铜钱的直径（≈ 22 屏幕像素）
HOLE = 17.0                     # 方孔的边长（≈ 5.4 屏幕像素）
COINS = (                     # 三枚铜钱：圆心的 x、y，直径，方孔转了多少度。绳是弯的，钱也一枚一个样（手画的没有两枚一样的）
    (44.0, 52.0, 73.0, -14.0),
    (62.0, 103.0, 67.0, 11.0),
    (41.0, 154.0, 71.0, -5.0),
)
KNOT = (47.0, 9.0, 19.0)        # 绳头上的结：圆心的 x、y 和直径，一半埋在最上面那枚铜钱里


def draw():
    d = doodle.Mask(W, H)
    holes = doodle.Mask(W, H)
    h = HOLE / 2
    for x, y, dia, deg in COINS:
        d.ellipse((x - dia / 2, y - dia / 2, x + dia / 2, y + dia / 2))          # 铜钱的外圆
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        holes.polygon([(x + px * c - py * s, y + px * s + py * c) for px, py in ((-h, -h), (h, -h), (h, h), (-h, h))])   # 方孔，转一个角度
    # 绳：从结往下、在铜钱后面弯着穿过去，在三枚钱之间露出一小截
    d.path([(44.0, 14.0), (53.0, 78.0), (52.0, 130.0), (42.0, 172.0)], 11.0)
    holes.soften(0.8)
    kx, ky, kd = KNOT
    d.ellipse((kx - kd / 2, ky - kd / 2, kx + kd / 2, ky + kd / 2))               # 绳头上的结
    d.soften(1.2)
    d.cut(holes)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL), hand=dict(seed=734, wobble=0.018, thick=0.026, tilt=0))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

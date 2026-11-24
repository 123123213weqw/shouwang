#!/usr/bin/env python3
"""技能按钮上的叉号：原版是一根斜着的粗棒，照同样的姿态用脚本重画。

画布 379×355，图形落在原版的范围里（x 34..344， y 42..313），纯白实心。
游戏里拿两张这张图叠成一个叉：一张正着放，另一张转 91.6°。所以这张图只是叉的一笔——
从左下到右上、两头是圆头的一根粗棒，方向照原版的来（沿着图形范围的对角线），叠出来的叉才是正的。
屏幕上一笔大约 106×93 像素（zoom 0.34），很粗，什么都不用挖。

用法: python3 -I cross.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/cross.png
"""
import importlib.util
import math
import random
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/cross.png"
CANVAS = (379, 355)
W, H = 310, 271                 # 设计范围 = 原版的图形范围

A = (34.0, 238.0, 56.0)         # 起笔（左下）：圆心和这里的粗细。起笔重，粗
B = (280.0, 30.0, 46.0)         # 收笔（右上）：圆心和这里的粗细。收笔细一点


def draw():
    """马克笔的一笔：整笔微微弯着、粗细沿着长度在变，两头是笔头劈开的几根须子（原版就是这样）"""
    d = doodle.Mask(W, H)
    (x0, y0, w0), (x1, y1, w1) = A, B
    dx, dy = x1 - x0, y1 - y0
    L = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / L, dy / L                  # 笔画的方向
    nx, ny = uy, -ux                          # 和笔画垂直的方向
    n = 8
    pts, widths = [], []
    for i in range(n + 1):
        t_ = i / n
        bow = 7.0 * math.sin(math.pi * t_)    # 整笔弯一点：中段往垂直方向偏 7 个像素
        pts.append((x0 + dx * t_ + nx * bow, y0 + dy * t_ + ny * bow))
        widths.append(w0 + (w1 - w0) * t_ + 3.0 * math.sin(math.pi * t_ * 2.3))   # 中间还有一处略鼓
    for i in range(n):
        d.capsule(pts[i], pts[i + 1], (widths[i] + widths[i + 1]) / 2.0)
    # 两头的须子：从这一头的圆心附近往笔画的反方向（或正方向）伸出几根粗细、长短都不一样的短线
    rng = random.Random(8)
    for (x, y, w), s in ((A, -1.0), (B, 1.0)):
        for _ in range(7):
            ox, oy = (rng.random() - 0.5) * w * 0.8, (rng.random() - 0.5) * w * 0.8
            length = w * (0.10 + 0.22 * rng.random())
            d.capsule((x + ox * 0.7, y + oy * 0.7), (x + ox * 0.7 + ux * length * s, y + oy * 0.7 + uy * length * s),
                      w * (0.16 + 0.13 * rng.random()))
    d.soften(0.9)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL), hand=dict(seed=85, wobble=0.012, thick=0.02, tilt=0, grain=0.006))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

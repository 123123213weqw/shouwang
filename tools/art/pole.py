#!/usr/bin/env python3
"""竹篙（原来是手杖的那张图）：upgrade-cane.png。

和原版的手杖一样：156×136 的画布，图形落在同一块范围里（x 10..136，y 22..126，127×105），纯白、实心，
细节用挖空的洞表示；游戏在运行时把颜色乘上去。

画的是一根斜着的竹篙：从范围的左下角（根，粗）伸到右上角（梢，细），一节比一节细，
中间挖三道横着的短槽当竹节。短槽两头不到竹竿的边（各留两三个像素的皮），整根竹竿始终是一整块——
要是槽把竿切断，几节竹竿就成了互不相连的几块，着色器一抖它们会错位。

用法: python3 -I pole.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 upgrade-cane.png。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("a2_common", os.path.join(HERE, "a2_common.py"))
common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(common)
doodle = common.doodle

REL = common.DIR + "upgrade-cane.png"
NAME = "upgrade-cane.png"
W, H = 127, 105            # 设计范围 = 原版手杖的图形范围（宽、高）

DEFAULT = dict(
    a=(11, 95),            # 竹篙根部的中心（设计范围的坐标）
    b=(116, 10),           # 竹篙梢部的中心
    root=22.0,             # 根部多粗
    tip=17.0,               # 梢部多粗
    nodes=(0.30, 0.57, 0.80),   # 三道竹节在从根到梢的几分之几处（越靠梢部节越短）
    slit=10.0,             # 竹节那道槽多粗
    skin=2.5,              # 槽的两头各留多少皮不挖
)


def lerp(p, q, t):
    return p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t


# 手绘化的力度：这三样身上有细缝，笔画粗细变得太厉害缝会被挤没，所以比默认的轻
HAND = dict(seed=611, wobble=0.014, thick=0.009, tilt=2.5)


def pole(P=None):
    """返回高分辨率的透明度图（设计范围 127×105 的 K 倍）"""
    P = dict(DEFAULT, **(P or {}))
    a, b = P["a"], P["b"]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length             # 沿着竹竿的方向
    nx, ny = -uy, ux                               # 垂直于竹竿的方向

    def width(t):                                  # 离根部 t 处竹竿有多粗
        return P["root"] + (P["tip"] - P["root"]) * t

    body = doodle.Mask(W, H)
    cuts = (0.0,) + tuple(P["nodes"]) + (1.0,)
    for t0, t1 in zip(cuts, cuts[1:]):             # 一节一节地画，每一节从粗到细
        p, q = lerp(a, b, t0), lerp(a, b, t1)
        w0, w1 = width(t0), width(t1)
        body.polygon([(p[0] + nx * w0 / 2, p[1] + ny * w0 / 2), (q[0] + nx * w1 / 2, q[1] + ny * w1 / 2),
                      (q[0] - nx * w1 / 2, q[1] - ny * w1 / 2), (p[0] - nx * w0 / 2, p[1] - ny * w0 / 2)])
        body.capsule(p, p, w0)
        body.capsule(q, q, w1)
    body.soften(1.5)

    holes = doodle.Mask(W, H)
    for t in P["nodes"]:                           # 竹节：垂直于竹竿的一道直槽，两头留皮
        c = lerp(a, b, t)
        half = (width(t) - 2 * P["skin"]) / 2      # 槽的两头是平的，槽的总长就是"竹竿多粗减去两边的皮"
        h = P["slit"] / 2
        holes.polygon([(c[0] - nx * half - ux * h, c[1] - ny * half - uy * h), (c[0] + nx * half - ux * h, c[1] + ny * half - uy * h),
                       (c[0] + nx * half + ux * h, c[1] + ny * half + uy * h), (c[0] - nx * half + ux * h, c[1] - ny * half + uy * h)])
    holes.soften(0.8)

    out = doodle.Mask(W, H)
    out.fill = body.fill.copy()
    out.cut(holes)
    return out.alpha()


def render(P=None):
    return doodle.place(pole(P), common.CANVAS, doodle.orig_box(REL), hand=HAND)


if __name__ == "__main__":
    imgs = [(NAME, render())]
    if len(sys.argv) > 1:      # 给了预览图的路径才出预览图
        common.preview(sys.argv[1], [("竹篙", REL, imgs[0][1])])
    if len(sys.argv) > 2:
        common.save(imgs, sys.argv[2])
    else:
        # 不给输出目录就写进工程（别的画图脚本都是这样）
        common.save(imgs, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "sprites", "upgrades"))

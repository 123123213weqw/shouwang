#!/usr/bin/env python3
"""格子上的装饰三（assets/sprites/foliages/algae-2.png）：两道弯弯的水波纹。

原版是两根分叉的水藻（256×256 的画布，图形在 x 74..165、y 137..230，左右两块）。新图是同一块范围里的
两道水波：上下各一道粗粗的波浪线，一上一下并行着，像水面上推开的两道涟漪。两道线是分开的两块，
间距比原版两块水藻（6 像素）宽得多。
为什么是两道不是三道：这个装饰是一张竖着的画片，被俯视的镜头压得很扁，竖直方向一个纹理像素只有
0.16 到 0.26 个屏幕像素。三道线挤在 94 像素高里，线与线的缝远看只有两个多像素，会糊成一片；两道才分得开。
线条的粗细照原版水藻来（原版 15 到 20 像素宽）。

用法: python3 -I ripple.py [预览图的输出路径]
  不带参数只把图写到工程里并自检；带了参数再出一张对比图（原版 | 新图 | 叠在一起）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL = "assets/sprites/foliages/algae-2.png"
ZOOM_MIN = 0.24                            # 最小的情况：和 algae.png 一样是第 12 关最远一排

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

CANVAS = doodle.orig_size(REL)             # (256, 256)
BOX = doodle.orig_box(REL)                 # 原版图形的范围 (74, 137, 92, 94)
W, H = BOX[2], BOX[3]                      # 设计范围：92 宽、94 高

LINE_W = 16.0                              # 每道波的粗细
AMP = 8.0                                  # 波浪的幅度（波峰到波谷的一半）
WAVE = 1.0                                 # 每道波里有几个来回（一个来回就是一条完整的「～」）
ROWS = (0.22, 0.78)                        # 两道波的中心各在范围的哪个高度（隔得开，远看也分得清是两道）
PHASE = (0.0, 0.0)                         # 上下两道同起同落（试过错开半个波：两道线斜着插到一起，缝反而变窄）


def wave_row(cy, phase, x0, x1):
    """一道波：沿着一条正弦线的圆头粗线，两端略略往上翘一点（像水纹收尾的小回钩）"""
    m = doodle.Mask(W, H)
    pts = []
    n = 40
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = cy + AMP * math.sin(2 * math.pi * WAVE * t + phase)
        pts.append((x, y))
    m.path(pts, LINE_W)
    m.soften(0.4)
    return m


def build():
    """返回设计范围里的透明度图（高分辨率）：两道分开的水波"""
    m = doodle.Mask(W, H)
    x0, x1 = LINE_W / 2 + 0.5, W - LINE_W / 2 - 0.5
    for row, ph in zip(ROWS, PHASE):
        m.union(wave_row(H * row, ph, x0, x1))
    return m.alpha()


def render(alpha):
    """把设计范围里的图等比缩进原版图形的范围、放到 256×256 的画布上（纯白）"""
    return doodle.place(alpha, CANVAS, BOX)


if __name__ == "__main__":
    img = render(build())
    img.save(os.path.join(ROOT, REL))
    print("已写出", REL)
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("algae-2 水波纹  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL), REL)], cell=300)
        print("预览图:", sys.argv[1])
    doodle.check(os.path.join(ROOT, REL), REL, zoom=ZOOM_MIN, kind="3d")

#!/usr/bin/env python3
"""格子上的装饰四（assets/sprites/foliages/algae-3.png）：三片浮萍的小圆叶。

原版是三根分叉的水藻（256×256 的画布，图形在 x 63..212、y 152..236，左中右三块，中间那块最高）。
新图照原版的布局：三片浮萍的小圆叶，中间一片略大、略高，左右两片略小、略低，三片是分开的三块，
间距不比原版近。三片叶子的姿态各不相同（中间的略向左歪、左边的一片近圆、右边的一片是卵形），
像随手点出来的三片浮萍，不是三颗一样大的石子。
为什么选浮萍不选菱角：这块范围又宽又矮，在这张被俯视镜头压扁的画片上，横躺的菱角会被压成一条
六七个像素高的弯线，看不出是什么；圆叶是一个面，压扁了也还是一片叶子。
试过给叶子下缘加凹口（想做成荇菜那种肾形叶）：远看三片叶子成了三座小拱桥，不像浮萍，所以没有用。
叶片的大小照原版来（原版每块 34 到 47 像素宽），不比它小。

用法: python3 -I duckweed.py [预览图的输出路径]
  不带参数只把图写到工程里并自检；带了参数再出一张对比图（原版 | 新图 | 叠在一起）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL = "assets/sprites/foliages/algae-3.png"
ZOOM_MIN = 0.24                            # 最小的情况：和 algae.png 一样是第 12 关最远一排

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

CANVAS = doodle.orig_size(REL)             # (256, 256)
BOX = doodle.orig_box(REL)                 # 原版图形的范围 (63, 152, 150, 85)
W, H = BOX[2], BOX[3]                      # 设计范围：150 宽、85 高

# 三片叶子：(中心的横坐标, 中心的纵坐标, 宽, 高, 歪多少度, 卵形程度)。中间的最高最大，和原版中间那块水藻一样
LEAVES = [(W / 2, 25.0, 44.0, 41.0, -6.0, 0.10), (21.0, 58.0, 38.0, 34.0, 8.0, 0.0), (W - 21.0, 57.0, 38.0, 33.0, -10.0, 0.14)]


def leaf(cx, cy, w, h, tilt, egg):
    """一片浮萍叶：接近圆的椭圆，歪 tilt 度；egg > 0 时右端略收窄，是个卵形"""
    m = doodle.Mask(W, H)
    pts = []
    n = 48
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 1 - egg * 0.5 * (1 + math.cos(a))          # 右边（a = 0）缩到 1 - egg
        x, y = w / 2 * r * math.cos(a), h / 2 * r * math.sin(a)
        t = math.radians(tilt)
        pts.append((cx + x * math.cos(t) - y * math.sin(t), cy + x * math.sin(t) + y * math.cos(t)))
    m.polygon(pts)
    m.soften(0.5)
    return m


def build():
    """返回设计范围里的透明度图（高分辨率）：三片分开的浮萍叶"""
    m = doodle.Mask(W, H)
    for leaf_def in LEAVES:
        m.union(leaf(*leaf_def))
    return m.alpha()


def render(alpha):
    """把设计范围里的图等比缩进原版图形的范围、放到 256×256 的画布上（纯白）"""
    return doodle.place(alpha, CANVAS, BOX)


if __name__ == "__main__":
    img = render(build())
    img.save(os.path.join(ROOT, REL))
    print("已写出", REL)
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("algae-3 浮萍  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL), REL)], cell=300)
        print("预览图:", sys.argv[1])
    doodle.check(os.path.join(ROOT, REL), REL, zoom=ZOOM_MIN, kind="3d")

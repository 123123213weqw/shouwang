#!/usr/bin/env python3
"""食盒：原版的宝箱（chest.png）换成一只三层的提盒。棋盘上挡路的那样东西。

和原版的宝箱一样：156×136 的画布，图形落在同一块范围里（x 20..135，y 41..128，115×87），纯白、实心，
不描边、不画明暗。位置、大小、缩放、染色都不变。

画法照原版宝箱的涂鸦来（原版是鼓鼓的盖子、箱身，中间一条抖着、一头粗一头细的缝）：
  提手 往右歪一点的拱，粗细不匀，两只脚插在盖子里；
  盖子 鼓鼓的一块，左边比右边厚，上沿略鼓，比箱身宽一点（盖子压在盒身上）；
  箱身 底是圆的，上面有一道不到头的短缝，是"两层"的意思；
  缝   盖子和箱身之间一条抖着、略斜、一头粗一头细的缝（12 到 15 个纹理像素，原版是 12 到 16）。
第一版画成三条等宽的横板加一个正半圆的提手，太板正，不像手绘；第二版改成三层，两条缝把 87 像素的高度挤得
下面两层只剩 9 到 11 像素，所以定成两大块加一道短缝。
最后再过一遍手绘化（doodle.handdraw）：线抖一抖、粗细变一变、整体歪两三度。

这张图在游戏里最小的时候是 33×22 个屏幕像素（第 12 关最远一排，zoom 0.29），而且落在最远一排时下半截会被
前排的格子挡住，看得见的主要是提手和上面两层。

用法: python3 -I food_box.py [预览图的输出路径]
  总是把 chest.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图（原版 | 新图 | 叠在一起）。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/upgrades/chest.png"
CANVAS = (156, 136)
W, H = 115, 87                  # 设计范围 = 原版图形的范围
HAND = dict(seed=706, wobble=0.02, thick=0.022, tilt=2.5)   # 手绘化的力度（比默认的稍重一点）


def stroke(mask, pts, widths):
    """一条粗细沿着长度在变的线（相邻两点之间画一段两头是圆的线段）。画在 mask 的实心层上，
    之后用 d.cut(mask) 就成了一条挖空的缝"""
    for (x0, y0), (x1, y1), w0, w1 in zip(pts, pts[1:], widths, widths[1:]):
        mask.capsule((x0, y0), (x1, y1), (w0 + w1) / 2.0)


def build():
    d = doodle.Mask(W, H)
    # 提手：往右歪的拱，两只脚插在盖子里
    d.path([(42, 30), (37, 16), (45, 7), (61, 5.5), (75, 10), (82, 20), (83, 30)], 11)
    # 盖子：鼓鼓的一块，左边比右边厚，上沿略鼓，比箱身宽一点
    d.shape([(2, 33), (9, 25), (38, 21), (78, 22), (106, 26), (113, 33), (112, 43), (96, 49), (48, 50), (10, 49), (2, 42)])
    # 箱身：上下两层的盒身，底是圆的
    d.shape([(6, 52), (21, 40), (70, 39), (100, 41), (110, 47), (111, 70), (106, 82), (92, 87), (26, 87), (9, 82), (4, 72)])
    d.soften(0.9)
    gaps = doodle.Mask(W, H)
    # 盖子和箱身之间的缝：抖着、略斜、一头粗一头细（12 到 15 个纹理像素，原版是 12 到 16）
    stroke(gaps, [(-2, 47.4), (28, 45.8), (60, 47.4), (90, 45.2), (117, 44.6)], [12, 13, 15, 13, 11])
    # 箱身上一道不到头的短缝：分层的意思，不把盒身切开
    stroke(gaps, [(27, 69.2), (55, 70.6), (86, 72.4)], [6, 7, 6])
    gaps.soften(0.5)
    d.cut(gaps)
    return d.alpha()


def main():
    img = doodle.place(build(), CANVAS, doodle.orig_box(REL), hand=HAND)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("食盒：原版 | 新图 | 叠在一起", out, REL)], cell=260)


if __name__ == "__main__":
    main()

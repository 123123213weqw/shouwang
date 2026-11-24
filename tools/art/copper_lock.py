#!/usr/bin/env python3
"""选人卡片上"还没解锁"的记号：原版是挂锁 → 中式的铜锁。

画布 311×316，图形落在原版的范围里（x 108..203， y 107..208），纯白实心。
扁长的方锁身（四个角只是略略抹圆），上面一道半圆的铜梁（梁里挖空），锁身正面开一个圆的锁孔。
和原版的挂锁比，锁身更方更厚、梁更粗、梁里的空档更小——看上去是一块沉甸甸的铜疙瘩，而不是轻巧的铁皮挂锁。
游戏里它只有 39×41 屏幕像素（选人卡片，zoom 0.41）：梁里的空档 7 个多屏幕像素宽，锁孔 6 个。

用法: python3 -I copper_lock.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/lock.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/lock.png"
CANVAS = (311, 316)
W, H = 95, 101                   # 设计范围 = 原版的图形范围

BODY_TOP = 50.0                  # 锁身的上沿（锁梁从这里插进锁身）
CORNER = 7.0                     # 锁身的圆角
SHACKLE = (47.5, 27.0)           # 锁梁：半圆拱的圆心
R_OUT, BAR_W = 27.0, 21.0
r_l, r_r = R_OUT - (BAR_W + 3.0) / 2, (R_OUT - 2.0) - (BAR_W + 0.0) / 2    # 左右两根柱子的中线到圆心的距离        # 锁梁的外沿半径、铜梁的粗细（≈ 7.4 屏幕像素）
KEYHOLE = (47.5, 78.0, 14.0)     # 锁孔：圆心的 x、y 和直径（≈ 5.7 屏幕像素）


def draw():
    d = doodle.Mask(W, H)
    # 锁身：鼓鼓的一块（像拿马克笔随手画的），四边都略往外鼓，底比顶宽，整体略歪
    c = CORNER
    d.shape([(c + 2, BODY_TOP + 2), (W * 0.42, BODY_TOP - 1), (W * 0.74, BODY_TOP + 1), (W - c, BODY_TOP + 4),
             (W + 1, H * 0.56), (W - c - 1, H - c), (W * 0.60, H + 1), (W * 0.30, H - 1), (c, H - c + 2), (-1, H * 0.62)])
    d.soften(2.0)
    # 锁梁：左边一根粗，右边一根细，顶上的拱也是一头粗一头细（doodle.arc 的框是弧线的外沿，线朝里加粗）
    cx, cy = SHACKLE
    cx += 2.0                                                  # 拱的圆心往右偏一点
    d.capsule((cx - r_l, BODY_TOP - 6.0), (cx - r_l + 1.5, cy + 1.0), BAR_W + 3.0)
    d.capsule((cx + r_r, BODY_TOP - 6.0), (cx + r_r - 1.0, cy + 2.0), BAR_W)
    d.arc((cx - R_OUT, cy - R_OUT - 1.0, cx + R_OUT - 2.0, cy + R_OUT - 1.0), 180, 360, BAR_W + 1.5)
    d.soften(1.2)
    hole = doodle.Mask(W, H)
    r_in = R_OUT - BAR_W                                       # 拱里面的空档：半圆的拱顶下面一根竖的方孔
    hole.ellipse((cx - r_in + 1.0, cy - r_in - 1.0, cx + r_in - 3.0, cy + r_in - 1.0))
    hole.polygon([(cx - r_in + 1.0, cy - 1.0), (cx + r_in - 3.0, cy - 1.0), (cx + r_in - 3.0, BODY_TOP + 3.0), (cx - r_in + 1.0, BODY_TOP + 3.0)])
    hole.soften(1.0)
    kx, ky, kd = KEYHOLE
    hole.ellipse((kx - 4 - kd / 2, ky - 1 - kd / 2, kx - 4 + kd / 2, ky - 1 + kd / 2))   # 锁孔，偏左一点
    d.cut(hole)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL), hand=dict(seed=539, wobble=0.02, thick=0.03, tilt=4))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

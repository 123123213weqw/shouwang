#!/usr/bin/env python3
"""钓叟的技能图标：原版是张开的嘴（鱼骨头）→ 钓竿。

画布 311×316，图形落在原版的范围里（x 72..240，y 80..236），纯白实心。
一根斜着的钓竿从左下角伸到右上角，线从竿尖垂下来，线的下头弯成一个钩子。
游戏里这个图标只有 54×50 屏幕像素（HUD 的技能按钮，zoom 0.32），线有 3.5 个屏幕像素粗。

用法: python3 -I fishing_rod.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/eat-fish.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/eat-fish.png"
CANVAS = (311, 316)
W, H = 168, 156                 # 设计范围 = 原版的图形范围

BUTT = (14.0, 142.0, 24.0)      # 竿的握把头：圆心的 x、y 和粗细
TIP = (150.0, 14.0, 13.0)       # 竿尖：圆心的 x、y 和粗细
LINE = [(150.0, 16.0), (145.0, 50.0), (139.0, 88.0), (139.0, 108.0)]   # 钓线：从竿尖垂下来，略微往左弯
LINE_W = 11.0                   # 线的粗细（≈ 3.5 屏幕像素）
HOOK = (126.0, 124.0, 13.0)     # 钩子下面那个弯：圆心的 x、y 和半径（钩子的内侧从这儿弯上来）
HOOK_W = 14.0                   # 钩子的粗细（≈ 4.5 屏幕像素）


def rod(d):
    """钓竿：握把头粗、竿尖细的一根锥形的棒"""
    (x0, y0, w0), (x1, y1, w1) = BUTT, TIP
    dx, dy = x1 - x0, y1 - y0
    n = (dy, -dx)
    L = (n[0] ** 2 + n[1] ** 2) ** 0.5
    nx, ny = n[0] / L, n[1] / L
    d.polygon([(x0 + nx * w0 / 2, y0 + ny * w0 / 2), (x1 + nx * w1 / 2, y1 + ny * w1 / 2),
               (x1 - nx * w1 / 2, y1 - ny * w1 / 2), (x0 - nx * w0 / 2, y0 - ny * w0 / 2)])
    d.ellipse((x0 - w0 / 2, y0 - w0 / 2, x0 + w0 / 2, y0 + w0 / 2))
    d.ellipse((x1 - w1 / 2, y1 - w1 / 2, x1 + w1 / 2, y1 + w1 / 2))


def hook(d):
    """钩子：从线的下头往下、往左绕半圈、再往上翘一个尖"""
    cx, cy, r = HOOK
    d.capsule((cx + r, cy - 26.0), (cx + r, cy), HOOK_W)                          # 和线相接的竖着的一段
    d.arc((cx - r, cy - r, cx + r, cy + r), 0, 180, HOOK_W)                       # 下面弯的半圈
    d.capsule((cx - r, cy), (cx - r, cy - 15.0), HOOK_W)                          # 往上翘的钩尖


def draw():
    d = doodle.Mask(W, H)
    rod(d)
    d.path(LINE, LINE_W)
    hook(d)
    d.soften(1.0)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

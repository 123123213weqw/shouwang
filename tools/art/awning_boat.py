#!/usr/bin/env python3
"""船家少年的技能图标：原版是漩涡（传送门）→ 乌篷船。

画布 311×316，图形落在原版的范围里（x 90..221， y 112..220），纯白实心。
两头尖翘的狭长船身，前半截扣着一个拱形的乌篷（篷上两道竖缝，是竹篾一根一根的乌篷），
船尾一支橹斜着翘出去，橹板在上头，和船尾翘起的尖之间空开一个口子。
游戏里这个图标只有 42×35 屏幕像素（HUD 的技能按钮，zoom 0.32）：篷 15×21 个屏幕像素，
篷上的缝 4 个多屏幕像素宽，橹 4.5 个屏幕像素粗，橹和船尾尖之间空 6 个多屏幕像素。

用法: python3 -I awning_boat.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/portal.png
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

REL = "assets/sprites/ui/actions/portal.png"
CANVAS = (311, 316)
W, H = 131, 108                 # 设计范围 = 原版的图形范围

HULL = [                         # 船身：两头尖、往上翘，船底是平缓的弧
    (0, 44, 1), (24, 80), (60, 86), (100, 83), (131, 60, 1),
    (128, 100), (98, 107), (52, 108), (6, 94),
]
CANOPY = [                       # 乌篷：拱形的篷，扣在船身的前半截上
    (10, 88), (11, 48), (14, 32), (26, 18), (42, 16), (54, 28), (58, 48), (59, 88),
]
SLATS = [(26.0, 30.0, 82.0), (43.0, 30.0, 82.0)]      # 篷上的两道竖缝：竹篾一跟一根的乌篷
SLAT_W = 13.0                   # 缝的粗细（≈ 4.2 屏幕像素）
OAR = ((88.0, 104.0), (118.0, 20.0), 14.0)      # 橹：从船尾翘出去的杆；下头的圆心、上头的圆心、粗细
BLADE = (17.0, 28.0)             # 橹板：椭圆的短轴（横着杆）、长轴（顺着杆）


def oar(d):
    (x0, y0), (x1, y1), w = OAR
    d.capsule((x0, y0), (x1, y1), w)
    # 橹板：顺着杆的方向的一个扁椭圆，套在杆的上头上
    a = math.atan2(y1 - y0, x1 - x0)
    sa, la = BLADE[0] / 2, BLADE[1] / 2
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        pts.append((x1 + math.cos(a) * la * math.cos(t) - math.sin(a) * sa * math.sin(t),
                    y1 + math.sin(a) * la * math.cos(t) + math.cos(a) * sa * math.sin(t)))
    d.polygon(pts)


def draw():
    d = doodle.Mask(W, H)
    d.shape(HULL)                                  # 船身
    d.shape(CANOPY)                                # 乌篷
    oar(d)                                         # 橹
    d.soften(1.4)
    hole = doodle.Mask(W, H)
    for x, y0, y1 in SLATS:
        hole.capsule((x, y0), (x, y1), SLAT_W)                       # 篷上的竹篾缝
    hole.soften(0.6)
    d.cut(hole)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

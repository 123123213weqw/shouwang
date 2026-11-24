#!/usr/bin/env python3
"""小鼓手的技能图标：原版是漩涡球 → 更鼓和鼓槌。

画布 311×316，图形落在原版的范围里（x 100..210， y 97..210），纯白实心。
一面横着放的更鼓架在两条往外撇的鼓架腿上：鼓身上下两面鼓皮绷得往外鼓，是一个枕形的桶；
两根鼓槌交叉成叉，下面那两头搭在鼓面上，上面那两头翘起来。
光画"交叉的鼓槌 + 一条横着的鼓身"，在这么小的图里实拍出来像一个叉加一道横杠；把鼓架也画上，
让鼓槌搭在鼓面上，一眼看出是架子上的一面鼓。整个图标连成一块：两根鼓槌和鼓面之间围出一个小三角形的洞。
游戏里这个图标只有 35×36 屏幕像素（HUD 的技能按钮，zoom 0.32），鼓身上别的什么都不挖：
鼓槌的柄 4 个屏幕像素粗、圆头 7 个，腿 4 个半屏幕像素粗。

用法: python3 -I drum_icon.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/combooo.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/combooo.png"
CANVAS = (311, 316)
W, H = 110, 113                 # 设计范围 = 原版的图形范围

# 鼓身：上下两面鼓皮绷得往外鼓，左右两头是圆的竖边
DRUM = [(8, 58), (33, 55), (55, 54.5), (77, 55), (102, 58), (106, 75), (102, 92), (77, 95.5), (55, 96), (33, 95.5), (8, 92), (4, 75)]
LEGS = [((26.0, 90.0), (12.0, 106.0)), ((84.0, 90.0), (98.0, 106.0))]   # 鼓架：两条往外撇的腿（两头的圆心）
LEG_W = 14.0                   # 腿的粗细（≈ 4.5 屏幕像素）
STICKS = [((85.0, 52.0), (12.0, 13.0)), ((27.0, 52.0), (97.0, 3.0))]    # 两根鼓槌：搭在鼓面上的那头、翘起的那头（圆心）。一长一短、一高一低，手画的没有两根一样的
SHAFT_W = 13.0                  # 鼓槌的柄的粗细（≈ 4.2 屏幕像素）
HEAD_D = 22.0                   # 鼓槌两头圆头的直径（≈ 7 屏幕像素）


def draw():
    d = doodle.Mask(W, H)
    d.shape(DRUM)
    d.soften(3.0)
    for p0, p1 in LEGS:
        d.path([p0, p1], LEG_W)                                       # 鼓架
    for tail, head in STICKS:
        d.capsule(tail, head, SHAFT_W)
        for c in (tail, head):                                         # 两头都是圆头
            d.ellipse((c[0] - HEAD_D / 2, c[1] - HEAD_D / 2, c[0] + HEAD_D / 2, c[1] + HEAD_D / 2))
    d.soften(1.0)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL), hand=dict(seed=421, wobble=0.018, thick=0.026, tilt=3))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

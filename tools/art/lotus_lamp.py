#!/usr/bin/env python3
"""守夜人的技能图标：原版是伞 → 河灯。

画布 311×316，图形落在原版的范围里（x 79..231，y 81..235），纯白实心，不挖洞（原版的伞也是一整块）。
一朵莲花托着一团火苗：下面是宽宽的花瓣托，外层两片花瓣的尖往两边翘，里面还有两片立得更高的花瓣；
火苗又宽又大，底子直接坐在花托里，中间没有细杆。
（第一版画成"火苗 + 一根细灯芯 + 两头翘的托"，实拍出来是一个船锚，所以去掉了灯芯。）
游戏里这个图标只有 49×49 屏幕像素（HUD 的技能按钮，zoom 0.32）：火苗 17 像素宽，花瓣托 47 像素宽。

用法: python3 -I lotus_lamp.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/umbrella.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/umbrella.png"
CANVAS = (311, 316)
W, H = 152, 154                 # 设计范围 = 原版的图形范围

FLAME = [                        # 火苗：下面圆、上面一个歪向右边的尖（被夜风吹偏了一点）
    (93, 3, 1), (102, 22), (106, 50), (104, 82), (93, 106), (76, 115), (59, 107), (48, 84), (46, 56), (52, 30), (66, 12), (80, 6),
]
DISH = [                         # 花瓣托：外沿从左边外层花瓣的尖绕到底部中间、再到右边外层花瓣的尖；上沿回来时是两片内层花瓣的尖
    (3, 86, 1), (8, 114), (30, 138), (58, 149), (94, 149), (122, 138), (144, 114), (149, 86, 1),
    (130, 92), (124, 62, 1),      # 右边内层花瓣的尖
    (104, 94), (76, 108), (48, 94),
    (28, 62, 1),                  # 左边内层花瓣的尖
    (22, 92),
]


def draw():
    d = doodle.Mask(W, H)
    d.shape(DISH)                                   # 花瓣托
    d.soften(2.0)
    f = doodle.Mask(W, H)
    f.shape(FLAME)                                  # 火苗
    f.soften(1.4)
    d.union(f)
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

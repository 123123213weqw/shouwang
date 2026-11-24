#!/usr/bin/env python3
"""草鞋（原来是鞋子的那张图）：upgrade-shoe.png。

和原版的鞋一样：156×136 的画布，图形落在同一块范围里（x 18..143，y 39..114，126×76），纯白、实心，
细节用挖空的洞表示；游戏在运行时把颜色乘上去。和原版一样是从侧面看、鞋尖朝右。

画的是一只草鞋：
  鞋底：厚厚的一条，鞋尖那边微微翘起来；鞋底的侧面挖几道斜的短槽，是编鞋底的草绳纹；
  鞋面：一根粗草绳带从鞋底的前部升起来、跨过脚背、落回鞋底的中部（下面空着，脚从这里进去）；
  系带：从鞋面带子的后脚里斜着往左上伸出去的一根粗绳，系在脚踝上。
都画得比较粗：原版的鞋是一大块实心的，绳子太细的话自检会报"比原版细碎得多"，游戏里也会抖散。
斜槽都缩在鞋底里面（上下留皮），整只鞋始终是一整块。

用法: python3 -I sandal.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 upgrade-shoe.png。
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

REL = common.DIR + "upgrade-shoe.png"
NAME = "upgrade-shoe.png"
W, H = 126, 76              # 设计范围 = 原版鞋的图形范围（宽、高）

DEFAULT = dict(
    slit=8.0,              # 斜槽多粗（两头是平的，整个是一块斜的小方块）
    slits=(31.0, 62.0, 94.0),   # 每道斜槽下端的 x（鞋底的两头不挖，免得槽的圆头露出鞋底）
    slit_y=(60.0, 72.0),   # 斜槽上端、下端各在哪一行（上下都留着鞋底的皮）
    slit_dx=-7.0,          # 斜槽的上端比下端往左偏多少（草绳是斜着编的）
)

# 鞋底的轮廓（设计范围的坐标，鞋尖在右，两头圆钝、微微上翘）
SOLE = [(2, 56), (3, 71), (14, 78), (56, 79), (96, 77), (117, 71), (125, 59), (120, 49), (100, 48), (60, 50), (26, 51), (7, 50)]
# 鞋面那根带子：从鞋底的前部升起来、跨过脚背、落回鞋底的中部（两头埋在鞋底里，下面空着）
STRAP = [(97, 66), (91, 24), (64, 2), (37, 24), (31, 66), (49, 66), (53, 34), (64, 20), (75, 34), (79, 66)]
TIE = ((46.0, 34.0), (7.0, 4.0), 14.0)          # 系带：从带子的后脚里出来、斜着往左上伸出去（起点、终点、多粗）


# 手绘化的力度：这三样身上有细缝，笔画粗细变得太厉害缝会被挤没，所以比默认的轻
HAND = dict(seed=614, wobble=0.014, thick=0.009, tilt=2.5)


def sandal(P=None):
    """返回高分辨率的透明度图（设计范围 126×76 的 K 倍）"""
    P = dict(DEFAULT, **(P or {}))
    body = doodle.Mask(W, H)
    body.shape(SOLE)                                              # 鞋底
    body.shape(STRAP)                                             # 鞋面的带子
    body.capsule(*TIE)                                            # 系带
    body.soften(1.5)

    holes = doodle.Mask(W, H)
    y1, y0 = P["slit_y"]
    h = P["slit"] / 2
    for x in P["slits"]:                                          # 鞋底侧面的草绳纹：每道是一块斜的小方块
        x1 = x + P["slit_dx"]
        dx, dy = x1 - x, y1 - y0
        length = math.hypot(dx, dy)
        ox, oy = -dy / length * h, dx / length * h               # 垂直于槽的方向上各伸出去半个槽宽
        holes.polygon([(x - ox, y0 - oy), (x1 - ox, y1 - oy), (x1 + ox, y1 + oy), (x + ox, y0 + oy)])
    holes.soften(0.8)

    out = doodle.Mask(W, H)
    out.fill = body.fill.copy()
    out.cut(holes)
    return out.alpha()


def render(P=None):
    return doodle.place(sandal(P), common.CANVAS, doodle.orig_box(REL), hand=HAND)


if __name__ == "__main__":
    imgs = [(NAME, render())]
    if len(sys.argv) > 1:      # 给了预览图的路径才出预览图
        common.preview(sys.argv[1], [("草鞋", REL, imgs[0][1])])
    if len(sys.argv) > 2:
        common.save(imgs, sys.argv[2])
    else:
        # 不给输出目录就写进工程（别的画图脚本都是这样）
        common.save(imgs, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "sprites", "upgrades"))

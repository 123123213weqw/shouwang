#!/usr/bin/env python3
"""捞网（原来是马蹄磁铁的那张图）：upgrade-magnet.png。

和原版的磁铁一样：156×136 的画布，图形落在同一块范围里（x 23..131，y 6..118，109×113），纯白、实心，
细节用挖空的洞表示；游戏在运行时把颜色乘上去。

画的是一把捞鱼的小抄网，从稍高的地方往前看：
  网口是一个横着的椭圆环（中间挖空）；
  网兜从网口的下沿垂下来，是一个往下收口的水滴形袋子：一圈粗的边，里面是网线——横线以上两道竖的，横线以下中间一道，
  围出上面三个、下面两个格（格子是挖空的）；
  短柄从网口的左边斜着往左下伸出来。
网线的两头都插在袋子的边框里，整把网始终是一整块（网格要是不相连，着色器一抖就会散开）。

用法: python3 -I net.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 upgrade-magnet.png。
"""
import importlib.util
import math
import os
import sys

from PIL import ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("a2_common", os.path.join(HERE, "a2_common.py"))
common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(common)
doodle = common.doodle

REL = common.DIR + "upgrade-magnet.png"
NAME = "upgrade-magnet.png"
W, H = 109, 113            # 设计范围 = 原版磁铁的图形范围（宽、高）

DEFAULT = dict(
    c=(67.5, 28.0),        # 网口椭圆的中心
    a=40.0,                # 网口的半宽
    b=26.0,                # 网口的半高（横着的椭圆：从稍高的地方看网口）
    ring=10.0,             # 网口的环有多宽（挖空的是里面往里缩 ring 的椭圆）
    bottom=113.0,          # 网兜的袋底在 y 多少
    handle=(8.5, 37.0),    # 短柄末端（手握的那一头）的中心
    handle_w=16.0,         # 短柄多粗
    cord=9.0,              # 网线和袋子边框有多粗
    cols=(-13.5, 13.5),    # 横线以上两道竖的网线在网口中线左边、右边多远（袋子往下收口，下面只剩中间一道）
    row_y=80.0,            # 那道横的网线在 y 多少
    row_half=26.0,         # 横网线从网口中线往左右各伸多远（两头要插进袋子的边框）
)

# 网兜的外轮廓（设计范围的坐标）：从网口左端出发，两边收拢着下来、绕过圆的袋底、回到网口右端，成一个往下垂的水滴形；
# 两头是尖的，接着沿网口的下沿回去
BAG_OUT = [(27.5, 28, 1), (30, 52), (38, 84), (50, 107), (67.5, 113), (85, 107), (97, 84), (105, 52), (107.5, 28, 1),
           (98, 44), (84, 52), (67.5, 54), (51, 52), (37, 44)]
# 袋子里面（边框以内）
BAG_IN = [(36.5, 46, 1), (39, 52), (45.5, 79), (55.5, 98), (67.5, 104), (79.5, 98), (89.5, 79), (96, 52), (98.5, 46, 1),
          (91, 57), (81, 63), (67.5, 65), (54, 63), (44, 57)]


# 手绘化的力度：这三样身上有细缝，笔画粗细变得太厉害缝会被挤没，所以比默认的轻
HAND = dict(seed=612, wobble=0.014, thick=0.009, tilt=2.5)


def net(P=None):
    """返回高分辨率的透明度图（设计范围 109×113 的 K 倍）"""
    P = dict(DEFAULT, **(P or {}))
    cx, cy, a, b = P["c"][0], P["c"][1], P["a"], P["b"]

    body = doodle.Mask(W, H)
    body.shape(BAG_OUT)                                            # 网兜（先画成实心的）
    body.ellipse((cx - a, cy - b, cx + a, cy + b))                 # 网口（先画成实心的）
    body.capsule((cx - a * 0.88, cy + b * 0.25), P["handle"], P["handle_w"])   # 短柄
    body.soften(1.5)

    holes = doodle.Mask(W, H)
    holes.ellipse((cx - a + P["ring"], cy - b + P["ring"] * 0.75, cx + a - P["ring"], cy + b - P["ring"] * 0.75))   # 网口挖空（上下留得薄一点，环看着是匀的）
    holes.shape(BAG_IN)                                            # 袋子里面挖空
    holes.soften(0.8)

    cords = doodle.Mask(W, H)                                      # 网线：画回实心
    h = P["cord"] / 2
    for dx in P["cols"]:                                           # 横线以上两道竖的：上头贴着网口的下沿插进袋口的边框，下头插进横线
        y_top = cy + b * math.sqrt(max(0.0, 1 - (dx / a) ** 2))
        cords.polygon([(cx + dx - h, y_top + 1.5), (cx + dx + h, y_top + 1.5), (cx + dx + h, P["row_y"]), (cx + dx - h, P["row_y"])])
    # 横线以下中间一道短的竖的：从横线通到袋底（袋底是收拢的，两边留成两个宽格）
    cords.polygon([(cx - h, P["row_y"]), (cx + h, P["row_y"]), (cx + h, P["bottom"] - 2.0), (cx - h, P["bottom"] - 2.0)])
    y = P["row_y"]                                                 # 一道横的：两头插进袋子的左右边框
    cords.capsule((cx - P["row_half"], y), (cx + P["row_half"], y), P["cord"])
    cords.soften(0.6)

    out = doodle.Mask(W, H)
    out.fill = ImageChops.subtract(body.fill, holes.fill)
    out.fill = ImageChops.lighter(out.fill, cords.fill)
    return out.alpha()


def render(P=None):
    return doodle.place(net(P), common.CANVAS, doodle.orig_box(REL), hand=HAND)


if __name__ == "__main__":
    imgs = [(NAME, render())]
    if len(sys.argv) > 1:      # 给了预览图的路径才出预览图
        common.preview(sys.argv[1], [("捞网", REL, imgs[0][1])])
    if len(sys.argv) > 2:
        common.save(imgs, sys.argv[2])
    else:
        # 不给输出目录就写进工程（别的画图脚本都是这样）
        common.save(imgs, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "sprites", "upgrades"))

#!/usr/bin/env python3
"""油纸伞（原来是伞的那张图）：upgrade-umbrella.png。

和原版的伞一样：156×136 的画布，图形落在同一块范围里（x 25..129，y 15..120，106×106），纯白、实心，
细节用挖空的洞表示；游戏在运行时把颜色乘上去。

画的是一把撑开的油纸伞，正对着看：
  伞面：上边是一段圆弧，下边是一圈圆头的花瓣边——每根伞骨的头把伞面顶出去一个圆鼓鼓的花瓣尖，骨头和骨头之间收进去一点；
  伞骨：伞面里挖出来的两道缝，左右各一道斜的，从花瓣边的里头指向伞顶，两头都不出头，伞面始终是一整块；
  伞顶：一个小葫芦形的伞头（下面一个大球、上面一个小球）；
  伞柄：一根直的竹柄，竖着往下伸，上面挖两道短槽当竹节。
伞骨的缝只画两道、而且不画到伞顶：放射状的缝越靠近伞顶挨得越近，画全了、画到头，按游戏里最小的 zoom
缩下去它们会粘成一片（正中间那道竖缝也试过，它把伞面正中劈开，原版的伞面是一整大块）。花瓣边一共七个尖，也就等于画出了七根伞骨的头。
原版的伞是斜着拿的，这里正着画：伞面、伞骨、伞柄一眼都看得全。

用法: python3 -I paper_umbrella.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 upgrade-umbrella.png。
"""
import importlib.util
import math

import numpy as np
from PIL import Image
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("a2_common", os.path.join(HERE, "a2_common.py"))
common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(common)
doodle = common.doodle

REL = common.DIR + "upgrade-umbrella.png"
NAME = "upgrade-umbrella.png"
W, H = 106, 106              # 设计范围 = 原版伞的图形范围（宽、高）

DEFAULT = dict(
    y_top=6.0,            # 伞面的弧顶在 y 多少（上面是伞头）
    y_edge=58.0,          # 伞面的边在 y 多少（花瓣尖和花瓣之间的凹点都在这一行附近）
    petal=5,              # 花瓣边有几个尖（也就是几根伞骨的头）；两头各半个尖
    lobe=4.5,             # 每个花瓣尖往下鼓出多少（浅浅的波浪，大了缩到游戏里像蘑菇）
    rib_w=9.0,            # 伞骨的缝多粗
    ribs=(),              # 哪几个凹点（从左数，0 到 petal-1）往里画伞骨的缝。斜过来以后这些缝挤在一起像蘑菇上的点，所以不画了
    rib_len=(),           # 这几道缝各有多长
    rib_in=7.0,           # 缝的外头离花瓣边的凹点多远
    handle_w=21.0,        # 伞柄多粗（和原版伞柄差不多粗）
    nodes=(),             # 伞柄上的竹节：伞柄改成带钩的以后不画了（缝多了细碎，远看也看不见）
    node_w=8.0,           # 竹节的槽多粗
    node_skin=4.5,        # 竹节的槽两头各留多少皮
)


def rib_dir(P, k):
    """第 k 个凹点的位置，和从它指向伞顶的单位向量"""
    x = W / P["petal"] * (k + 0.5)
    tx, ty = W / 2, P["y_top"]
    d = math.hypot(tx - x, P["y_edge"] - ty)
    return (x, P["y_edge"]), ((tx - x) / d, (ty - P["y_edge"]) / d)


def umbrella(P=None):
    """返回高分辨率的透明度图（设计范围 106×106 的 K 倍）"""
    P = dict(DEFAULT, **(P or {}))
    w, h = W / 2, H / 2
    sag = P["y_edge"] - P["y_top"]                 # 伞面上边那段圆弧的矢高
    dy = (w * w - sag * sag) / (2 * sag)           # 圆心在伞面的边以下 dy 处
    rad = dy + sag
    a_end = math.degrees(math.atan2(P["y_edge"] - (P["y_edge"] + dy), w))   # 圆弧右端的角度（负的）

    body = doodle.Mask(W, H)
    pts = []
    for i in range(41):                            # 上边的圆弧：从右端逆时针到左端
        a = math.radians(a_end + (180 - 2 * a_end) * i / 40)
        pts.append((w + rad * math.cos(a), P["y_edge"] + dy - rad * math.sin(a)))
    n, lobe = P["petal"], P["lobe"]
    for i in range(n * 16 + 1):                    # 下边的花瓣边：从左端经过正下方回到右端
        t = n * i / (n * 16)
        f = 0.5 + 0.5 * math.cos(2 * math.pi * t)  # 每个尖上鼓出到 lobe，尖和尖之间收回到 0
        pts.append((W * i / (n * 16), P["y_edge"] + lobe * f))
    body.polygon(pts)                              # 伞面
    top = P["y_top"]
    body.capsule((w, top + 4), (w, top - 3), 7.0)  # 伞头的脖子
    body.add(0, 0, _ball(w, top - 4.0, 11.0))      # 葫芦的下面一个球
    body.add(0, 0, _ball(w, top - 12.5, 7.0))      # 葫芦的上面一个小球
    hw = P["handle_w"]
    # 伞柄：上面一段直的，到底下弯一个小钩（原版的伞柄就是带钩的）
    body.path([(w, P["y_edge"]), (w, H - 26.0), (w + 3.0, H - hw / 2 - 3.0), (w + 22.0, H - hw / 2 - 1.0)], hw)
    body.soften(1.5)

    holes = doodle.Mask(W, H)
    half = P["rib_w"] / 2
    for k, length in zip(P["ribs"], P["rib_len"]):  # 伞骨的缝：从凹点往里 rib_in 起，长 length（两头是圆的，端点各往里收半个缝宽）
        (x, y), (ux, uy) = rib_dir(P, k)
        a = P["rib_in"] + half
        holes.capsule((x + ux * a, y + uy * a), (x + ux * (P["rib_in"] + length - half), y + uy * (P["rib_in"] + length - half)), P["rib_w"])
    skin = P["node_skin"]
    for y in P["nodes"]:                           # 伞柄上的竹节
        holes.capsule((w - P["handle_w"] / 2 + skin + P["node_w"] / 2, y), (w + P["handle_w"] / 2 - skin - P["node_w"] / 2, y), P["node_w"])
    holes.soften(0.8)

    out = doodle.Mask(W, H)
    out.fill = body.fill.copy()
    out.cut(holes)
    return out.alpha()


def _ball(cx, cy, d):
    """一个圆心在 (cx, cy)、直径 d 的圆球（Mask 和设计范围一样大，用 add(0, 0, …) 并到别的 Mask 里）"""
    b = doodle.Mask(W, H)
    b.ellipse((cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2))
    return b


def render(P=None):
    # 整把伞歪 24 度（原版的伞就是斜打的，立得笔直像表情符号）：伞面偏左上，伞柄伸向右下，末端是朝上翘的钩
    art = Image.fromarray(np.asarray(umbrella(P)), "L").rotate(24, resample=Image.BICUBIC, expand=True)
    art = art.point(lambda v: 255 if v >= 128 else 0)
    return doodle.place(art, common.CANVAS, doodle.orig_box(REL), hand=dict(seed=616, wobble=0.014, thick=0.010, tilt=2.0))


if __name__ == "__main__":
    imgs = [(NAME, render())]
    if len(sys.argv) > 1:      # 给了预览图的路径才出预览图
        common.preview(sys.argv[1], [("油纸伞", REL, imgs[0][1])])
    if len(sys.argv) > 2:
        common.save(imgs, sys.argv[2])
    else:
        # 不给输出目录就写进工程（别的画图脚本都是这样）
        common.save(imgs, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "sprites", "upgrades"))

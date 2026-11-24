#!/usr/bin/env python3
"""渔娘的技能图标：原版是磁铁 → 捞网。

画布 311×316，图形落在原版的范围里（x 76..233， y 69..247），纯白实心。
正对着网口看一支抄网：上面是圆的网口，底下是垂下来的网兜，整个网头是一整片菱形的网
（网线是实心的，网眼挖空），一根粗柄从网口的右上沿斜着伸出去。
游戏里这个图标只有 50×57 屏幕像素（HUD 的技能按钮，zoom 0.32）：网线 5 个屏幕像素粗，
每个网眼 10 个屏幕像素宽——网眼够大，缩图以后还是一格一格的网，不是一块实心的板子。

用法: python3 -I scoop_net.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/magnet.png
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/magnet.png"
CANVAS = (311, 316)
W, H = 157, 178                 # 设计范围 = 原版的图形范围

CX, CY, R = 64.0, 58.0, 46.0    # 网口（圆）的圆心和半径
HEAD = [                         # 网头的轮廓：上面是圆的网口，底下垂着一个网兜
    (CX, CY - R), (CX + R * 0.7, CY - R * 0.7), (CX + R, CY), (CX + R + 4, CY + 40), (CX + R - 6, CY + 80),
    (CX + 20, CY + 108), (CX - 16, CY + 112), (CX - R + 8, CY + 86), (CX - R - 2, CY + 44), (CX - R, CY), (CX - R * 0.7, CY - R * 0.7),
]
INSET = 0.80                    # 网区：把轮廓朝里缩到八成，留下一圈边
PITCH = 65.0                    # 网线的间距（相邻两条同向斜线的横向距离）
LINE_W = 16.0                   # 网线的粗细（≈ 5 屏幕像素）
NODE = (CX, 96.0)               # 网格的基准点：一列网眼的中心线落在网头的中轴上，网格左右对称
HANDLE = ((96.0, 32.0), (146.0, 7.0), 17.0)   # 粗柄：从网口的右上沿伸出去；起点的圆心、终点的圆心、粗细
MIN_EYE = 330.0                  # 一个网眼至少要有多少个纹理像素的面积（完整的菱形眼大约 540），不到的就不挖


def net_head():
    """一整片菱形的网：轮廓里去掉一圈边就是网区，网区里把网眼挖掉，留下的就是两向交叉的网线"""
    d = doodle.Mask(W, H)
    d.shape(HEAD)
    zone = doodle.Mask(W, H)
    zone.shape([(CX + (x - CX) * INSET, CY + (y - CY) * INSET) for x, y in HEAD])   # 朝里缩
    zone.soften(1.5)
    lines = doodle.Mask(W, H)
    half = PITCH / 2                                   # 让一列网眼正好落在中轴上
    for k in range(-6, 7):
        xk = NODE[0] + half + k * PITCH
        lines.capsule((xk - 130, NODE[1] + 130), (xk + 130, NODE[1] - 130), LINE_W)   # 一个方向的一排斜线
        lines.capsule((xk - 130, NODE[1] - 130), (xk + 130, NODE[1] + 130), LINE_W)   # 另一个方向的
    eyes = doodle.Mask(W, H)
    eyes.fill = ImageChops.subtract(zone.fill, lines.fill)           # 网眼里线没经过的地方
    # 网区边角上被切碎的小网眼不要：缩图以后它们成了时隐时现的小点。只挖够大的网眼
    solid = np.asarray(eyes.fill) > 127
    big = np.zeros_like(solid)
    for comp in doodle._components(solid):
        if int(comp.sum()) >= MIN_EYE * doodle.K * doodle.K:
            big |= comp
    eyes.fill = Image.fromarray((big * 255).astype("uint8"), "L")
    eyes.soften(0.8)
    d.cut(eyes)
    return d


def draw():
    d = net_head()
    d.capsule(HANDLE[0], HANDLE[1], HANDLE[2])                       # 柄
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

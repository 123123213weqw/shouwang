#!/usr/bin/env python3
"""终点传送门（原版是漩涡）→ 水车：圆轮、辐条、轮缘上一圈刮板。

画布 156×136，图形落在原版的范围里（x 12..143，y 14..122），纯白实心，细节靠挖空的洞。
游戏里这张图会绕着自己的轴不停地转（激活时每秒半圈），所以画成旋转对称的：轮心正落在画布中心，
任意转角看起来都一样。
原版的范围是 131 宽 × 108 高；水车是个正圆的轮子，直径按高度算（108），左右各留一点空。

轮子的画法照简笔画的水车来：外圈 6 片宽宽的刮板（不是细密的齿；板是斜着装的，像筒车斜着拨水的叶片——
直着装的方齿实拍一眼就是齿轮）、一圈轮缘、里面一个十字的辐条、当中一个带轴孔的轮毂。
整体是一块，轮子里挖 4 个洞、轴心挖 1 个洞。
游戏里最小的情况 zoom 约 0.36（第 12 关最远一排），轮子在屏幕上只有 39 像素宽：
轮缘 4 个屏幕像素粗、辐条 5 个、刮板 5×8、轴孔 5、轮子里的洞 8×9。

用法: python3 -I waterwheel.py [输出目录]      不给输出目录就写在工程的 assets/sprites/upgrades/portal.png
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

REL = "assets/sprites/upgrades/portal.png"
CANVAS = (156, 136)
S = 108                      # 设计范围（正方形），轮心在正中
C = S / 2

# 各部分的粗细（纹理像素）。游戏里最小的情况 zoom 约 0.36，1 纹理像素 ≈ 0.36 屏幕像素
PAD_N = 6                    # 刮板的片数
PAD_LEN = 15.0               # 刮板伸出轮缘的长度  ≈ 5.4 屏幕像素
PAD_W = 23.0                 # 刮板的宽度          ≈ 8.3 屏幕像素
RIM_W = 11.0                 # 轮缘的粗细          ≈ 4 屏幕像素
SPOKE_N = 4                  # 辐条的根数
SPOKE_W = 14.0               # 辐条的粗细          ≈ 5 屏幕像素
HUB_R = 16.0                 # 轮毂的半径          ≈ 5.8 屏幕像素
AXLE_R = 7.0                 # 轴孔的半径          ≈ 5 屏幕像素粗的洞
TILT = 12.0                  # 刮板斜着装的角度：像筒车的叶片斜着拨水。直着装的方齿实拍一眼就是齿轮，斜一点才是叶轮


def wheel():
    """水车的轮子，画在以轮心为中心、S×S 的范围里"""
    r_out = C                                   # 刮板的外端
    r_rim = r_out - PAD_LEN                     # 轮缘的外沿
    r_in = r_rim - RIM_W                        # 轮缘的内沿（轮子里面挖空的地方从这里开始）
    d = doodle.Mask(S, S)
    d.ellipse((C - r_rim, C - r_rim, C + r_rim, C + r_rim))            # 轮缘
    # 一圈刮板：从轮缘外沿伸出去的短板，外端是平的；板是斜着装的——从轮缘往外越来越斜
    for i in range(PAD_N):
        a = i * 2 * math.pi / PAD_N                                    # 左右各正对一片，轮子在横向占得宽一点
        v = (-math.sin(a), math.cos(a))
        pts = []
        for r, s in ((r_rim - 2, -1), (r_out, -1), (r_out, 1), (r_rim - 2, 1)):
            t = math.radians(TILT) * (r - r_rim) / PAD_LEN             # 斜着装的角度
            pts.append((C + math.cos(a + t) * r + v[0] * PAD_W / 2 * s, C + math.sin(a + t) * r + v[1] * PAD_W / 2 * s))
        d.polygon(pts)
    d.soften(1.6)

    # 轮子里面的洞：轮缘以内整块挖掉，只留下辐条和轮毂
    inner = doodle.Mask(S, S)
    inner.ellipse((C - r_in, C - r_in, C + r_in, C + r_in))
    keep = doodle.Mask(S, S)
    for i in range(SPOKE_N):
        a = (i + 0.5) * 2 * math.pi / SPOKE_N                          # 辐条从两片刮板之间出头（斜着的十字）
        keep.capsule((C, C), (C + math.cos(a) * (r_in + 4), C + math.sin(a) * (r_in + 4)), SPOKE_W)
    keep.ellipse((C - HUB_R, C - HUB_R, C + HUB_R, C + HUB_R))          # 轮毂
    keep.soften(0.8)
    inner.cut(keep)
    d.cut(inner)
    # 轮毂当中的轴孔
    axle = doodle.Mask(S, S)
    axle.ellipse((C - AXLE_R, C - AXLE_R, C + AXLE_R, C + AXLE_R))
    axle.soften(0.5)
    d.cut(axle)
    return d.alpha()


def build():
    return doodle.place(wheel(), CANVAS, doodle.orig_box(REL))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

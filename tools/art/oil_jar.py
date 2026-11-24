#!/usr/bin/env python3
"""灯油罐：原版的心（heart.png）换成一只带提梁的圆罐子，有罐口。棋盘上能收的那样东西（加了命的那一种）。

和原版的心一样：156×136 的画布，图形落在同一块范围里（x 30..133，y 37..122），纯白、实心，
不描边、不画明暗，细节用挖空的洞表示。位置、大小、缩放、染色都不变。

画法（坐标是 103×85 的设计范围，y 向下；从罐口到底是一笔描出来的轮廓）：
  提梁   罐口上头半个圆环，线宽 13；
  罐口   口沿是一条横向的圆角短板，底下接着短短的颈；
  罐身   从颈往外滑出去的圆肩、鼓起来的肚子、圆底的肚。
整张图是连在一起的一块，只有提梁围出来的那一个洞（28 宽、14 高，最小的镜头下 4.3 个屏幕像素；
原版的心没有洞，原版的鱼有一个 11 像素的眼睛）。这张图在游戏里最小的时候是 28×22 个屏幕像素（第 12 关最远一排，镜头拉到 0.29），
而且落在最远一排时下半截会被前排的格子挡住，看得见的是提梁和罐口——所以提梁做得粗而圆，一眼就是"带提手的罐子"。提梁和口沿是这张图里最细的地方，自检的细碎程度
（33%，原版的心是一整块，只有 23%）已经贴近上限，所以口沿和颈没法再往上加高：试过把口沿加宽到 58、颈加到 6，就超了。

这张图还是"丢心"动画用的图（主角踩空一步，头顶上飘走一个染了颜色的小罐子）：油洒了一罐。

用法: python3 -I oil_jar.py [预览图的输出路径]
  总是把 heart.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图。
只依赖 Pillow。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/heart.png"
W, H = 103, 85                                           # 设计范围 = 原版图形的范围
ZOOM_MIN = 0.31                                          # 最小的镜头：一个纹理像素等于几个屏幕像素（第 12 关最远一排）


def _load(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle, kit):
    """返回高分辨率的透明度图（103×85 的设计范围，已经按 8 倍画好）"""
    cx = W / 2.0                                         # 51.5
    t, R = 13, 27                                        # 提梁的线宽、外半径（拱顶贴着图形范围的顶，里面的洞 28 宽、14 高）
    lift = R                                             # 提梁拱脚的高度
    ly = lift - 1                                        # 口沿的顶
    lw, lh = 56, 8                                       # 口沿的宽、高（口沿比颈宽出一圈，是罐口上翻的沿）
    nw, nh = 32, 2                                       # 颈的宽、高
    bw = 103                                             # 罐身最宽的地方（把宽度撑满）
    y0 = ly + lh                                         # 颈的起点
    b = doodle.Mask(W, H)
    # ---- 罐口、颈、肩、肚子、底：一条轮廓
    b.shape([
        (cx - lw / 2, ly), (cx + lw / 2, ly),
        (cx + lw / 2, ly + lh),
        (cx + nw / 2, y0 + 1.5), (cx + nw / 2, y0 + nh),
        (cx + bw * 0.42, y0 + nh + 5),
        (cx + bw / 2, y0 + nh + (H - y0 - nh) * 0.6),
        (cx + bw * 0.38, H - 4), (cx, H),
        (cx - bw * 0.38, H - 4),
        (cx - bw / 2, y0 + nh + (H - y0 - nh) * 0.6),
        (cx - bw * 0.42, y0 + nh + 5),
        (cx - nw / 2, y0 + nh), (cx - nw / 2, y0 + 1.5),
        (cx - lw / 2, ly + lh),
    ])
    # ---- 提梁：半个圆环，拱脚落在口沿上
    kit.arc_handle(b, cx, lift, R, t, 5)
    b.soften(1.1)                                        # 把接缝抹圆
    return b.alpha()


def main():
    doodle, kit = _load("doodle"), _load("a1_kit")
    box = doodle.orig_box(REL)
    img = doodle.place(build(doodle, kit), doodle.orig_size(REL), box)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    ok = doodle.check(out, REL, zoom=ZOOM_MIN, kind="3d", name=REL)
    if len(sys.argv) > 1:
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=(ZOOM_MIN, 0.5), title="灯油罐"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

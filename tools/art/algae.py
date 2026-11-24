#!/usr/bin/env python3
"""格子上的装饰一（assets/sprites/algae.png）：一片荷叶——圆圆的叶子，带一段叶柄和叶脉。

原版是三根弯弯的水藻（256×256 的画布，图形在 x 64..189、y 88..242）。新图是同一块范围里的一片荷叶
（从斜上方看的一片圆叶）：
  - 叶片：接近正圆，顶在范围的最上边，左右撑满；
  - 莲脐：叶心挖一个小圆洞（荷叶正中间叶柄着生的那个凹点），稍微偏离叶心一点；
  - 叶脉：从莲脐四周放射出去、快到叶缘就停下的六条细线，正下方留空（叶柄从那里长出来）；
  - 叶柄：从叶子底下一直伸到范围的最下边（游戏里正好立在格子面上），下端是原版的根的位置。

叶脉是半透明的细线（透明度 75%，原版 tile.png 环里那层 20% 的白就是这种手法），不是挖空的。
这是这一组里唯一用了半透明细节的地方，原因写在这里，方便以后拿主意：
  这个装饰是一张竖着的画片，被俯视的镜头压得很扁，竖直方向一个纹理像素只有 0.16 到 0.26 个屏幕像素。
  挖空的线要么够粗（12 像素以上），近处远处的格子上满屏都是一个个船舵轮子（实拍试过，否掉了）；
  要么细到 7 像素上下，远看会闪。半透明的线缩小以后是连续的淡线，不会断也不会闪，
  叶子始终是一整块实心的圆盘，叶脉只是叶面上一条条略透的线——实拍十个相位都稳定。
把 VEIN_MODE 改成 "cut" 就换回挖空的画法（VEIN_W 要加到 12 以上，不然近处远处的格子会散开）。
试过、没有用的：叶缘的荷叶边（更像伞）、叶脉分叉（远看像蜘蛛网）、四角内凹的海棠形叶（成了小刺）。

用法: python3 -I algae.py [预览图的输出路径]
  不带参数只把图写到工程里并自检；带了参数再出一张对比图（原版 | 新图 | 叠在一起）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

from PIL import ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL = "assets/sprites/algae.png"
ZOOM_MIN = 0.24                            # 最小的情况：第 12 关最远一排（长夜第 16 更是 0.28）

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

CANVAS = doodle.orig_size(REL)             # (256, 256)
BOX = doodle.orig_box(REL)                 # 原版图形的范围 (64, 88, 126, 155)
W, H = BOX[2], BOX[3]                      # 设计范围：126 宽、155 高

CX = W / 2                                 # 叶心的横坐标（范围的正中，原版三根水藻也是居中的）
LEAF_R = 56.0                              # 叶片的半径：叶子顶在范围的最上边，底下留一段看得见的叶柄
LEAF_CY = 2.0 + LEAF_R                     # 叶心的纵坐标
NAVEL = 18.0                               # 莲脐（叶心的圆洞）的直径
STEM_W = 16.0                              # 叶柄的宽度（原版水藻每根约 20 像素宽）

VEIN_MODE = "tint"                         # 叶脉的画法："cut" 挖空 / "tint" 半透明
VEINS = 8                                  # 叶脉按这个条数均匀分布一圈（错开半个间隔），正下方靠近叶柄的两条不留
VEIN_W = 8.0                               # 叶脉的宽度
VEIN_ALPHA = 191                           # 半透明画法里叶脉的透明度（191 是 75%：游戏里叶脉的亮度大约是叶面的四成）
VEIN_RIM = 3.0                             # 叶脉离叶缘留这么宽
NAVEL_OFF = (-6.0, 6.0)                    # 莲脐（叶脉的放射中心）偏离叶心多少：往左下偏一点。对称的圆盘像轮子、像扇子，偏一点才像一片自然的叶子
FORK = -1.0                                # 主脉走到多长开始分叉（0 到 1）。试过 0.52（每条分两叉）：近处很像荷叶的叶脉，但远处十二个线头密得像蜘蛛网，所以不分叉
FORK_ANGLE = 20.0                          # 两叉各偏离主脉多少度


def leaf_outline():
    """叶片的轮廓锚点：接近正圆，带一点手绘的不圆（半径起伏不到两个像素）"""
    pts = []
    n = 16
    for i in range(n):
        a = -math.pi / 2 + 2 * math.pi * i / n
        r = LEAF_R * (1 + 0.014 * math.sin(3 * a + 0.9) + 0.009 * math.sin(5 * a + 2.4))
        pts.append((CX + r * math.cos(a), LEAF_CY + r * math.sin(a)))
    return pts


def navel_center():
    """莲脐的位置，叶脉都从这里放射出去"""
    return CX + NAVEL_OFF[0], LEAF_CY + NAVEL_OFF[1]


def vein_mask():
    """叶脉的形状：从莲脐边上出发、到叶缘内侧停下的圆头细线，一圈均匀分布，正下方（叶柄的方向）留空"""
    v = doodle.Mask(W, H)
    nx, ny = navel_center()
    ex, ey = nx - CX, ny - LEAF_CY             # 莲脐相对叶心的偏移
    for i in range(VEINS):
        ang = math.radians(-90 + 360.0 * i / VEINS + 180.0 / VEINS)
        if abs((math.degrees(ang) - 90 + 180) % 360 - 180) < 30.0:      # 正下方那两条离叶柄太近，不留
            continue
        c, s = math.cos(ang), math.sin(ang)
        # 这个方向上从莲脐走到叶缘有多远：叶子是圆心在叶心的圆，莲脐偏了心，所以每条叶脉的长短都不一样
        reach = -(ex * c + ey * s) + math.sqrt(max(LEAF_R ** 2 - ex * ex - ey * ey + (ex * c + ey * s) ** 2, 1.0))
        ox, oy = nx + (NAVEL / 2 + 0.5) * c, ny + (NAVEL / 2 + 0.5) * s          # 出发点：莲脐的边上
        if FORK <= 0.0:
            v.capsule((ox, oy), (nx + (reach - VEIN_RIM) * c, ny + (reach - VEIN_RIM) * s), VEIN_W)
        else:
            # 荷叶的叶脉是分叉的：一条主脉走到一半，分成两叉伸到叶缘
            mx, my = nx + reach * FORK * c, ny + reach * FORK * s                 # 分叉点
            v.capsule((ox, oy), (mx, my), VEIN_W)
            for turn in (FORK_ANGLE, -FORK_ANGLE):
                b = ang + math.radians(turn)
                fb, sb = math.cos(b), math.sin(b)
                rb = -(ex * fb + ey * sb) + math.sqrt(max(LEAF_R ** 2 - ex * ex - ey * ey + (ex * fb + ey * sb) ** 2, 1.0))
                v.capsule((mx, my), (nx + (rb - VEIN_RIM) * fb, ny + (rb - VEIN_RIM) * sb), VEIN_W * 0.9)
    v.soften(0.3)
    return v


def build():
    """返回设计范围里的透明度图（高分辨率）：实心部分是 255，半透明的叶脉是 VEIN_ALPHA，其余是 0"""
    m = doodle.Mask(W, H)
    m.shape(leaf_outline())
    stem = doodle.Mask(W, H)
    stem.capsule((CX + 1, LEAF_CY + 8), (CX, H - STEM_W / 2 - 0.5), STEM_W)
    m.union(stem)
    m.soften(0.8)                           # 把叶柄和叶子接缝的地方抹圆

    hole = doodle.Mask(W, H)
    nx, ny = navel_center()
    hole.ellipse((nx - NAVEL / 2, ny - NAVEL / 2, nx + NAVEL / 2, ny + NAVEL / 2))
    hole.soften(0.4)
    vein = vein_mask()
    if VEIN_MODE == "cut":
        hole.union(vein)                    # 叶脉挖空：和莲脐一起挖掉
    base = ImageChops.subtract(m.alpha(), hole.alpha())
    if VEIN_MODE == "tint":
        base = ImageChops.lighter(ImageChops.subtract(base, vein.alpha()),
                                  vein.alpha().point(lambda v: v * VEIN_ALPHA // 255))
    return base


def render(alpha):
    """把设计范围里的图等比缩进原版图形的范围、放到 256×256 的画布上（纯白）"""
    return doodle.place(alpha, CANVAS, BOX)


if __name__ == "__main__":
    img = render(build())
    img.save(os.path.join(ROOT, REL))
    print("已写出", REL, "（叶脉：%s）" % ("挖空" if VEIN_MODE == "cut" else "半透明"))
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("algae  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL), REL)], cell=300)
        print("预览图:", sys.argv[1])
    doodle.check(os.path.join(ROOT, REL), REL, zoom=ZOOM_MIN, kind="3d")

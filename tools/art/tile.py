#!/usr/bin/env python3
"""格子顶面（assets/sprites/tile.png）：水里一块方方正正的石头墩（江南水乡的汀步、河埠头）。

和原版一样：160×160 的画布，图形落在同一块范围里（x 19..141，y 17..138），纯白、实心。
原版是一个圆角方环，环里铺着一层 20% 透明的白（alpha = 51），环里的孔是圆角方形。新图：
  - 外轮廓的范围一点不变（还是那个带一点手绘起伏的圆角方）；
  - 环里那层 20% 的透明原样保留（格子的明暗靠它）；
  - 只把环里的孔从圆角方形改成正圆："外方内圆"，石墩的顶面被磨成一个圆圆的凹面
    （井栏石、河埠头的缆船石都是这个样子），也和面板边框上的月洞弧是同一种味道。
试过"海棠形"（四条边鼓出、四角收进）和"四角内凹的四瓣"：前者缩成五十来个像素宽时只是个
胖圆角方，后者四角的小凹要么看不出、要么成了小刺，都不如正圆干净，所以没有用。
没有挖任何小洞、没有加任何小块：格子是满屏平铺的，一点碎细节都会花。

用法: python3 -I tile.py [预览图的输出路径]
  不带参数只把图写到工程里并自检；带了参数再出一张预览图（原版 | 新图 | 叠在一起，
  下面是原版和新图各按游戏里的大小缩小后、三乘三平铺的样子）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL = "assets/sprites/tile.png"
CANVAS = (160, 160)
INNER_ALPHA = 51                           # 环里那层 20% 的透明（原版就是 51）
ZOOM_MIN = 0.32                            # 最小的情况：第 12 关最远一排，整个格子约 50 像素宽

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

BOX = doodle.orig_box(REL)                 # 原版图形的范围 (19, 17, 123, 122)
X0, Y0, X1, Y1 = BOX[0], BOX[1], BOX[0] + BOX[2], BOX[1] + BOX[3]   # 外轮廓的左上、右下（右下不含）
INSET = 0.45                               # 四边往里收这么多：缩回原尺寸时边缘的抗锯齿正好补上，范围和原版重合
WOBBLE = 1.4                               # 外轮廓四条边中段的手绘起伏（像素）
HAND = 0.018                               # 圆孔的不圆程度（半径的起伏比例，不到一个像素）

IX0, IY0, IX1, IY1 = 32.5, 32.5, 123.5, 123.5   # 原版的内孔：x 32..124，y 32..124。圆孔的外接方就是它，环的宽度不变


def rounded_square(x0, y0, x1, y1, radii, wobble=0.0):
    """圆角方的轮廓锚点（顺时针一圈）。radii 是四个角的半径（左上、右上、右下、左下）。
    wobble > 0 时四条边的中段带一点点手绘的起伏（幅度是 wobble 个像素）"""
    rt, rr, rb, rl = radii

    def corner(px, py, r, a0):             # 以 (px, py) 为圆心、半径 r，从角 a0 起顺时针（屏幕坐标，y 向下）转 90 度，5 个点
        return [(px + r * math.cos(a0 + math.pi / 2 * i / 4), py + r * math.sin(a0 + math.pi / 2 * i / 4)) for i in range(5)]

    pts = []
    pts += corner(x0 + rl, y1 - rl, rl, math.pi / 2)               # 左下角：从下边转到左边
    # 四条边的中段：只往里起伏、不往外鼓，所以外轮廓永远不会超出原版的范围
    pts += [(x0 + 0.35 * wobble, y0 + (y1 - y0) * 0.62),
            (x0 + 0.9 * wobble, y0 + (y1 - y0) * 0.36)]            # 左边中段
    pts += corner(x0 + rt, y0 + rt, rt, math.pi)                   # 左上角：从左边转到上边
    pts += [(x0 + (x1 - x0) * 0.34, y0 + 0.3 * wobble),
            (x0 + (x1 - x0) * 0.62, y0 + 1.0 * wobble)]            # 上边中段
    pts += corner(x1 - rr, y0 + rr, rr, -math.pi / 2)              # 右上角：从上边转到右边
    pts += [(x1 - 0.4 * wobble, y0 + (y1 - y0) * 0.40),
            (x1 - 0.95 * wobble, y0 + (y1 - y0) * 0.68)]           # 右边中段
    pts += corner(x1 - rb, y1 - rb, rb, 0.0)                       # 右下角：从右边转到下边
    pts += [(x0 + (x1 - x0) * 0.60, y1 - 0.25 * wobble),
            (x0 + (x1 - x0) * 0.30, y1 - 0.9 * wobble)]            # 下边中段
    return pts


def circle(cx, cy, r, n=20, hand=HAND):
    """圆的锚点（顺时针一圈）。hand 是手绘的不圆程度：半径随角度起伏 hand × r（不到一个像素）"""
    def rad(a):
        return r * (1 + hand * math.sin(3 * a + 0.7) + hand * 0.6 * math.sin(5 * a + 2.1))
    return [(cx + rad(a) * math.cos(a), cy + rad(a) * math.sin(a))
            for a in [-math.pi / 2 + 2 * math.pi * i / n for i in range(n)]]


def build():
    """返回高分辨率的透明度图：环是 255，环里那层是 51（20%），其余是 0"""
    # 外轮廓带一点手绘的起伏（原版也是手画的：上缘上下差三四个像素），圆也略有一点不圆
    outer = rounded_square(X0 + INSET, Y0 + INSET, X1 - INSET, Y1 - INSET, (23.0, 26.0, 22.5, 25.0), wobble=WOBBLE)
    inner = circle((IX0 + IX1) / 2, (IY0 + IY1) / 2, (IX1 - IX0) / 2, hand=HAND)

    ring = doodle.Mask(CANVAS[0], CANVAS[1])
    ring.shape(outer)
    hole = doodle.Mask(CANVAS[0], CANVAS[1])
    hole.shape(inner)
    ring.cut(hole)                       # 环 = 外轮廓减去圆孔
    # 环过一遍手绘化（doodle.handdraw_inplace）：原版的环是马克笔手画的，边的粗细沿着轮廓在变。
    # 只做线抖和粗细变化，位置和大小不变
    ring_a = doodle.handdraw_inplace(ring.alpha(), seed=317, wobble=0.012, thick=0.016, grain=0.003)

    fill = doodle.Mask(CANVAS[0], CANVAS[1])
    # 环里那层：比孔大一圈（半径多 3 个像素）。环的里沿手绘化以后会离原来的圆边两三个像素，
    # 填充大一圈才能保证始终压在环的下面，不会露出细缝（多出来的那部分在环下面，看不见）
    fill.shape(circle((IX0 + IX1) / 2, (IY0 + IY1) / 2, (IX1 - IX0) / 2 + 3.0, hand=HAND))
    return ImageChops.lighter(ring_a, fill.alpha().point(lambda v: v * INNER_ALPHA // 255))


def render(alpha):
    """高分辨率的透明度图 → 160×160 的 RGBA 图（纯白）"""
    return doodle.full(alpha, CANVAS)


def game_preview(img, zoom, color, floor, tiles=3, squash=0.62):
    """按游戏里的样子粗略模拟：缩到 zoom 倍，环用关卡的颜色，环里露出下面压暗的石面
    （着色器把透明度立方，所以 20% 的那层在游戏里几乎是全透明的）；格子被俯视的镜头压扁，
    竖直方向按 squash 压；平铺成 tiles × tiles"""
    w, h = max(1, round(img.width * zoom)), max(1, round(img.height * zoom))
    a = img.split()[3].resize((w, h), Image.LANCZOS).point(lambda v: int(255 * (v / 255.0) ** 3))
    a = a.resize((w, max(1, round(h * squash))), Image.BILINEAR)
    w, h = a.size
    tile = Image.new("RGB", (w, h), floor)
    tile.paste(Image.new("RGB", (w, h), color), (0, 0), a)
    sheet = Image.new("RGB", (w * tiles + 2 * tiles, h * tiles + 2 * tiles), floor)
    for j in range(tiles):
        for i in range(tiles):
            sheet.paste(tile, (i * (w + 2), j * (h + 2)))
    return sheet


def preview(path, img):
    """预览图：上面是 doodle 的对比图（原版 | 新图 | 叠在一起），下面是原版和新图在近处（0.70）、远处（0.32）平铺的样子"""
    tmp = path + ".sheet.png"
    doodle.review_sheet(tmp, [("tile  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL), REL)], cell=300)
    sheet = Image.open(tmp).convert("RGB")
    os.remove(tmp)
    big = Image.new("RGB", (sheet.width, sheet.height + 240), (28, 34, 52))
    big.paste(sheet, (0, 0))
    x = 12
    for im in (i for i in (doodle.orig(REL), img) if i is not None):     # 原版的图不在手边（没设 SW_ORIG）就只放新图
        for z in (0.70, 0.32):
            t = game_preview(im, z, (170, 210, 195), (8, 24, 20))
            k = 2 if z < 0.5 else 1
            t = t.resize((t.width * k, t.height * k), Image.NEAREST)
            big.paste(t, (x, sheet.height + 12))
            x += t.width + 40
    big.save(path)


if __name__ == "__main__":
    img = render(build())
    img.save(os.path.join(ROOT, REL))
    print("已写出", REL)
    if len(sys.argv) > 1:
        preview(sys.argv[1], img)
        print("预览图:", sys.argv[1])
    doodle.check(os.path.join(ROOT, REL), REL, zoom=ZOOM_MIN, kind="3d")

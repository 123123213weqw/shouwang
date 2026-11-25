#!/usr/bin/env python3
"""斗笠：竹子编的雨帽，新加的道具（效果是"挡一次踩空"）。原版里没有对应的东西，所以这是一张新图：
拿同目录的铜钱（clover.png，原版是四叶草）当参照，画布和图形的范围都照它来。

156×136 的画布，图形落在铜钱那块范围里（x 27..124，y 21..124，97×103），纯白、实心，不描边、不画明暗。
位置、大小、缩放、染色都不变。图形是 97×66：宽度撑满了这个范围，高度只有它的六成五——斗笠本来就矮而宽，
和原版的鱼（101×62）、草鞋（118×76）是一个量级，不比别的道具大。所以自检里会有一句"图形比原版的小（高 65%）"，
那是因为参照的铜钱是撑满 97×103 的圆疙瘩，不是这张图画小了。

照着守夜人头上那顶斗笠（tools/art/watchman.py 的 hat()）的形来画——玩家一看主角的帽子就认得：
宽矮的圆锥、基本笔直的坡面、圆钝的帽尖、又平又宽的笠沿。（守夜人那顶的笠沿两头略往下垂；这里两头微微上翘，
单独放在棋盘上更像一顶帽子。）
坐标是帽子自己的：原点在帽檐的正中，y 向下，单位是纹理像素。
  帽顶  宽矮的圆锥（高约 42、底宽约 77），帽尖略偏左，顶上一个圆头；
  帽尖  圆头上再鼓起一个小圆顶（斗笠顶上收口的小疙瘩）；
  帽檐  比帽顶的底宽（整顶宽 93），两头各伸出一截、厚厚的小尖微微上翘；前沿往下弯（正面略带俯视，看得见帽檐的面），
        起伏不平、不对称，最低点偏左——不是正圆。
帽子不切开、不挖洞，全靠外形认（帽檐和帽顶之间那条细缝没有试实拍：留了缝，下面那条帽檐在最远的镜头下只剩
三四个像素宽，按规矩得靠连拍确认它不散，稳妥起见不留）。最后再过一遍手绘化（doodle.handdraw）：线抖一抖、
粗细变一变、整体略歪几度。

为什么只画帽子、下面什么都不挂（前三条都在服务器上实拍过，放大了看）：
  单独一顶帽子悬在半空，帽檐底下挂两根线当系带，放到棋盘上就是桌腿：一长一短是歪腿的桌子，歪戴帽子让绳子
  竖直下垂像会走路的帽子（这两样只在本机按游戏里的大小模拟过，没上服务器）；实拍里两根绳在远处像树干，一棋盘的斗笠成了小树林。
  帽檐下面加一个小圆顶（像扣在脑袋上）近处像扣着斗笠的脑袋，远处像蘑菇；再加两根绳就是水母。
  系带在帽子底下连成一个兜、帽檐和带子之间留一道弯缝，像一张笑嘴，整个外形也成了水滴形。
  帽顶画高（高是宽的三分之二）细碎程度的数字好看，但像竹笋/火苗。
  所以定成矮而宽的、干干净净的一顶帽子。

游戏里同一个面片在不同距离上的竖向比例不一样（第 12 关实拍量的）：第 1 关不变形，第 12 关最近一排压到 0.85，
最远一排拉长到 1.22。所以这张图按"矮而宽"画：最远一排（zoom 0.29）一个斗笠在画面上大约 28 像素宽。

用法: python3 -I hat.py [预览图的输出路径]
  总是把 hat.png 写到工程的 assets/sprites/upgrades/ 里并自检；给了路径就再出一张预览图。
只依赖 Pillow 和 numpy。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/hat.png"
REF = "assets/sprites/upgrades/clover.png"               # 当参照的原版图
ZOOM_MIN = 0.29                                          # 最小的镜头：一个纹理像素等于几个屏幕像素（第 12 关最远一排）
HAND = dict(seed=706, wobble=0.02, thick=0.022, tilt=2.5)   # 手绘化的力度（比默认的稍重一点，同食盒）

# 设计范围比图形大：帽子歪了、线往外鼓都不会被裁掉，最后由 doodle.place() 等比缩进参照的范围里
W, H = 130, 130
OX, OY = 65.0, 58.0                                      # 帽子自己的原点（帽檐正中）落在设计范围的哪里

P = dict(
    angle=4.0,          # 整顶帽子往右下歪几度
    reach=46.5,         # 帽檐两头离中心的距离（整顶宽 93）
    lip=8.0,            # 帽檐比帽顶的底多伸出多少
    tip=(-5.0, -8.0),   # 帽檐两头的小尖在 y 多少（负数是往上翘；左，右）。帽子往右下歪，所以右边多翘一点才两边看着一样
    upper=((-37.0, -1.5), (36.0, -1.5)),   # 帽檐上沿从两头的尖回到帽顶底边的中途过的点（左，右），大多藏在帽顶后面
    back=-2.0,          # 帽檐上沿在正中（帽顶后面）的高度
    height=42.0,        # 帽顶从帽檐的底线量起有多高
    apex=-2.5,          # 帽尖偏离中心多少（往左）
    crown_tip=5.6,      # 帽尖自己的圆头有多宽（半宽）
    knob=(5.2, 1.4),    # 帽尖上的小圆顶：半径，圆心比帽尖高出多少
    side=(0.62, 0.62),  # 帽顶左右两边的腰各往外鼓多少（0.62 是直边，不到 0.5 是往里凹）
    front=(3.8, 6.6, 7.2, 8.2, 5.8, 6.8, 4.0),      # 帽檐前沿从左到右七个点各往下多少（起伏）
)


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _moved(p, angle):
    """帽子自己坐标里的点 → 设计范围里的点：先绕帽檐正中转 angle 度，再挪到 (OX, OY)"""
    t = math.radians(angle)
    return (OX + p[0] * math.cos(t) - p[1] * math.sin(t), OY + p[0] * math.sin(t) + p[1] * math.cos(t))


def _circle(mask, cx, cy, r, n=28):
    mask.polygon([(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)])


def build(doodle, p=None):
    """返回高分辨率的透明度图（W×H 的设计范围，已经按 8 倍画好）"""
    q = dict(P if p is None else p)
    d = doodle.Mask(W, H)
    a = q["angle"]
    T, B, h = q["reach"], q["reach"] - q["lip"], q["height"]
    mv = lambda pts: [_moved(pt, a) for pt in pts]

    # ---- 帽檐：从左边的尖出发，沿上沿绕到帽顶后面、再到右边的尖（两头的小尖保持尖角），然后沿前沿从右往左回来
    f = q["front"]
    xs = (-T + 9, -T + 20, -T + 33, -T + 45, -T + 57, -T + 69, -T + 80)     # 前沿七个点各在哪
    (ul, ur), (tl, tr) = q["upper"], q["tip"]
    d.shape(mv([(-T, tl, 1), ul, (0, q["back"]), ur, (T, tr, 1)] + [(x, y) for x, y in reversed(list(zip(xs, f)))]))
    # ---- 帽顶：宽矮的圆锥，坡面基本是直的，帽尖略偏左，顶上是一个圆头
    ax, tk, sl = q["apex"], q["crown_tip"], q["side"]
    d.shape(mv([(-B, 2.0), (-B, -1.0), (-B * 0.80, -h * 0.16), (-B * sl[0], -h * 0.38), (-B * 0.33, -h * 0.62), (-tk - 3.4, -h * 0.86),
                (ax - tk, -h + 2.6), (ax, -h), (ax + tk, -h + 2.6), (ax + tk + 3.4, -h * 0.86),
                (B * 0.37, -h * 0.60), (B * sl[1], -h * 0.38), (B * 0.78, -h * 0.16), (B, -1.0), (B, 2.0), (0, 3.0)]))
    # ---- 帽尖上的小圆顶
    kx, ky = _moved((ax + 0.2, -h - q["knob"][1]), a)
    _circle(d, kx, ky, q["knob"][0])
    d.soften(0.9)
    return d.alpha()


def main():
    doodle, kit = _load("doodle"), _load("a1_kit")
    box = doodle.orig_box(REF)
    img = doodle.place(build(doodle), doodle.orig_size(REF), box, hand=HAND)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    ok = doodle.check(out, REL, zoom=ZOOM_MIN, kind="3d", ref=REF, name=REL)
    if len(sys.argv) > 1:
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=(ZOOM_MIN, 0.5, 0.7), title="斗笠"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

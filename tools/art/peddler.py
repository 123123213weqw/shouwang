#!/usr/bin/env python3
"""货郎（yv.png，选人卡片上第 4 张）：走街串巷的货郎——戴毡帽（圆顶、有檐），招风耳，咧着嘴笑，
肩上挑一根扁担，两头各压着一捆货。

和原版的图一样是 236×248 的画布，图形落在原版 yv.png 的范围里（x 40..189、y 58..194：原版是个大三角形，
比较高）。新图是"⊥"形：上面是圆顶的毡帽和脸（不到 100 像素宽），最下面一根 150 像素宽的扁担横在
下巴底下、两头各一捆货——宽度全给了扁担，高度给了高高的帽顶。别的角色都是头大身子小，
只有他是底下宽，光看轮廓就分得开。

扁担和货捆都画在头这一张图里（没有另做身子）：游戏里头和身子是两张图，镜头是斜的，身子在屏幕上
会相对头往右下错开 20 到 40 个纹理像素（屏幕上 9 到 12 像素），还会随主角在棋盘上的位置变——
分开画的话，绳子永远对不上扁担。

游戏里镜头是俯视的，头在屏幕上竖向只压到一半多一点，所以：帽檐 16 像素厚、扁担 13 像素粗、
咧嘴的口子 17 像素高、耳朵和帽檐之间留 14 像素——再细/再近在棋盘上就没了或者粘上了。

用法: python3 -I peddler.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 yv.png。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


fig = _load("figure")
doodle = fig.doodle
REL = "assets/sprites/characters/yv.png"


def hat():
    """毡帽：高高的圆顶（顶在 y 58，范围的顶）+ 一圈短短的、两头圆的檐"""
    d = doodle.Mask(236, 248)
    d.ellipse((72.5, 58, 156.5, 142))                   # 帽顶（下半截藏在檐和脸后面）
    d.capsule((69, 99), (160, 99), 16)                  # 帽檐：比帽顶两边各宽出十来个像素
    return d


def face():
    """脸：方圆脸，两边各一只招风耳（圆的，从帽檐底下伸出来）"""
    d = doodle.Mask(236, 248)
    d.shape([
        (80, 108),
        (77, 124),
        (78, 142),
        (82, 158),
        (90, 169),
        (101, 175.5),
        (114.5, 177),
        (128, 175.5),
        (139, 169),
        (147, 158),
        (151, 142),
        (152, 124),
        (149, 108),
    ])
    d.ellipse((66, 122, 88, 146))                       # 左耳
    d.ellipse((141, 122, 163, 146))                     # 右耳
    return d


def grin():
    """咧嘴笑：一个上平下圆的口子（挖空），17 像素高"""
    d = doodle.Mask(236, 248)
    d.ellipse((96.5, 127, 132.5, 161))                 # 整个椭圆 36×34，再把上半截去掉，只剩下半圆（36×17，上平下圆）
    top = doodle.Mask(236, 248)
    top.polygon([(90, 120), (140, 120), (140, 144), (90, 144)])
    d.cut(top)
    return d


def neck():
    """脖子：从下巴一直到 y 194（范围的底），扁担从它后面过去"""
    d = doodle.Mask(236, 248)
    d.polygon([(104, 166), (125, 166), (125, 194.6), (104, 194.6)])
    return d


def pole_and_loads():
    """扁担：横在下巴底下，两头微微往上翘；两头各压着一捆圆滚滚的货"""
    d = doodle.Mask(236, 248)
    d.path([(47, 183.5), (80, 188), (114.5, 188), (150, 188), (182, 183.5)], 13)
    d.ellipse((40, 159, 74, 185))                       # 左边的货捆
    d.ellipse((155, 159, 189, 185))                     # 右边的货捆
    return d


def build():
    head = hat()
    head.union(face())
    head.union(neck())
    head.union(pole_and_loads())
    head.soften(1.0)
    holes = grin()
    holes.union(fig.eyes([(99, 124), (130, 124)], 7.5, 8.5))
    holes.soften(0.4)
    head.cut(holes)
    return head.alpha()


if __name__ == "__main__":
    img = fig.to_canvas(build())
    ok = fig.verify(img, REL)
    if not fig.pure_white(img):
        print("  [不合格] 有不是纯白的不透明像素"); ok = False
    print("自检：%s" % ("合格" if ok else "不合格"))
    chars = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "sprites", "characters"))
    out = fig.write(img, sys.argv[2] if len(sys.argv) > 2 else None, "yv.png")
    if len(sys.argv) > 1:
        fig.preview(sys.argv[1], "货郎 yv.png", out, os.path.join(chars, "body.png"), REL, fig.CHARS + "body.png")

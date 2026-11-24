#!/usr/bin/env python3
"""小鼓手（ikke.png，选人卡片上第 5 张）：巡游队伍里打鼓的孩子——戴虎头帽（圆帽顶、头顶两只圆尖的耳朵），
脸圆、腮帮子鼓，张着嘴在喊拍子。

和原版的图一样是 236×248 的画布，图形落在原版 ikke.png 的范围里（x 54..175、y 69..182）。
轮廓是"头顶两个尖"的圆脑袋，别的角色头上是帽子、头巾或者辫子。虎头帽额头上那个"王"字没有画：
镜头是俯视的，头在屏幕上竖向只压到一半多一点，三道横 10 像素的笔画在棋盘上会糊成一团。

这张图除了当角色，还是排行榜每一行、解锁提示和结算页上的头像，最小的只有 0.2 倍（头 25 像素宽），
所以脸上只留三样东西：两只眼睛、一张圆嘴，都在 15 像素以上。

游戏里镜头是俯视的：眼睛 15×17、嘴 16 像素，耳朵尖比帽顶高出 14 像素——再小在棋盘上就没了。

用法: python3 -I drummer.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 ikke.png。
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
REL = "assets/sprites/characters/ikke.png"
CX = 114.5                        # 这张图的中线


def tiger_hat():
    """虎头帽：圆帽顶，顶在 y 83；两边各一只耳朵，耳朵尖朝上、略微往外，尖在 y 69（范围的顶），
    外沿伸到范围的左右两边；帽子的下沿是一道边，比上半个脸宽出一截"""
    d = doodle.Mask(236, 248)
    d.shape([
        (70, 108),
        (70, 98),
        (76, 89),
        (88, 85),
        (101, 83.5),
        (114.5, 83),
        (128, 83.5),
        (141, 85),
        (153, 89),
        (159, 98),
        (159, 108),
        (148, 113),
        (114.5, 115),
        (81, 113),
    ])
    d.capsule((67, 108), (162, 108), 12)                 # 帽子的下沿：一道边，比上半个脸宽出一截
    ear = [(62, 106), (55.2, 86), (64, 68.3, 1), (84, 74), (94, 89), (88, 103)]    # 左耳，第三个点保持尖；耳朵的外沿伸到范围的左边
    d.shape(ear)
    d.shape(fig.flip(ear, CX))                                                    # 右耳
    return d


def face():
    """脸：圆脸，腮帮子鼓出来，下巴圆，底在 y 182（范围的底）"""
    d = doodle.Mask(236, 248)
    d.shape([
        (74, 120),
        (74, 106),
        (82, 98),
        (98, 94),
        (114.5, 93),
        (131, 94),
        (147, 98),
        (155, 106),
        (155, 120),
        (159, 140),
        (154, 160),
        (143, 174),
        (129, 181),
        (114.5, 182.4),
        (100, 181),
        (86, 174),
        (75, 160),
        (70, 140),
    ])
    return d


def holes():
    """眼睛两只 + 张开的圆嘴"""
    d = fig.eyes([(101, 134), (128, 134)], 7.5, 8.5)
    d.ellipse((106.5, 151, 122.5, 167))
    return d


def build():
    head = face()
    head.union(tiger_hat())
    head.soften(1.6)              # 耳朵尖抹圆一点
    h = holes()
    h.soften(0.4)
    head.cut(h)
    return head.alpha()


if __name__ == "__main__":
    img = fig.to_canvas(build())
    ok = fig.verify(img, REL)
    if not fig.pure_white(img):
        print("  [不合格] 有不是纯白的不透明像素"); ok = False
    print("自检：%s" % ("合格" if ok else "不合格"))
    chars = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "sprites", "characters"))
    out = fig.write(img, sys.argv[2] if len(sys.argv) > 2 else None, "ikke.png")
    if len(sys.argv) > 1:
        fig.preview(sys.argv[1], "小鼓手 ikke.png", out, os.path.join(chars, "body.png"), REL, fig.CHARS + "body.png")

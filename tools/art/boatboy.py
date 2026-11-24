#!/usr/bin/env python3
"""船家少年（eye.png，选人卡片上第 2 张）：撑船的少年——圆脸，头上扎头巾，结和两个巾角飘在左边，眼睛弯弯的。

和原版的图一样是 236×248 的画布，图形落在原版 eye.png 的范围里（x 52..182、y 69..178）。
头巾是一顶圆帽子，下沿是一道比帽顶和脸都宽出一截的边；结在左边，两个巾角一上一下往左飘，伸到范围的左边——
所以轮廓左边伸出两个巾角和一个结，右边是圆的、只在下沿露出一个小鼓包，一眼就跟别的角色分得开。

眼睛画成两道弯（"⌒"），是挖空的弧。游戏里镜头是俯视的，头在屏幕上竖向只压到一半多一点，
所以弧只有 5 像素高，在棋盘上看起来是两道横线（眯眼笑），在选人卡片上才看得出是弯的；
弧画到 12 像素粗，再细在棋盘上就没了。

用法: python3 -I boatboy.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 eye.png。
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
REL = "assets/sprites/characters/eye.png"


def scarf():
    """头巾：扣在头上的一顶圆帽子，顶在 y 69（范围的顶），下沿是一道边（比帽顶和脸都宽出一截，像帽檐）"""
    d = doodle.Mask(236, 248)
    d.shape([
        (86, 110),
        (85, 96),
        (92, 82),
        (106, 72.5),
        (127, 69.3),
        (145, 69.5),
        (157, 74),
        (164, 82),
        (168, 96),
        (168, 110),
        (120, 116),
        (88, 114),
    ])
    d.capsule((84, 108), (174, 108), 16)                 # 头巾的下沿：一道边，比上头的帽顶和下面的脸都宽出一截
    return d


def knot_and_tails():
    """左边打的结（一个圆球）和两个巾角：一个往左上飘、一个往左下飘，都是圆头的短棒。
    两个巾角之间留出一道朝左张开的口子"""
    d = doodle.Mask(236, 248)
    d.ellipse((70, 94, 90, 114))                        # 结
    d.capsule((79, 101), (58.5, 76.3), 13)              # 上面那个巾角
    d.capsule((79, 108), (59.5, 119), 13)               # 下面那个巾角
    return d


def face():
    """脸：圆圆的、比头巾窄一圈，下巴圆，底在 y 178（范围的底）"""
    d = doodle.Mask(236, 248)
    d.shape([
        (90, 122),
        (94, 106),
        (108, 97),
        (132, 93),
        (156, 95),
        (170, 104),
        (176, 120),
        (177, 140),
        (172, 158),
        (160, 171),
        (144, 177.5),
        (126, 178.5),
        (108, 173),
        (96, 160),
        (88, 142),
    ])
    return d


def smiling_eyes():
    """弯弯的眼睛：两段朝上弯的弧（挖空），粗 12"""
    d = doodle.Mask(236, 248)
    for cx in (110, 150):
        d.arc((cx - 9, 134 - 8, cx + 9, 134 + 8), 200, 340, 12)
    return d


def build():
    head = scarf()
    head.union(knot_and_tails())
    head.union(face())
    head.soften(1.0)
    e = smiling_eyes()
    e.soften(0.4)
    head.cut(e)
    return head.alpha()


if __name__ == "__main__":
    img = fig.to_canvas(build())
    ok = fig.verify(img, REL)
    if not fig.pure_white(img):
        print("  [不合格] 有不是纯白的不透明像素"); ok = False
    print("自检：%s" % ("合格" if ok else "不合格"))
    chars = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "sprites", "characters"))
    out = fig.write(img, sys.argv[2] if len(sys.argv) > 2 else None, "eye.png")
    if len(sys.argv) > 1:
        fig.preview(sys.argv[1], "船家少年 eye.png", out, os.path.join(chars, "body.png"), REL, fig.CHARS + "body.png")

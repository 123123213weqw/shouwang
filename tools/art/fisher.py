#!/usr/bin/env python3
"""钓叟（evil.png，选人卡片上第 1 张）：老渔翁——宽檐的旧草帽、腮帮子、山羊胡，嘴边叼一根旱烟杆。

和原版的图一样是 236×248 的画布，图形落在原版 evil.png 的范围里（x 37..192、y 77..174：又宽又扁，
原版宽是因为两头有角）。新图的宽度全给了草帽的檐（左右各伸出脸三十多像素），所以轮廓是一个宽宽的"T"字，
和守夜人尖顶的斗笠分得开。高度只有 98 像素，分成：帽顶 21、帽檐 14、脸 44、胡子 19 左右。

游戏里镜头是俯视的，头在屏幕上竖向只压到一半多一点（第 12 关 0.54 倍），所以：
  帽檐画到 14 像素厚、烟杆 14 像素粗、眼睛 15×17 ——再细的横线在棋盘上就没了；
  帽檐左低右高地斜着（旧草帽，一边耷拉下来），右边留出地方给烟杆。

用法: python3 -I fisher.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图。给了就在里面写出 evil.png。
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
REL = "assets/sprites/characters/evil.png"


def hat():
    """草帽：小而圆的帽顶 + 又宽又厚、左低右高的帽檐。帽檐两头收成圆尖"""
    d = doodle.Mask(236, 248)
    d.ellipse((85, 76.7, 145, 117))                     # 帽顶（下半截藏在帽檐和脸后面）
    d.shape([
        (37.2, 122, 1),        # 帽檐左端（耷拉下来的一头），收成一个圆尖
        (46, 115),
        (62, 107),
        (84, 100.5),
        (112, 97),
        (140, 97),
        (164, 95.5),
        (180, 96.5),
        (192.2, 102.5, 1),     # 帽檐右端
        (182, 111),
        (156, 113),
        (124, 114),
        (96, 117),
        (70, 123),
        (50, 130),
        (40, 128),
    ])
    return d


def face():
    """脸：上窄下宽，腮帮子往下坠；下巴的正中垂下一撮山羊胡（尖朝下，两边各留出一道弯角，
    这样胡子不会看成是尖下巴）"""
    d = doodle.Mask(236, 248)
    d.shape([
        (77, 112),
        (74, 127),
        (77, 140),
        (85, 150),
        (97, 155),
        (115, 156.5),
        (133, 155),
        (145, 150),
        (153, 140),
        (156, 127),
        (153, 112),
    ])
    d.shape([(101, 146), (129, 146), (122, 165), (114, 174.6, 1), (108, 165)])     # 山羊胡：从下巴的正中垂下来，尖朝下
    return d


def pipe():
    """旱烟杆：从嘴角斜着往下伸出去，头上一个小烟锅。整根连在脸上（叼在嘴里），不是单独一块"""
    d = doodle.Mask(236, 248)
    d.capsule((150, 136), (178, 153), 14)
    d.ellipse((173.5, 154.6, 192.5, 174.6))                 # 烟锅
    return d


def build():
    head = hat()
    head.union(face())
    head.union(pipe())
    head.soften(1.0)              # 帽檐和脸、脸和胡子、烟杆和嘴的接缝抹圆（胡子尖、帽檐尖留着）
    head.cut(fig.eyes([(102, 132), (128, 132)], 7.5, 8.5))
    return head.alpha()


if __name__ == "__main__":
    img = fig.to_canvas(build())
    ok = fig.verify(img, REL)
    if not fig.pure_white(img):
        print("  [不合格] 有不是纯白的不透明像素"); ok = False
    print("自检：%s" % ("合格" if ok else "不合格"))
    chars = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "sprites", "characters"))
    out = fig.write(img, sys.argv[2] if len(sys.argv) > 2 else None, "evil.png")
    if len(sys.argv) > 1:
        fig.preview(sys.argv[1], "钓叟 evil.png", out, os.path.join(chars, "body.png"), REL, fig.CHARS + "body.png")

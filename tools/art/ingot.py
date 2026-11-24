#!/usr/bin/env python3
"""元宝：原版的五角星（star.png）换成一只金元宝。它不是棋盘上的东西，是分数图标：通关结算面板上
"守到天明"四个字的两边各一个（画面上 47×41 像素），选人卡片的名字旁边也有（34×34 像素）。走的是界面上的 2D 着色器。

和原版的五角星一样：156×136 的画布，图形落在同一块范围里（x 12..139，y 11..118），纯白、实心，
不描边、不画明暗。位置、大小、缩放、染色都不变。

画法（坐标是 127×107 的设计范围，y 向下）：
  船     一个两端翘起的小船，占了三分之二的高度：船沿当中微微下凹，到两头翘成尖角，底下是圆弧的船底；
  顶     正当中一个矮矮的馒头（顶面 54 宽、42 高），坐在船里，顶比两头的角只高一点。
整张图是连在一起的一块，没有洞（原版的五角星也没有洞）。它最小的用处是选人卡片名字旁边的那个，
28×21 个屏幕像素，而且那一处它垫在名字后面、下半截被名字的框挡着，看得见的是顶和两头的角，
所以顶要矮而胖：第一版把顶画得又高又尖，垫在名字后面就像一顶皇冠了。顶和船沿之间的两个凹口有 15 个纹理像素宽。
元宝和河灯（fish.png，一只小船里一团火）都是船形，分得开：元宝当中是矮矮的实心圆顶、两头的角翘得和顶一样高；
河灯当中是细高的火苗，船沿是平的。

用法: python3 -I ingot.py [预览图的输出路径]
  总是把 star.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图。
只依赖 Pillow。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/star.png"
W, H = 127, 107                                          # 设计范围 = 原版图形的范围
ZOOM_PANEL, ZOOM_CARD = 0.30, 0.22                       # 结算面板上、选人卡片上各是多大（进游戏量出来的）


def _load(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle, kit):
    """返回高分辨率的透明度图（127×107 的设计范围，已经按 8 倍画好）"""
    cx = W / 2.0                                         # 63.5
    b = doodle.Mask(W, H)
    b.shape([
        (cx - 27, 35),
        (cx - 15, 18),
        (cx, 14),                                        # 圆顶的顶（矮矮的一个馒头）
        (cx + 15, 18),
        (cx + 27, 35),
        (cx + 33, 49),                                   # 顶的脚
        (cx + 48, 56),                                   # 船沿（顶和角之间的凹口）
        (cx + 63, 26, 1),                                # 右头翘起的角
        (cx + 59, 64),
        (cx + 49, 88),
        (cx + 26, 103),
        (cx, 107),                                       # 船底
        (cx - 26, 103),
        (cx - 49, 88),
        (cx - 59, 64),
        (cx - 63, 26, 1),                                # 左头翘起的角
        (cx - 48, 56),
        (cx - 33, 49),
    ])
    b.soften(1.1)                                        # 把角和顶抹圆
    return b.alpha()


def main():
    doodle, kit = _load("doodle"), _load("a1_kit")
    box = doodle.orig_box(REL)
    img = doodle.place(build(doodle, kit), doodle.orig_size(REL), box)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    ok = doodle.check(out, REL, zoom=ZOOM_CARD, kind="2d", name=REL)
    if len(sys.argv) > 1:
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=[(ZOOM_PANEL, 1.0), (ZOOM_CARD, 1.0)], title="元宝"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

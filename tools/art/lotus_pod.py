#!/usr/bin/env python3
"""连击方块（原版是骰子，六张图随机出现）→ 莲蓬，莲子 1 到 6 颗。

画布 156×136，图形落在原版的范围里（x 47..109，y 58..121，62×63），纯白实心，莲子是挖空的洞。
原版的骰子在游戏里是随机出现的装饰：六张图随机挑一张，点数没有任何玩法含义。所以这一张最要紧的是
"小方块上带着几个点"这种一眼能认的结构，其次才是主题。试过画成更鼓（鼓点即鼓钉、鼓加鼓槌），在这么小的
范围里（屏幕上只有 18 到 28 个像素）实拍是纽扣、小电视机，所以换成莲蓬：上宽下收的花托带一根短梗，
莲子就是点。莲蓬多子，在江南水乡是"多子多福"的意思。
六张图的花托和梗完全一样，只有莲子的颗数不同：
  1 颗在正中；2 颗左右并排；3 颗品字形；4 颗四角；5 颗四角加中间；6 颗上下两排。
莲子直径 9 个纹理像素、圆心相距 17 个，最小的那一档（zoom 0.29）莲子约 2.6 屏幕像素、间隔约 2.3。

用法: python3 -I lotus_pod.py [输出目录]      不给输出目录就写在工程的 assets/sprites/upgrades/combooo-1.png … combooo-6.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

RELS = ["assets/sprites/upgrades/combooo-%d.png" % n for n in range(1, 7)]
CANVAS = (156, 136)
W, H = 62, 63                 # 设计范围 = 原版的图形范围
R = 4.6                       # 莲子的半径
SEEDS = {                     # 每张图莲子的圆心
    1: [(31, 26)],
    2: [(22, 26), (40, 26)],
    3: [(31, 15), (22, 36), (40, 36)],
    4: [(15, 15), (47, 15), (15, 36), (47, 36)],
    5: [(15, 15), (47, 15), (31, 25), (15, 36), (47, 36)],
    6: [(14, 15), (31, 12), (48, 15), (15, 36), (31, 33), (47, 36)],
}
POD = [                       # 花托：上沿平而略鼓，两侧往下收，底是圆的
    (4, 10), (18, 5), (44, 5), (58, 10), (59, 30), (51, 45), (40, 53), (31, 56), (22, 53), (11, 45), (3, 30),
]


def draw(count):
    d = doodle.Mask(W, H)
    d.shape(POD)                                     # 花托
    d.capsule((31, 52), (33, 62), 7)                 # 短梗
    d.soften(1.2)
    seeds = doodle.Mask(W, H)
    for x, y in SEEDS[count]:
        seeds.ellipse((x - R, y - R, x + R, y + R))
    seeds.soften(0.4)
    d.cut(seeds)
    return d.alpha()


def build(count):
    return doodle.place(draw(count), CANVAS, doodle.orig_box(RELS[0]))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    for n in range(1, 7):
        path = os.path.join(out_dir, RELS[n - 1])
        os.makedirs(os.path.dirname(path), exist_ok=True)
        build(n).save(path)
    print("已写出", ", ".join(os.path.relpath(os.path.join(out_dir, r), out_dir) for r in RELS))

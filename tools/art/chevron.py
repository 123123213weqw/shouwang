#!/usr/bin/env python3
"""箭头符号（一个尖角，›）：难度加减器两头的两个按钮用的（暂停菜单里、没过的结算面板上）。
游戏的手写字体里没有 ‹ › ← → 这些字形（写上去是个空框），所以画一张朝右的，朝左的那一边在游戏里左右翻过来。
新加的图，原版里没有：拿同一套界面图标里的返回箭头（ui/actions/back.png）当参照，画布和图形的范围都照它来。

311×316 的画布，图形落在返回箭头那块范围里（x 81..222，y 72..227，141×155），纯白、实心，不描边、不画明暗。
一笔折成两段的粗线：上面那一臂略短、收得高一点，下面那一臂长一点，两头是圆的，拐角抹圆——不是拿尺子画的等腰尖角。
线画到 26 个纹理像素粗：游戏里这个尖角在屏幕上约 30 像素宽（zoom 约 0.3），粗 8 个屏幕像素，缩小了也看得清。

用法: python3 -I chevron.py
  把 chevron.png 写到工程的 assets/sprites/ui/rules/ 里并自检。
只依赖 Pillow 和 numpy。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/ui/rules/chevron.png"
REF = "assets/sprites/ui/actions/back.png"               # 当参照的原版图（返回箭头：也是粗线条的图形）
ZOOM = 30.0 / 98.0                                      # 游戏里尖角约 30 屏幕像素宽（图形本身宽 98 个纹理像素）

# 设计范围就是参照图形的范围。原点在它的左上角，单位是设计像素
W, H = 141, 155
TIP = (107.0, 78.0)          # 尖角顶点（两臂相交处的中线）
UPPER = (41.0, 26.0)         # 上面那一臂的另一头
LOWER = (32.0, 130.0)        # 下面那一臂的另一头
STROKE = 26.0                # 线的粗细


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    doodle = _load("doodle")
    d = doodle.Mask(W, H)
    d.path([UPPER, TIP, LOWER], STROKE)
    d.soften(1.0)
    img = doodle.place(d.alpha(), doodle.orig_size(REF), doodle.orig_box(REF), hand=dict(seed=57, wobble=0.010, thick=0.012, tilt=0.8))
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    return 0 if doodle.check(out, REL, zoom=ZOOM, kind="2d", ref=REF, name=REL) else 1


if __name__ == "__main__":
    sys.exit(main())

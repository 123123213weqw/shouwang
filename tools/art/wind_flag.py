#!/usr/bin/env python3
"""风幡：难度里"风向"这条规矩的小旗子，挂在游戏画面左上角，旗子飘向哪边、风就往哪边吹。新加的图，原版里没有：
拿同一套界面图标里的返回箭头（ui/actions/back.png）当参照，画布和图形的范围都照它来。

311×316 的画布，图形落在返回箭头那块范围里（x 81..222，y 72..227，141×155），纯白、实心，不描边、不画明暗。
画的是一面三角旗（帶燕尾的幡）系在一根竿子上：竿子粗、略往左歪，顶上一个圆头；旗面从竿子顶部往右飘，
右边是燕尾（两个尖），上沿鼓、下沿收，两面都不平直——风里的布没有一条直边。旗面和竿子连成一块。
游戏里这面旗只有 54×54 屏幕像素（zoom 约 0.38）：竿子画到 18 个纹理像素粗（约 7 个屏幕像素），
旗面 95×50 个纹理像素（约 36×19 个屏幕像素），燕尾的口子挖得深（25 个纹理像素，约 10 个屏幕像素），
缩小了也看得出是旗而不是一块布。南风、北风的时侯游戏里把整面旗转 90 度，所以四个方向用的是同一张图。

用法: python3 -I wind_flag.py
  把 wind_flag.png 写到工程的 assets/sprites/ui/rules/ 里并自检。
  想看它在游戏里的大小：python3 -I review.py mini 预览.png 0.38 assets/sprites/ui/rules/wind_flag.png
只依赖 Pillow 和 numpy。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/ui/rules/wind_flag.png"
REF = "assets/sprites/ui/actions/back.png"               # 当参照的原版图（返回箭头：也是细线条的图形）
ZOOM = 54.0 / 141.0                                      # 游戏里一个纹理像素等于几个屏幕像素（旗子 54 像素宽）
HAND = dict(seed=311, wobble=0.016, thick=0.022, tilt=1.5)   # 手绘化的力度（默认的）

# 设计范围就是参照图形的范围。坐标原点在它的左上角，单位是设计像素
W, H = 141, 155
POLE_BOTTOM = (31.0, 152.0)      # 竿子脚（圆心）
POLE_TOP = (22.0, 12.0)          # 竿子头（圆心）：整根往左歪三度多
POLE_W = 18.0                    # 竿子的粗细
KNOB_D = 27.0                    # 竿子顶上圆头的直径
# 旗面：从竿子顶部出发，往右飘。两个尖保留尖角（第三个数是 1），燕尾的口子往里收 25
FLAG = [(28.0, 13.0), (62.0, 8.0), (96.0, 12.0), (139.0, 27.0, 1), (113.0, 47.0), (139.0, 68.0, 1),
        (101.0, 79.0), (62.0, 76.0), (30.0, 62.0)]


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle):
    """返回高分辨率的透明度图（W×H 的设计范围，已经按 8 倍画好）"""
    d = doodle.Mask(W, H)
    d.shape(FLAG)
    d.capsule(POLE_BOTTOM, POLE_TOP, POLE_W)          # 竿子
    d.ellipse((POLE_TOP[0] - KNOB_D / 2, POLE_TOP[1] - KNOB_D / 2, POLE_TOP[0] + KNOB_D / 2, POLE_TOP[1] + KNOB_D / 2))
    d.soften(1.2)
    return d.alpha()


def main():
    doodle = _load("doodle")
    box = doodle.orig_box(REF)
    img = doodle.place(build(doodle), doodle.orig_size(REF), box, hand=HAND)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    ok = doodle.check(out, REL, zoom=ZOOM, kind="2d", ref=REF, name=REL)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

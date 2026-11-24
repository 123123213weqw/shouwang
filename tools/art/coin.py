#!/usr/bin/env python3
"""铜钱：原版的四叶草（clover.png）换成一枚铜钱，外圆内方。棋盘上能收的那样东西（让道具掉得更多的那一种）。

和原版的四叶草一样：156×136 的画布，图形落在同一块范围里（x 27..124，y 21..124），纯白、实心，
不描边、不画明暗，细节用挖空的洞表示。位置、大小、缩放、染色都不变。

画法（坐标是 97×103 的设计范围，y 向下）：
  外圆   一个滚圆的圆，直径 97，上下居中（原版的四叶草下面多出一截茎，所以范围比圆高出 6 个纹理像素）；
  方孔   正当中一个圆角的方孔，边长 34。
整张图是连在一起的一块，只有当中那一个方孔（最小的镜头下 10.5 个屏幕像素；原版的四叶草没有洞，
原版的鱼有一个 11 像素的眼睛）。铜钱上四个字的位置不画字：这张图在游戏里最小的时候只有 28 个屏幕像素宽，
字会糊成几团（镜头拉到 0.29 的时候是 28 个）。外圆和方孔之间的那一圈有 31 个纹理像素宽。

用法: python3 -I coin.py [预览图的输出路径]
  总是把 clover.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图。
只依赖 Pillow。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/clover.png"
W, H = 97, 103                                           # 设计范围 = 原版图形的范围
ZOOM_MIN = 0.31                                          # 最小的镜头：一个纹理像素等于几个屏幕像素（第 12 关最远一排）


def _load(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle, kit):
    """返回高分辨率的透明度图（97×103 的设计范围，已经按 8 倍画好）"""
    cx, cy = W / 2.0, H / 2.0                            # 48.5、51.5
    b = doodle.Mask(W, H)
    # ---- 外圆
    b.ellipse((cx - 48.5, cy - 48.5, cx + 48.5, cy + 48.5))
    b.soften(0.8)
    # ---- 方孔
    holes = doodle.Mask(W, H)
    kit.round_rect(holes, cx - 17, cy - 17, cx + 17, cy + 17, 4)
    holes.soften(0.5)
    b.cut(holes)
    return b.alpha()


def main():
    doodle, kit = _load("doodle"), _load("a1_kit")
    box = doodle.orig_box(REL)
    img = doodle.place(build(doodle, kit), doodle.orig_size(REL), box)
    out = os.path.join(ROOT, REL)
    img.save(out)
    print("已写出", out)
    ok = doodle.check(out, REL, zoom=ZOOM_MIN, kind="3d", name=REL)
    if len(sys.argv) > 1:
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=(ZOOM_MIN, 0.5), title="铜钱"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

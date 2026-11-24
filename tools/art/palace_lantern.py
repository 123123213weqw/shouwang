#!/usr/bin/env python3
"""宫灯：原版的大鱼（big-fish.png）换成一只圆灯笼，上下有灯口。棋盘上要收的那样东西，大而醒目。

和原版的大鱼一样：156×136 的画布，图形落在同一块范围里（x 9..147，y 30..133），纯白、实心，
不描边、不画明暗，细节用挖空的洞表示。位置、大小、缩放、染色都不变。

画法（坐标是 138×103 的设计范围，y 向下）：
  灯身   滚圆饱满的一团（136×80，比椭圆再鼓一点），把宽度撑满；
  灯口   上面一个帽、下面一个座，都是口小、底下大的圆角梯形，比灯身窄得多，各露出 11 个纹理像素；
  灯骨   灯身上左右对称挖两条梭形的缝，是灯笼的竹骨之间透光的地方。
整张图是连在一起的一块，带两个洞。原版的大鱼只有一个 9 个纹理像素的眼睛；这里的缝有 15 个纹理像素宽
（最小的镜头下 4 个多屏幕像素），缝和缝之间隔着 39 个纹理像素，缝和灯身边缘之间隔着 27 个。

这是中式的宫灯（滚圆的灯身、上下小口、几根粗骨），不是日式的灯笼：日式的是横放的桶形、骨很密、上面写字。

这张图还被连击计数用到（画面左上角，每收一个大鱼加一个，一个 76×77 像素，走的是界面上的 2D 着色器）。

用法: python3 -I palace_lantern.py [预览图的输出路径]
  总是把 big-fish.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图。
只依赖 Pillow。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/big-fish.png"
W, H = 138, 103                                          # 设计范围 = 原版图形的范围
ZOOM_MIN = 0.31                                          # 最小的镜头：一个纹理像素等于几个屏幕像素（第 12 关最远一排）
ZOOM_HUD = 0.49                                          # 连击计数里的大小（界面上的 2D 精灵）


def _load(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle, kit):
    """返回高分辨率的透明度图（138×103 的设计范围，已经按 8 倍画好）"""
    cx = W / 2.0                                         # 69
    b = doodle.Mask(W, H)
    # ---- 灯身：滚圆饱满的一团（比椭圆再鼓一点，上下不那么尖），上下各留出灯口的地方
    kit.superellipse(b, cx, H / 2.0, 68, 40, 2.3)
    # ---- 上面的灯口（帽）和下面的灯口（座）：口小、底下大，各露出 11 个纹理像素
    for s, y in ((1, 0.5), (-1, H - 0.5)):
        b.shape([(cx - 22, y), (cx + 22, y), (cx + 26, y + s * 8), (cx + 27, y + s * 22), (cx - 27, y + s * 22), (cx - 26, y + s * 8)])
    b.soften(1.2)                                        # 把灯口和灯身的接缝抹圆
    # ---- 两条灯骨之间的缝
    holes = doodle.Mask(W, H)
    for x in (cx - 27, cx + 27):
        kit.lens(holes, x, H / 2.0 - 19, x, H / 2.0 + 19, 15)
    holes.soften(0.6)
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
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=[(ZOOM_MIN, kit.SQUASH), (0.55, kit.SQUASH), (ZOOM_HUD, 1.0)], title="宫灯"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

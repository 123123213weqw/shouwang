#!/usr/bin/env python3
"""河灯：原版的鱼（fish.png）换成"莲花座 + 灯焰"。界面上叫"灯火"，是棋盘上要收的那样东西。

和原版的鱼一样：156×136 的画布，图形落在同一块范围里（x 22..131，y 70..132，又扁又宽），纯白、实心，
不描边、不画明暗。位置、大小、缩放、染色都不变。

画法（坐标是 109×62 的设计范围，y 向下）：
  莲座   一片横放的莲花瓣做成的小船：船舷当中微微往下凹，两头收成尖，底下是圆弧；
  灯焰   船当中一团火苗：底下收成腰，中段鼓起来，上面一个尖，尖往右歪一点（歪着的才像火）。
整张图是连在一起的一块，没有洞。这张图在游戏里最小的时候只有 30×16 个屏幕像素（第 12 关最远一排，镜头拉到 0.29），而且落在最远一排时
下半截会被前排的格子挡住，只看得见火苗和船舷，所以只画这两样，火苗占了四分之三的高度。
原版的鱼在这个大小下也只有"一团身体 + 一个 3 像素的眼睛"。最细的地方是火苗的腰（13 个纹理像素，
最小的镜头下 4 个屏幕像素）和船身的厚薄（当中 21 个纹理像素，6.5 个屏幕像素）。

试过的画法（都缩到最小的尺寸看过，其中好几种进游戏拍过）：碗沿上立着几个花瓣尖的（三瓣、五瓣的莲台）都像皇冠；花瓣朝外平伸的像蝴蝶；
莲座上镂空的像面具；口沿平整的碗又像纸杯蛋糕；船头船尾各自翘起一瓣的，近看是船，落到最远一排、
下半截被挡住以后又成了皇冠。最后定成"一片花瓣做的小船盛着一团火"——河灯本来就是漂在水上的
小船形状的灯，远看是一团火苗，近看是一只小船。

这张图还被连击计数用到（画面左上角，每收一个灯火加一个，一个 76×77 像素，走的是界面上的 2D 着色器）。

用法: python3 -I river_lantern.py [预览图的输出路径]
  总是把 fish.png 写到工程的 assets/sprites/upgrades/ 里；给了路径就再出一张预览图（原版 | 新图 | 两者按最小的镜头缩小的样子）。
只依赖 Pillow。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录
REL = "assets/sprites/upgrades/fish.png"
W, H = 109, 62                                           # 设计范围 = 原版图形的范围
ZOOM_MIN = 0.31                                          # 最小的镜头：一个纹理像素等于几个屏幕像素（第 12 关最远一排）
ZOOM_HUD = 0.49                                          # 连击计数里的大小（界面上的 2D 精灵）


def _load(name):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(doodle, kit):
    """返回高分辨率的透明度图（109×62 的设计范围，已经按 8 倍画好）"""
    cx = W / 2.0                                         # 54.5
    b = doodle.Mask(W, H)
    # ---- 莲座：一片横放的莲花瓣做成的小船。船舷当中微微往下凹，两头收成尖（比船舷只高一点），
    #      底下是圆弧。整条船是一笔画出来的轮廓，中间不鼓起来——两头翘得太高、当中又有肩的话，
    #      落在最远一排时下半截被前排的格子挡住，露出来的三只角就像皇冠了
    b.shape([
        (2, 35, 1),                                       # 左头的尖
        (cx - 34, 39),
        (cx, 41),
        (cx + 34, 39),
        (107, 35, 1),                                     # 右头的尖
        (cx + 42, 52),
        (cx + 22, 60.5),
        (cx, 62),
        (cx - 22, 60.5),
        (cx - 42, 52),
    ])
    # ---- 灯焰
    kit.flame(b, cx, 29, 46, 13, 18)
    b.soften(0.9)                                        # 把接缝抹圆
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
        print("预览图:", sys.argv[1], kit.sheet(sys.argv[1], REL, img, zoom=[(ZOOM_MIN, kit.SQUASH), (0.5, kit.SQUASH), (ZOOM_HUD, 1.0)], title="河灯"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

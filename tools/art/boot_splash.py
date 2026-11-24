#!/usr/bin/env python3
"""启动时一闪的那张图（assets/boot_splash.png）：和标题一致的"守望"。

和原版一样是 630×368、透明背景的彩色图，两个字落在原版图形的同一块范围里（x 29..600，y 43..325）。
两个字的样子直接取自 title_logo.py（同样的字、同样的倾斜、弯曲、粗细），所以启动图和标题页的标志是同一个标志。
原版是白色的手写 "Ooqo." 加一条紫色的鱼；紫色不在这个游戏的颜色里了，换成游戏的两章主色：守 用石绿、望 用朱砂。

这张图是原样显示的彩色图，不是染色的剪影。游戏启动时它不缩放、不插值（project.godot 里 boot_splash/use_filter=false，
底色是黑的），所以边缘的抗锯齿就是 PNG 里的样子。

用法: python3 -I boot_splash.py [预览图的输出路径] [输出目录]
  不带参数就把 boot_splash.png 写进工程并自检（tools/art/regen_all.sh 就是这么跑的）。
  给了预览图的路径就再出一张预览图；再给一个输出目录就写到那里，不写进工程。
  加上 --colors 时预览图里并排画出几种配色，用来挑（不写文件）。
只依赖 Pillow 和 numpy。
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def _logo():
    spec = importlib.util.spec_from_file_location("title_logo", os.path.join(HERE, "title_logo.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


logo = _logo()

OUT_REL = "assets/boot_splash.png"          # 写出来的新图
ORIG_REL = "assets/ooqo-title-itch.png"     # 照着画的那张原版图（量好的数在 originals.json 里）
CANVAS = (630, 368)
BOX = (29, 43, 572, 283)        # 原版图形的范围（x, y, 宽, 高）
BOOT_BG = (0, 0, 0)             # project.godot 里 boot_splash/bg_color
VIEW = (1152, 720)              # 启动图的底色铺满整个窗口，图本身不缩放、居中

IVORY = (243, 238, 228)         # 暖白
SHILV = (77, 182, 166)          # 石绿
ZHUSHA = (226, 83, 60)          # 朱砂
SCHEME = (SHILV, ZHUSHA)        # 定稿的配色：守、望 各一个颜色


def build(colors=SCHEME):
    """630×368 的 RGBA 图，透明背景"""
    full = logo.draw()                                     # 和标题用的是同一份高分辨率透明度图
    k = min(BOX[2] / full.width, BOX[3] / full.height)     # draw() 给的是 logo.SS 倍大小的图，缩到原版的范围里
    size = (max(1, round(full.width * k)), max(1, round(full.height * k)))
    at = (BOX[0] + (BOX[2] - size[0]) // 2, BOX[1] + (BOX[3] - size[1]) // 2)
    img = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    for i, col in enumerate(colors):
        layer = Image.new("RGBA", size, tuple(col) + (0,))
        layer.putalpha(logo.draw(only=i).resize(size, Image.LANCZOS))
        img.alpha_composite(layer, at)
    return img


def ink_box(img, level=24):
    ys, xs = np.where(np.asarray(img.convert("RGBA"))[..., 3] > level)
    return int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


def check(path):
    """和原版比画布、图形的范围、背景是不是透明的、颜色对不对。返回 True 表示合格"""
    d = logo._doodle()
    new = Image.open(path).convert("RGBA")
    osize, ob = d.orig_size(ORIG_REL), d.orig_box(ORIG_REL)
    ok = True
    if new.size != osize:
        print("  [错误] 画布 %s，原版是 %s" % (new.size, osize))
        return False
    nb = ink_box(new)
    print("  %s（画布 %dx%d）" % (OUT_REL, new.width, new.height))
    print("    图形的范围：原版 %dx%d@(x%d,y%d)，新图 %dx%d@(x%d,y%d)" % (ob[2], ob[3], ob[0], ob[1], nb[2], nb[3], nb[0], nb[1]))
    if nb[0] < ob[0] - 3 or nb[1] < ob[1] - 3 or nb[0] + nb[2] > ob[0] + ob[2] + 3 or nb[1] + nb[3] > ob[1] + ob[3] + 3:
        print("    [不合格] 图形超出了原版的范围"); ok = False
    if nb[2] < ob[2] * 0.85 or nb[3] < ob[3] * 0.85:
        print("    [不合格] 图形比原版的小太多"); ok = False
    elif nb[2] < ob[2] * 0.97 or nb[3] < ob[3] * 0.97:
        print("    [要看一眼] 图形比原版的小（宽 %d%%，高 %d%%）" % (100 * nb[2] / ob[2], 100 * nb[3] / ob[3]))
    a = np.asarray(new)
    edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    if edge[..., 3].max() != 0:
        print("    [不合格] 画布边上不是透明的"); ok = False
    solid = a[a[..., 3] == 255][:, :3]
    used = {tuple(int(v) for v in c) for c in np.unique(solid, axis=0)}
    want = {tuple(c) for c in SCHEME}
    print("    不透明像素的颜色：%s" % sorted(used))
    if not used <= want:
        print("    [不合格] 有配色以外的颜色"); ok = False
    print("    %s" % ("合格" if ok else "不合格"))
    return ok


def on_black(img, view=VIEW):
    """照游戏启动时的样子：黑的底色铺满 view 这么大的窗口，这张图不缩放、放在正中"""
    t = Image.new("RGB", view, BOOT_BG)
    t.paste(img, ((view[0] - img.width) // 2, (view[1] - img.height) // 2), img)
    return t


def _font(size):
    for f in ("/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/PingFang.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def preview(path, img, variants=None):
    """预览图：上面一行是游戏启动时的样子（裁中间一块，原大）；下面一行是几种配色（各画在 630×368 的黑底上）"""
    font, bg, fg = _font(18), (28, 34, 52), (235, 235, 245)
    boot = on_black(img).crop((236, 176, 916, 544))            # 680×368：图加上四周一点黑边
    top = Image.new("RGB", (boot.width + 16, boot.height + 46), bg)
    ImageDraw.Draw(top).text((8, 8), "游戏启动时的样子（原大，图居中、不缩放，底色是黑的）", fill=fg, font=font)
    top.paste(boot, (8, 34))
    items = [("定稿：石绿 + 朱砂", img)] + list(variants or [])
    old = logo._doodle().orig(ORIG_REL)      # 原版的图不在手边（没设 SW_ORIG）时是 None，预览图里就没有"原版"那一格
    tw, th = CANVAS[0] + 16, CANVAS[1] + 44
    tiles = ([("原版", old)] if old is not None else []) + items
    cols = min(4, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    bottom = Image.new("RGB", (tw * cols + 8, th * rows + 8), bg)
    dr = ImageDraw.Draw(bottom)
    for i, (name, im) in enumerate(tiles):
        x, y = 8 + (i % cols) * tw, 8 + (i // cols) * th
        dr.text((x, y), name, fill=fg, font=font)
        bottom.paste(on_black(im, CANVAS), (x, y + 26))
    sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height + 12), bg)
    sheet.paste(top, (0, 0))
    sheet.paste(bottom, (0, top.height + 12))
    sheet.save(path)
    print("预览图:", path, sheet.size)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--colors" in sys.argv:
        preview(args[0], build(), [
            ("暖白 + 暖白", build((IVORY, IVORY))),
            ("朱砂 + 石绿", build((ZHUSHA, SHILV))),
            ("暖白 + 朱砂", build((IVORY, ZHUSHA))),
            ("朱砂 + 朱砂", build((ZHUSHA, ZHUSHA))),
        ])
    else:
        img = build()
        if len(args) > 1:                              # 给了输出目录就写到那里，不写进工程
            os.makedirs(args[1], exist_ok=True)
            out = os.path.join(args[1], "boot_splash.png")
        else:
            out = os.path.join(ROOT, OUT_REL)           # 不给输出目录就写进工程
        img.save(out)
        print("已写出", out, img.size)
        check(out)
        if args:
            preview(args[0], img)

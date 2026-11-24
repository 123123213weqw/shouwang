#!/usr/bin/env python3
"""标题标志"守望"的白色剪影（assets/sprites/ui/title-logo.png）。

和原版一样是 1098×579 的画布，图形落在同一块范围里（x 52..1047，y 42..535），纯白、实心、不描边。
原版是手写的 "Ooqo."；新标志是站酷快乐体（游戏界面在用的字体）的"守望"两个字。

游戏里这张图缩得很小（zoom 0.31：一个纹理像素只有 0.31 个屏幕像素，整个标志 313×155 个屏幕像素），
所以两个字撑满原版的范围、笔画粗（80 个纹理像素左右 ≈ 25 个屏幕像素），字里不挖细的缝。
手写的不规则感来自三处，都很轻，免得笔画变形：
  1. 两个字各转一点角度、上下错开一点，像原版那几个大小位置都不太整齐的字母；
  2. 整个标志过一遍很平缓的弯曲（手写字的笔画不会是绝对直的）；
  3. 笔画的尖角抹圆一点。

用法: python3 -I title_logo.py [预览图的输出路径] [输出目录]
  不带参数就把 title-logo.png 写进工程并自检（tools/art/regen_all.sh 就是这么跑的）。
  给了预览图的路径就再出一张预览图；再给一个输出目录就写到那里，不写进工程。
  加上 --variants 时预览图里并排画出几种参数，用来挑（不写文件）。
只依赖 Pillow 和 numpy。
"""
import importlib.util
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def _doodle():
    spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FONT = os.path.join(ROOT, "assets/fonts/ZCOOLKuaiLe-Regular.ttf")
OUT_REL = "assets/sprites/ui/title-logo.png"      # 写出来的新图
ORIG_REL = "assets/sprites/ui/ooqo-title.png"     # 照着画的那张原版图（量好的数在 originals.json 里）
CANVAS = (1098, 579)
BOX = (52, 42, 995, 493)       # 原版图形的范围
ZOOM = 0.31                    # 游戏里一个纹理像素等于几个屏幕像素
SS = 3                         # 先按 3 倍大小画，最后缩回去，边缘是平滑的
ERODE_LEVEL = 215              # 收细时的门槛（见 draw）：白底黑边的图模糊 sigma 以后，原来边缘往里正好 sigma 的地方亮度是这个值
WHITE = (255, 255, 255)

# 定稿的参数。每个字：转多少度（逆时针为正，和 Pillow 的 rotate 一样）、相对大小、上下挪多少（纹理像素）。
# 守 的顶往右倒一点、望 的顶往左倒一点并且稍微抬高：像原版那串往右上翘的字母
STYLE = {
    "chars": [("守", -2.5, 1.00, 0), ("望", 2.0, 0.96, -8)],
    "clear": 50,        # 两个字之间最近的水平空隙（纹理像素）
    "hand": 12,         # 平缓弯曲的幅度（纹理像素）
    "thin": 7.0,        # 笔画每边收细多少（纹理像素）。字体原样是 80 粗，收细以后字里的空隙变大，才有余地抹圆
    "round": 7.0,       # 抹圆尖角的程度（纹理像素）
    "press": 4.0,       # 笔画粗细沿着字慢慢变的幅度（纹理像素，0 是不变）
    "seed": 5,
}


# ---------------------------------------------------------------- 字形

def glyph(ch, size):
    """把一个字写成 size 号的黑白图，裁到墨迹的范围。返回 (L 图, 字号)"""
    size = int(round(size))
    font = ImageFont.truetype(FONT, size)
    im = Image.new("L", (size * 2, size * 2), 0)
    ImageDraw.Draw(im).text((size, size), ch, font=font, fill=255, anchor="mm")
    box = im.point(lambda v: 255 if v >= 128 else 0).getbbox()
    return im.crop(box), size


def rotated(g, angle):
    """转一个角度，还是黑白的"""
    if abs(angle) < 0.01:
        return g
    pad = 4
    big = Image.new("L", (g.width + pad * 2, g.height + pad * 2), 0)
    big.paste(g, (pad, pad))
    big = big.rotate(angle, resample=Image.BICUBIC, expand=True)
    big = big.point(lambda v: 255 if v >= 128 else 0)
    return big.crop(big.getbbox())


def ink(g):
    return np.asarray(g) > 127


def clearance(a, b, gap):
    """b 放在 a 右边 gap 个像素处时，两个字之间最近的水平空隙（只在两个字都有墨迹的行上量）"""
    off = a.shape[1] + gap
    best = None
    h = max(a.shape[0], b.shape[0])
    for y in range(h):
        ra = a[y] if y < a.shape[0] else None
        rb = b[y] if y < b.shape[0] else None
        if ra is None or rb is None or not ra.any() or not rb.any():
            continue
        left = int(np.where(ra)[0].max())            # 左边这个字在这一行最靠右的墨迹
        right = int(np.where(rb)[0].min())           # 右边这个字在这一行最靠左的墨迹
        d = off + right - left - 1
        best = d if best is None else min(best, d)
    return best


# ---------------------------------------------------------------- 手写的味道

def soft_field(w, h, seed, scale=1.0):
    """一张很平缓的随机场，取值在 -1 到 1 之间：几个波长和字高差不多的正弦波叠起来"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rng = np.random.default_rng(seed)

    def wave(kx, ky):
        return np.sin(2 * math.pi * (kx * xx + ky * yy) / (h * scale) + rng.uniform(0, 2 * math.pi))

    return (wave(0.7, 0.45) + 0.5 * wave(-0.5, 1.1)) / 1.5


def hand_field(w, h, amp, seed):
    """手写的弯曲用到的位移场：每个点往 (dx, dy) 挪多少（像素）"""
    return amp * soft_field(w, h, seed), amp * soft_field(w, h, seed + 100)


def bend(img, dx, dy):
    """按位移场把 img 弯一下（双线性取样）"""
    a = np.asarray(img, dtype=np.float32)
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = np.clip(xx + dx, 0, w - 1.001)
    sy = np.clip(yy + dy, 0, h - 1.001)
    x0 = sx.astype(np.int32)
    y0 = sy.astype(np.int32)
    fx, fy = sx - x0, sy - y0
    out = (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x0 + 1] * fx * (1 - fy)
           + a[y0 + 1, x0] * (1 - fx) * fy + a[y0 + 1, x0 + 1] * fx * fy)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


def to_binary(img):
    return img.point(lambda v: 255 if v >= 128 else 0)


# ---------------------------------------------------------------- 整个标志

def _layout(style):
    """把两个字摆好。返回三张同样大小的黑白图：两个字都有的、只有 守 的、只有 望 的"""
    s = SS
    base = 1000.0 * BOX[3] / 842.0          # 守 在 1000 号字时高 842：先按"撑满高度"定字号
    parts = []
    for ch, angle, rel, dy in style["chars"]:
        g, _ = glyph(ch, base * rel * s)
        parts.append((rotated(g, angle), dy))
    # 两个字上下居中对齐（再按各自的 dy 挪），量出真实的水平空隙，凑到 style["clear"]
    (a, _), (b, _) = parts
    clear = clearance(ink(a), ink(b), 0)
    gap = int(round(style["clear"] * s)) - clear
    w = a.width + gap + b.width
    top = min(-p[1] for p in parts)
    h = max(p[0].height + p[1] for p in parts) - top
    pad = int(style["hand"] * s * 3) + 40
    sheets = [Image.new("L", (w + pad * 2, h + pad * 2), 0) for _ in range(3)]
    x = pad
    for n, (g, dy) in enumerate(parts):
        pos = (x, pad + (h - g.height) // 2 + dy * s - top)
        sheets[0].paste(g, pos)
        sheets[1 + n].paste(g, pos)
        x += g.width + gap
    return [to_binary(sh) for sh in sheets]


def _finish(sheet, style):
    """平缓的弯曲 → 笔画收细 → 抹圆尖角。返回黑白图"""
    # 平缓的弯曲
    amp = style["hand"] * SS
    dx, dy = hand_field(sheet.width, sheet.height, amp, style.get("seed", 5))
    sheet = to_binary(bend(sheet, dx, dy))
    # 笔画收细：先模糊，再用比一半高的门槛二值化，等于每边往里收缩大约一个模糊半径
    t = style.get("thin", 0) * SS
    if t > 0.2:
        sheet = sheet.filter(ImageFilter.GaussianBlur(t)).point(lambda v: 255 if v >= ERODE_LEVEL else 0)
    # 抹圆尖角。顺手让笔画的粗细沿着字慢慢变一点（像手写字的轻重）：
    # 模糊后的图上加减一张很平缓的场再二值化，边缘就跟着场起伏（在一半亮度的边上，离边缘 1 个像素亮度差 101/r）
    r = style["round"] * SS
    pr = style.get("press", 0) * SS
    if r > 0.2:
        blur = sheet.filter(ImageFilter.GaussianBlur(r))
        if pr > 0.2:
            blur = Image.fromarray(np.clip(np.asarray(blur, dtype=np.float32)
                                           + pr * 101.0 / r * soft_field(sheet.width, sheet.height, style.get("seed", 5) + 200, 0.6),
                                           0, 255).astype(np.uint8))
        sheet = to_binary(blur)
    return sheet


def draw(style=STYLE, only=None):
    """按参数画出高分辨率的透明度图（两个字 + 弯曲 + 收细 + 抹圆），已经缩成正好放进 BOX 的大小。返回 L 图。
    only 给 0 或 1 时只画 守 或者 望，位置和大小跟两个字一起画时一模一样（启动图要给两个字染不同颜色时用）"""
    layout = _layout(style)
    full, solo = layout[0], layout[1:]
    art = _finish(full, style)
    # 裁到墨迹的范围，等比缩到正好放进 BOX
    cb = art.getbbox()
    k = min(BOX[2] * SS / (cb[2] - cb[0]), BOX[3] * SS / (cb[3] - cb[1]))
    size = (max(1, round((cb[2] - cb[0]) * k)), max(1, round((cb[3] - cb[1]) * k)))
    if only is not None:
        art = _finish(solo[only], style)
    return art.crop(cb).resize(size, Image.LANCZOS)


def build(style=STYLE):
    """1098×579 的画布：图形居中放在 BOX 里，纯白"""
    art = draw(style)
    alpha = Image.new("L", (CANVAS[0] * SS, CANVAS[1] * SS), 0)
    x = (BOX[0] + (BOX[2] - art.width / SS) / 2) * SS
    y = (BOX[1] + (BOX[3] - art.height / SS) / 2) * SS
    alpha.paste(art, (round(x), round(y)))
    alpha = alpha.resize(CANVAS, Image.LANCZOS)
    img = Image.new("RGBA", CANVAS, WHITE + (0,))
    img.putalpha(alpha)
    return img


# ---------------------------------------------------------------- 预览和自检

def at_game_size(img, k=4, margin=16):
    """按游戏里的大小缩小（zoom 0.31），只留图形附近的一块，再放大 k 倍，放在标题页的底色上"""
    small = img.resize((max(1, round(img.width * ZOOM)), max(1, round(img.height * ZOOM))), Image.LANCZOS)
    x0, y0 = BOX[0] * ZOOM - margin, BOX[1] * ZOOM - margin
    crop = (max(0, round(x0)), max(0, round(y0)),
            min(small.width, round((BOX[0] + BOX[2]) * ZOOM + margin)), min(small.height, round((BOX[1] + BOX[3]) * ZOOM + margin)))
    small = small.crop(crop)
    big = small.resize((small.width * k, small.height * k), Image.NEAREST)
    t = Image.new("RGB", big.size, (0, 0, 0))
    t.paste(Image.new("RGB", big.size, (238, 240, 236)), (0, 0), big)
    return t


def preview(path, img, variants=None, k=4):
    """预览图：上面是全尺寸的新图和原版（各缩成一半），下面是游戏里的大小（放大 k 倍）的新图和原版。
    给了 variants（(名字, 参数) 的列表）时，每种参数另存一张图：<预览图去掉扩展名>_序号_名字.png"""
    try:
        font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 18)
    except OSError:
        font = ImageFont.load_default()
    doodle = _doodle()
    old = doodle.orig(ORIG_REL)                  # 原版的图不在手边（没设 SW_ORIG）时是 None，预览图里就没有"原版"那两格
    bg, fg = (28, 34, 52), (235, 235, 245)

    def flat(im):
        t = Image.new("RGB", im.size, (0, 0, 0))
        t.paste(im, (0, 0), im)
        return t

    def framed(name, tiles):
        tw = max(t.width for _, t in tiles) + 16
        th = max(t.height for _, t in tiles) + 44
        sheet = Image.new("RGB", (tw * len(tiles) + 8, th + 8), bg)
        d = ImageDraw.Draw(sheet)
        for i, (n, t) in enumerate(tiles):
            sheet.paste(t, (i * tw + 8, 38))
            d.text((i * tw + 8, 12), n, fill=fg, font=font)
        return sheet

    new_big = ("新图（一半大小）", flat(img).resize((img.width // 2, img.height // 2), Image.LANCZOS))
    old_big = ("原版（一半大小）", flat(old).resize((old.width // 2, old.height // 2), Image.LANCZOS)) if old is not None else None
    top = framed("", [new_big] + ([old_big] if old is not None else []))
    bottom = framed("", [("游戏里的大小 ×%d：新图" % k, at_game_size(img, k))]
                    + ([("游戏里的大小 ×%d：原版" % k, at_game_size(old, k))] if old is not None else []))
    sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height + 12), bg)
    sheet.paste(top, (0, 0))
    sheet.paste(bottom, (0, top.height + 12))
    sheet.save(path)
    print("预览图:", path, sheet.size)
    base = os.path.splitext(path)[0]
    for i, (name, v) in enumerate(variants or []):
        t = framed("", [(name, at_game_size(build(v), k))])
        out = "%s_%d_%s.png" % (base, i, name.replace(" ", "").replace("（", "(").replace("）", ")").replace("/", "-"))
        t.save(out)
        print("  变体:", out, t.size)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--variants" in sys.argv:

        def v(**kw):
            s = {k: (list(val) if isinstance(val, list) else val) for k, val in STYLE.items()}
            s.update(kw)
            return s

        flat = dict(chars=[("守", 0, 1.0, 0), ("望", 0, 0.97, 0)], hand=0, round=0)
        tilt = dict(chars=[("守", -3.0, 1.0, -2), ("望", 3.0, 0.96, 12)], hand=14)
        vs = [
            ("收细5", v(thin=5, round=5)),
            ("收细7", v()),
            ("收细9", v(thin=9, round=9)),
            ("收细7-轻重4", v(press=4)),
            ("收细7-轻重7", v(press=7)),
            ("收细7-转多一点", v(**tilt)),
            ("收细7-转多一点-轻重4", v(press=4, **tilt)),
            ("收细9-转多一点", v(thin=9, round=9, **tilt)),
        ]
        preview(args[0], build(), vs)
    else:
        img = build()
        if len(args) > 1:                              # 给了输出目录就写到那里，不写进工程
            os.makedirs(args[1], exist_ok=True)
            out = os.path.join(args[1], "title-logo.png")
        else:
            out = os.path.join(ROOT, OUT_REL)           # 不给输出目录就写进工程
        img.save(out)
        print("已写出", out, img.size)
        _doodle().check(out, OUT_REL, zoom=ZOOM, kind="2d", ref=ORIG_REL, name=OUT_REL)
        if args:
            preview(args[0], img)

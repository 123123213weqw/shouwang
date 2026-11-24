"""a1 组六个元素共用的小工具：几个形状的画法（尖顶水滴、花瓣、火苗）+ 预览图。

形状的画法都直接画在 doodle.Mask 上（第一个参数 b），坐标是各元素自己设计范围里的坐标，y 向下：
    drop(b, centre, w, h, deg)         尖顶水滴：下面是圆，上面收到一个尖
    petal(b, root, tip, w)             花瓣：从 root 长到 tip
    flame(b, x, w, h, waist, deg)      火苗：底下收成腰，中段鼓起来，上面一个尖

预览图：把新图和原版并排放大，再做"游戏里最小那种情况"的模拟。棋盘上的东西是 3D 的面片：画布 156×136 的贴图
按 zoom（一个纹理像素等于几个屏幕像素）缩小，竖直方向还要再乘 0.88 左右（面片是斜对着镜头的）。
显存里的贴图带多级贴图，但拿原版的实拍校准下来，游戏里看到的更接近直接缩小（边缘是硬的），
所以模拟用的是双线性缩小，再掺一点多级贴图的糊（soft）。显存的压缩和着色器的抖动模拟不了，真的算数还是要进游戏连拍。

用法（在自己的脚本里，python3 -I 不把脚本所在的目录放进搜索路径，只能按文件加载）：
    import importlib.util, os
    spec = importlib.util.spec_from_file_location("a1_kit", os.path.join(脚本所在目录, "a1_kit.py"))
    kit = importlib.util.module_from_spec(spec); spec.loader.exec_module(kit)
    doodle = kit.load_doodle()
    kit.sheet(输出路径, "assets/sprites/upgrades/fish.png", 新图, zoom=0.31)      # 新图是 PIL 的 RGBA 图

只依赖 Pillow、numpy 和标准库。
"""
import importlib.util
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
BG = (14, 22, 40)                 # 一格的底色
FRAME = (28, 34, 52)              # 整张预览图的底色
SQUASH = 0.88                     # 3D 面片斜对着镜头：竖直方向在屏幕上只剩这么多（实拍量的，0.85 到 0.90）


def load_kit():
    """从别的脚本里加载这个模块（python3 -I 不把脚本所在的目录放进搜索路径，只能按文件加载）"""
    spec = importlib.util.spec_from_file_location("a1_kit", os.path.join(HERE, "a1_kit.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_doodle():
    spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _font(size):
    for f in ("/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/PingFang.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def sim_alpha(img, zoom, squash=SQUASH, soft=0.25):
    """模拟游戏里的缩小：返回缩到屏幕大小的透明度图（L 模式）。
    soft 是"糊"的程度：0 是直接双线性缩小，1 是相邻两级多级贴图各半。拿原版的实拍校准过：
    游戏里看到的接近直接缩小（边缘是硬的，鱼眼睛是 3.5 个屏幕像素的清晰的点），这里默认比实拍略糊一点，留点余量"""
    a = img.convert("RGBA").split()[3]
    w, h = max(1, round(a.width * zoom)), max(1, round(a.height * zoom * squash))
    lvl = math.log2(1.0 / zoom) if zoom < 1 else 0.0
    lo = int(math.floor(lvl))
    frac = lvl - lo

    def mip(level):
        small = a
        for _ in range(level):
            small = small.resize((max(1, small.width // 2), max(1, small.height // 2)), Image.BOX)
        return small.resize((w, h), Image.BILINEAR)

    plain = a.resize((w, h), Image.BILINEAR)
    if soft <= 0 or lo == 0 or frac <= 0:
        return plain
    return Image.blend(plain, Image.blend(mip(lo), mip(lo + 1), frac), soft)


def tile(alpha, k, bg=BG):
    """透明度图放大 k 倍（最近邻），白色剪影放在深色底上"""
    big = alpha.resize((alpha.width * k, alpha.height * k), Image.NEAREST)
    t = Image.new("RGB", big.size, bg)
    t.paste(Image.new("RGB", big.size, (255, 255, 255)), (0, 0), big)
    return t


def sheet(out, rel, new=None, zoom=0.31, squash=SQUASH, title="", k=8, big=2.5):
    """预览图：原版 | 新图 | 原版按 zoom 缩小后的样子（放大 k 倍）| 新图同样缩小后的样子。
    rel 是工程里的相对路径；new 是新图（不给就只看原版）。
    zoom 是一个数，或者几个数组成的元组（都按 squash 压）；要单独指定某一档的竖直压缩（界面上的精灵是 1），
    就传一个列表，每一项写成 (zoom, squash)"""
    doodle = load_doodle()
    old = doodle.orig(rel)                   # 原版的图不在手边（没设 SW_ORIG）时是 None，预览图里就没有"原版"那几格
    if isinstance(zoom, (int, float)):
        zoom = (zoom,)
    items = [(z, squash) for z in zoom] if isinstance(zoom, tuple) else list(zoom)
    tiles = []
    for name, im in (("原版", old), ("新图", new)):
        if im is None:
            continue
        a = im.split()[3].crop(im.getbbox())
        s = min(big * (old or new).width / a.width, big * (old or new).height / a.height)
        a = a.resize((max(1, round(a.width * s)), max(1, round(a.height * s))), Image.LANCZOS)
        tiles.append(("%s %s" % (name, title or os.path.basename(rel)), tile(a, 1)))
    for z, sq in items:
        for name, im in (("原版", old), ("新图", new)):
            if im is None:
                continue
            tiles.append(("%s 模拟 ×%.2f%s" % (name, z, "" if abs(sq - SQUASH) < 0.01 else " 竖直×%.2f" % sq), tile(sim_alpha(im, z, sq), k)))
    f = _font(20)
    tw = max(t.width for _, t in tiles) + 16
    th = max(t.height for _, t in tiles) + 52
    n = len(tiles)
    sheet_im = Image.new("RGB", (tw * n + 8 * (n + 1), th + 16), FRAME)
    draw = ImageDraw.Draw(sheet_im)
    for i, (name, t) in enumerate(tiles):
        x = 8 + i * (tw + 8)
        draw.text((x + 8, 10), name, fill=(240, 240, 248), font=f)
        sheet_im.paste(t, (x + 8, 42))
    sheet_im.save(out)
    return sheet_im.size


# ---------------------------------------------------------------- 形状的画法（画在 doodle.Mask 上）

def drop(b, centre, w, h, deg=0.0):
    """尖顶水滴：centre 是下面那个圆的圆心，w 是宽，h 是从尖到圆底的高，deg 是尖偏离"正上方"的角度（顺时针为正）"""
    r = w / 2.0
    d = h - r
    beta = math.pi / 2 - math.asin(min(1.0, r / d))      # 切点偏离"正上方"的角度
    th = math.radians(deg)

    def rot(px, py):
        return (centre[0] + px * math.cos(th) - py * math.sin(th), centre[1] + px * math.sin(th) + py * math.cos(th))

    pts = [rot(0, -d)]
    t0, t1 = -math.pi / 2 + beta, 1.5 * math.pi - beta
    for i in range(49):
        t = t0 + (t1 - t0) * i / 48
        pts.append(rot(r * math.cos(t), r * math.sin(t)))
    b.polygon(pts)


def petal(b, root, tip, w):
    """一片从 root 长到 tip 的花瓣：根上是半径 w/2 的圆，收到 tip 这个尖"""
    dx, dy = tip[0] - root[0], tip[1] - root[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    drop(b, (root[0] + ux * w / 2, root[1] + uy * w / 2), w, length + w / 2, math.degrees(math.atan2(ux, -uy)))


def flame(b, x, w, h, waist, deg):
    """火苗：底下收成腰（宽 waist），中段鼓起来（最宽 w），上面是一个尖；尖在 (x, 0)，整个往右歪 deg 度"""
    th = math.radians(deg)

    def rot(px, py):
        return (x + px * math.cos(th) - py * math.sin(th), py * math.cos(th) + px * math.sin(th))

    pts = [(-waist / 2, h), (-w / 2, h * 0.6), (-w * 0.36, 10), (-w * 0.12, 1.0), (0, 0),
           (w * 0.12, 1.0), (w * 0.36, 10), (w / 2, h * 0.6), (waist / 2, h)]
    b.shape([(p[0], p[1], 1) if i == 4 else p for i, p in enumerate(rot(*q) for q in pts)])   # 顶点保持尖角


def lens(b, x0, y0, x1, y1, w, n=24):
    """梭形（两头尖的橄榄形）：长轴从 (x0, y0) 到 (x1, y1)，w 是中间最宽的地方"""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux                                     # 长轴的法线
    pts = []
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n, -1, -1)
        for i in rng:
            t = i / n
            half = w / 2 * math.sin(math.pi * t)
            pts.append((x0 + ux * length * t + nx * half * side, y0 + uy * length * t + ny * half * side))
    b.polygon(pts)


def superellipse(b, cx, cy, a, c, n, N=96):
    """超椭圆（"圆角的方块"，n 是 2 就是椭圆，越大越方）：中心 (cx, cy)，横向半径 a，竖直半径 c"""
    pts = []
    for i in range(N):
        t = 2 * math.pi * i / N
        u, v = math.cos(t), math.sin(t)
        pts.append((cx + a * math.copysign(abs(u) ** (2.0 / n), u), cy + c * math.copysign(abs(v) ** (2.0 / n), v)))
    b.polygon(pts)


def round_rect(b, x0, y0, x1, y1, r, n=10):
    """圆角矩形：四个角是半径 r 的圆弧（按点描出来的，角不会鼓出去）"""
    pts = []
    for ccx, ccy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((ccx + r * math.cos(a), ccy + r * math.sin(a)))
    b.polygon(pts)


def arc_handle(b, cx, ybase, R, t, foot):
    """提梁：以 (cx, ybase) 为圆心的半个圆环（外半径 R，线宽 t），两只脚从 ybase 往下伸到 ybase + foot。
    并进 b 里去。环里面的那块要等下面的东西（罐口、盒盖）接上来才围成洞"""
    k = b._b((0, 0, 1, 1))[2]                            # 放大倍数
    ring = type(b)(b.size[0] / k, b.size[1] / k)
    ring.ellipse((cx - R, ybase - R, cx + R, ybase + R))
    inner = type(ring)(ring.size[0] / k, ring.size[1] / k)
    ri = R - t
    inner.ellipse((cx - ri, ybase - ri, cx + ri, ybase + ri))
    inner.polygon([(cx - R - 2, ybase + 0.2), (cx + R + 2, ybase + 0.2), (cx + R + 2, ybase + R + 4), (cx - R - 2, ybase + R + 4)])
    ring.cut(inner)
    ring.polygon([(cx - R - 2, ybase + 0.2), (cx + R + 2, ybase + 0.2), (cx + R + 2, ybase + R + 4), (cx - R - 2, ybase + R + 4)], hole=True)
    for s in (-1, 1):
        ring.capsule((cx + s * (R - t / 2), ybase - t / 2), (cx + s * (R - t / 2), ybase + foot - t / 2), t)
    b.union(ring)

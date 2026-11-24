"""画白色剪影的工具库：新游戏的每个美术元素都照这个画法来。

画法和原版一样：纯白、实心、圆润的涂鸦形，不描边、不画明暗，细节用挖空的洞表示；颜色由游戏运行时乘上去。
每张图的画布尺寸、图形的位置和大小都从原版的图里量出来（量好的数存在同目录的 originals.json 里），新图等比缩进同一个范围里。

用法（在自己的脚本里）：
    import importlib.util, os
    spec = importlib.util.spec_from_file_location("doodle", os.path.join(工程根目录, "tools/art/doodle.py"))
    doodle = importlib.util.module_from_spec(spec); spec.loader.exec_module(doodle)

    d = doodle.Mask(118, 108)          # 在 w×h 的设计范围里画
    d.shape([(10, 10), (60, 4), (110, 10), ...])   # 过这些锚点的闭合光滑曲线；第三个数是 1 的锚点保持尖角
    d.ellipse(60, 60, 20, 16)          # 椭圆
    d.capsule((10, 90), (100, 20), 9)  # 两头是圆的线段
    d.arc(...)                         # 两头是圆的弧
    d.soften(1.5)                      # 把各个部分的接缝抹圆
    holes = doodle.Mask(118, 108); holes.ellipse(45, 50, 6, 7); d.cut(holes)   # 挖洞
    img = doodle.place(d.alpha(), (236, 248), doodle.orig_box("assets/sprites/characters/default.png"))
    img.save(os.path.join(工程根目录, "assets/sprites/characters/default.png"))

几条硬规矩（都是在游戏里实拍、再拿原版的 50 张图校准出来的）：
  1. 图形的画布大小必须和原版一模一样，图形落在原版图形的范围里（orig_box），位置和大小由它决定。
  2. 细节的大小按"屏幕像素"算，不是按纹理像素：1152×720 的画面上，不到 1.5 个屏幕像素的洞或间距一定会被缩图抹掉
     （不合格）；不到 3 个屏幕像素的要看连拍；不相连的几块之间还要留着色器的抖动（最多是画布在屏幕上宽度的 1.2%，
     界面上的 2D 精灵是 3.1%）。所以每个元素都要先查它自己的 zoom（一个纹理像素 = 几个屏幕像素），再 check(path, rel, zoom=...)。
     zoom 不是固定的：镜头会按棋盘大小拉远，棋盘越大、离镜头越远的格子上的东西越小。要拿最小的那个 zoom 来查
     （棋盘上最大的关卡是第 12 关"远巡"，call pad_adapter.gd debug_goto_level 12）。原版自己就很细、很近的地方，照原版的来。
  3. 只画剪影本身，不加背景、不加描边、不加阴影、不加原来没有的东西。
  4. 静态检查过了不算完：进游戏连拍 10 个相位（着色器的抖动一秒换 8 次、10 个相位一轮），放大了逐个看。
  5. 要像手画的。原版是拿粗头马克笔在绘图软件里画的：线是抖的、左右不一样、笔画的粗细在变。拿圆规尺子画出来的
     "图标"（正圆、正方、等宽的条、两边对称）放在原版的图旁边一看就是两套。所以：
     - 先看原版是怎么画的，照它的画法来（比如原版宝箱是鼓鼓的盖子和箱身、中间一条抖着的缝，不是三条横线）；
     - 画完过一遍手绘化 handdraw()（place() 默认会做，力度见 HAND；不能挪位置的图用 handdraw_inplace()）；
     - 构图本身板正的（左右对称的伞、正圆的铜钱）光靠手绘化救不回来，要改画法；
     - 自检里"对称程度"一条：新图不能比原版对称得多。
     全部图重新生成一遍用 tools/art/regen_all.sh。

原版图量出来的数（画布大小、图形的范围、对称程度这些）都存在同目录的 originals.json 里：重画和自检只用这些数就够了，
原版工程的图不用放在手边（它们是原作者的东西，不进这个仓库）。想在预览图里和新图并排对照原版，
就把 SW_ORIG 指到原版工程的 assets/ 目录；originals.json 缺了条目，用 tools/art/bake_originals.py 重新烘。
只依赖 Pillow 和 numpy。完整的例子见 watchman.py。
"""
import json
import math
import os
import zlib
from collections import deque

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

K = 8                                   # 先按 8 倍大小画，最后缩回去，边缘是平滑的
WHITE, BLACK = (255, 255, 255), (0, 0, 0)
HERE = os.path.dirname(os.path.abspath(__file__))
_DATA = os.path.join(HERE, "originals.json")
# 原版图量出来的数，按工程里的相对路径存（比如 assets/sprites/upgrades/fish.png）
ORIG = json.load(open(_DATA, encoding="utf-8")) if os.path.exists(_DATA) else {}
# 原版工程的 assets/ 目录，只在出预览图（和新图并排对照）时用；没设 SW_ORIG 就不看原版
REF = os.path.abspath(os.environ["SW_ORIG"]) if os.environ.get("SW_ORIG") else None


# ---------------------------------------------------------------- 曲线轮廓

def spline(points, samples=26):
    """过一串锚点画一条闭合的光滑曲线（Catmull-Rom 样条），返回曲线上的一串点。
    锚点写成 (x, y) 或 (x, y, 1)：第三个数是 1 的锚点保持尖角，不抹圆"""
    pts = [(p[0], p[1]) for p in points]
    sharp = [len(p) > 2 and p[2] for p in points]
    n = len(pts)
    out = []
    for i in range(n):
        a, b, c, d = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = b if sharp[i] else (b[0] + (c[0] - a[0]) / 6.0, b[1] + (c[1] - a[1]) / 6.0)
        c2 = c if sharp[(i + 1) % n] else (c[0] - (d[0] - b[0]) / 6.0, c[1] - (d[1] - b[1]) / 6.0)
        for s in range(samples):
            t = s / samples
            u = 1 - t
            out.append((u * u * u * b[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * c[0],
                        u * u * u * b[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * c[1]))
    return out


class Mask:
    """在 w×h 的设计范围里画一张剪影：实心部分画在 fill 上，要挖掉的洞画在 hole 上"""

    def __init__(self, w, h):
        self.size = (math.ceil(w * K), math.ceil(h * K))
        self.fill = self._blank()
        self.hole = self._blank()

    def _blank(self):
        return Image.new("L", self.size, 0)

    def _draw(self, hole):
        return ImageDraw.Draw(self.hole if hole else self.fill)

    @staticmethod
    def _b(box):
        return [v * K for v in box]

    def ellipse(self, box, hole=False):
        """椭圆，box 是 (x0, y0, x1, y1)"""
        self._draw(hole).ellipse(self._b(box), fill=255)

    def shape(self, points, hole=False):
        """过锚点的闭合光滑曲线"""
        self._draw(hole).polygon([(x * K, y * K) for x, y in spline(points)], fill=255)

    def polygon(self, points, hole=False):
        """直边的多边形"""
        self._draw(hole).polygon([(x * K, y * K) for x, y in points], fill=255)

    def _dot(self, d, x, y, w):
        d.ellipse([(x - w / 2) * K, (y - w / 2) * K, (x + w / 2) * K, (y + w / 2) * K], fill=255)

    def capsule(self, p0, p1, w, hole=False):
        """两头是圆的粗线段"""
        d = self._draw(hole)
        d.line([(p0[0] * K, p0[1] * K), (p1[0] * K, p1[1] * K)], fill=255, width=max(1, round(w * K)))
        self._dot(d, p0[0], p0[1], w)
        self._dot(d, p1[0], p1[1], w)

    def path(self, pts, w, hole=False):
        """圆角的折线"""
        d = self._draw(hole)
        d.line([(x * K, y * K) for x, y in pts], fill=255, width=max(1, round(w * K)), joint="curve")
        for x, y in (pts[0], pts[-1]):
            self._dot(d, x, y, w)

    def arc(self, box, a0, a1, w, hole=False):
        """两头是圆的弧线（角度和 ImageDraw.arc 一样：从三点钟方向起，顺时针）"""
        d = self._draw(hole)
        d.arc(self._b(box), a0, a1, fill=255, width=max(1, round(w * K)))
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        rx, ry = (box[2] - box[0]) / 2 - w / 2, (box[3] - box[1]) / 2 - w / 2
        for a in (a0, a1):
            t = math.radians(a)
            self._dot(d, cx + rx * math.cos(t), cy + ry * math.sin(t), w)

    @staticmethod
    def half_ellipse(w, h, keep):
        """一个只留上半（keep="top"）或者下半（keep="bottom"）的椭圆，切口是平的。返回的 Mask 画在 (0, 0) 起，
        用 add() 并到别的 Mask 里去"""
        d = Mask(w, h)
        d.ellipse((0, 0, w, h))
        if keep == "top":
            d.polygon([(-2, h / 2), (w + 2, h / 2), (w + 2, h + 2), (-2, h + 2)], hole=True)
        else:
            d.polygon([(-2, -2), (w + 2, -2), (w + 2, h / 2), (-2, h / 2)], hole=True)
        return d

    def add(self, x, y, other):
        """把另一张 Mask 的实心部分并进来，放在 (x, y) 这个位置"""
        self.fill.paste(other.fill, (round(x * K), round(y * K)), other.fill)

    def union(self, other):
        """并上另一张同样大小的 Mask 的实心部分"""
        self.fill = ImageChops.lighter(self.fill, other.fill)

    def cut(self, other):
        """挖掉另一张 Mask 的实心部分（当作洞）"""
        self.fill = ImageChops.subtract(self.fill, other.fill)

    def soften(self, r):
        """把接缝抹圆：模糊之后以一半为界"""
        self.fill = self.fill.filter(ImageFilter.GaussianBlur(r * K)).point(lambda v: 255 if v >= 128 else 0)
        self.hole = self.hole.filter(ImageFilter.GaussianBlur(r * K * 0.5)).point(lambda v: 255 if v >= 128 else 0)

    def alpha(self):
        """高分辨率的透明度图（实心部分减去 hole 上的洞）"""
        return ImageChops.subtract(self.fill, self.hole)


# ---------------------------------------------------------------- 手绘化：画完的剪影都要过一遍
# 原版的图是拿粗头马克笔在绘图软件里画的。规矩见 handdraw()。这里是默认的力度（None 表示不做）；
# 各个脚本可以在 place(..., hand={...}) 里按元素改，想原样输出就写 hand=0
HAND = dict(wobble=0.016, thick=0.02, tilt=2.5, squash=0.03, grain=0.0035)


def _smooth_field(size, cells, rng):
    """一张变化很慢的随机涨落图（0 到 1）：先随机几个格子，再放大抹平"""
    small = Image.fromarray((rng.random((cells + 1, cells + 1)) * 255).astype(np.uint8), "L")
    return np.asarray(small.resize(size, Image.BICUBIC)).astype(np.float32) / 255.0


def _shift_edges(img, radius, field, amount=0.9):
    """让边缘顺着一张涨落图局部外鼓或内收（最多 radius 像素）：先模糊再按高低不一的门限切回去。
    一条直边模糊后在门限 0.5 + d 处被切开，切点就落在边里 2 × d × radius 的地方"""
    if radius < 1:
        return img
    blurred = np.asarray(img.filter(ImageFilter.BoxBlur(radius))).astype(np.float32) / 255.0
    out = blurred > (0.5 + (field - 0.5) * amount)
    return Image.fromarray((out * 255).astype(np.uint8), "L")


def handdraw(alpha, seed=None, wobble=0.016, thick=0.02, tilt=1.5, squash=0.02, grain=0.0035):
    """把画好的剪影变成手绘的样子。原版的线是抖的、笔画有粗有细、整个略歪一点，这里照着做：
      1. 线抖：轮廓被一张变化很慢的随机位移场推来推去，最多推 wobble × 图形的短边；
      2. 笔画粗细在变：边缘沿着轮廓慢慢外鼓或者内收，最多 thick × 短边；
      3. 略歪：整体转一个小角度（最多 tilt 度，均匀随机），横竖各拉或压不超过 squash，
         再叠一层很细的毛边（grain）。
    alpha 是 Mask.alpha() 那样的高分辨率透明度图；返回一张更大的图（四周留了空白）。
    不给种子就按图的内容算，所以同一张图每次画出来一模一样。"""
    src = Image.fromarray(np.asarray(alpha), "L")
    box = src.getbbox()
    if box is None:
        return alpha
    short = min(box[2] - box[0], box[3] - box[1])        # 图形的短边（高分辨率像素）
    if seed is None:
        seed = zlib.crc32(np.asarray(alpha).tobytes())
    rng = np.random.default_rng(seed)
    m = int(short * (wobble + thick + 0.04)) + 8         # 四周留出余地：线要往外鼓，还要转角度
    src = ImageOps.expand(src, border=m, fill=0)
    W, H = src.size

    # 1. 线抖
    amp = wobble * short
    if amp >= 0.5:
        dx = (_smooth_field((W, H), 3, rng) - 0.5) * 2 * amp
        dy = (_smooth_field((W, H), 3, rng) - 0.5) * 2 * amp
        ys, xs = np.mgrid[0:H, 0:W]
        sx = np.clip(xs + dx, 0, W - 1.001)
        sy = np.clip(ys + dy, 0, H - 1.001)
        x0, y0 = sx.astype(np.int32), sy.astype(np.int32)
        fx, fy = sx - x0, sy - y0
        a = np.asarray(src).astype(np.float32) / 255.0
        warped = (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x0 + 1] * fx * (1 - fy)
                  + a[y0 + 1, x0] * (1 - fx) * fy + a[y0 + 1, x0 + 1] * fx * fy)
        src = Image.fromarray(((warped > 0.5) * 255).astype(np.uint8), "L")

    # 2. 笔画粗细在变
    src = _shift_edges(src, thick * short, _smooth_field(src.size, 4, rng))
    # 3. 毛边
    src = _shift_edges(src, grain * short * 2, _smooth_field(src.size, 12, rng), amount=0.7)

    # 4. 略歪
    if squash > 0:
        fx_, fy_ = 1 + (rng.random() * 2 - 1) * squash, 1 + (rng.random() * 2 - 1) * squash
        src = src.resize((max(1, round(W * fx_)), max(1, round(H * fy_))), Image.BILINEAR).point(lambda v: 255 if v >= 128 else 0)
    if tilt > 0:
        src = src.rotate((rng.random() * 2 - 1) * tilt, resample=Image.BILINEAR, fillcolor=0).point(lambda v: 255 if v >= 128 else 0)
    return src


def handdraw_inplace(alpha, turn=False, **kw):
    """手绘化，但图的大小不变、图形还留在原来的位置上（多出来的空白裁掉）。
    默认只做线抖和粗细变化，不转也不拉——给不能挪位置的图用，比如九宫格的底板和边框、格子顶面。
    turn=True 的话允许整体歪一点（绕图的中心转和拉），给四周留白够多的图用，比如角色的头"""
    kw = dict(kw)
    if not turn:
        kw["tilt"], kw["squash"] = 0, 0
    out = handdraw(alpha, **kw)
    m = (out.width - alpha.width) // 2
    return out.crop((m, m, m + alpha.width, m + alpha.height))


def place(alpha, canvas, box, rgb=WHITE, hand=None):
    """把高分辨率的透明度图等比缩进 box（x, y, 宽, 高）里、居中，放到 canvas 大小的画布上。
    默认先做一遍手绘化（力度见 HAND）；hand={...} 按元素改参数，hand=0 原样输出"""
    h = HAND if hand is None else hand
    if h:
        alpha = handdraw(alpha, **h)
    img = alpha.crop(alpha.getbbox())
    s = min(box[2] / img.width, box[3] / img.height)
    small = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    layer = Image.new("RGBA", small.size, rgb + (0,))
    layer.putalpha(small)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(layer, (round(box[0] + (box[2] - small.width) / 2), round(box[1] + (box[3] - small.height) / 2)))
    return out


def full(alpha, canvas, rgb=WHITE):
    """整张画布直接缩回原尺寸（画的时候已经按画布坐标摆好了）"""
    layer = Image.new("RGBA", canvas, rgb + (0,))
    layer.putalpha(alpha.resize(canvas, Image.LANCZOS))
    return layer


# ---------------------------------------------------------------- 原版的图：量好的数存在 originals.json 里

def _orig_entry(rel):
    e = ORIG.get(rel)
    if e is None:
        raise KeyError("%s 在 tools/art/originals.json 里没有记录。有原版工程的 assets/ 目录的话，用 tools/art/bake_originals.py 重新烘一遍" % rel)
    return e


def orig_size(rel):
    """原版图的画布大小：宽, 高"""
    return tuple(_orig_entry(rel)["size"])


def orig_box(rel):
    """原版图里图形的位置和大小：x, y, 宽, 高"""
    return tuple(_orig_entry(rel)["box"])


def orig_inner(rel, level=200):
    """原版图里环（边框）中间那块不实心的范围：x0, y0, x1, y1。中间是实心的返回 None"""
    v = _orig_entry(rel).get("inner")
    return tuple(v) if v else None


def orig_measure(rel):
    """原版图的 measure() 结果（字典）"""
    return dict(_orig_entry(rel)["measure"])


def has_orig(rel):
    """原版的图在不在手边（设了 SW_ORIG 才可能在）"""
    return REF is not None and os.path.exists(os.path.join(REF, rel))


def orig(rel):
    """原版的图（rel 是工程里的相对路径，比如 assets/sprites/upgrades/fish.png）；不在手边返回 None"""
    return Image.open(os.path.join(REF, rel)).convert("RGBA") if has_orig(rel) else None


# ---------------------------------------------------------------- 自检：画完必须过一遍

def _bfs(mask, seeds):
    """从 seeds 出发把 mask 里相连的点都找出来（4 邻接），返回同样形状的布尔数组"""
    h, w = mask.shape
    out = np.zeros_like(mask, dtype=bool)
    q = deque(seeds)
    for y, x in seeds:
        out[y, x] = True
    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return out


def _components(mask):
    """连通块的列表（4 邻接），大的在前。mask 是二维布尔数组"""
    comps = []
    left = mask.copy()
    while left.any():
        ys, xs = np.where(left)
        c = _bfs(mask, [(int(ys[0]), int(xs[0]))])
        comps.append(c)
        left &= ~c
    comps.sort(key=lambda m: -int(m.sum()))
    return comps


def _filter(mask, size, op):
    """对布尔数组做最小值（腐蚀）或最大值（膨胀）滤波"""
    im = Image.fromarray((mask * 255).astype(np.uint8), "L")
    return np.asarray(im.filter(op(size))) > 127


def _erode(mask, width):
    """腐蚀：只留下周围 width×width 都是实心的那些点（width 是奇数）"""
    return _filter(mask, width, ImageFilter.MinFilter)


def _grow(mask, n):
    """膨胀 n 步（每步往外长一个像素，斜着也算）"""
    im = Image.fromarray((mask * 255).astype(np.uint8), "L")
    for _ in range(n):
        im = im.filter(ImageFilter.MaxFilter(3))
    return np.asarray(im) > 127


def _width(mask):
    """一块图形最宽的地方有多宽：反复用 3×3 腐蚀、数能腐蚀几次（结果都是奇数，3 表示宽度在 3 到 4 之间）。
    量的是能塞进去的最大的正方形的边长，斜着的细条按它的竖直/水平厚度算"""
    ys, xs = np.where(mask)
    # 四周先垫一圈 0 再腐蚀。不垫的话，正好是矩形的块（比如方头的槽）四边都顶在图的边上，腐蚀不动，会一直循环
    cur = np.pad(mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1], 1)
    width = 1
    while width < 4000:
        nxt = _erode(cur, 3)
        if not nxt.any():
            return width
        cur = nxt
        width += 2
    return width


def _min_gap(comps, limit=60):
    """几块不相连的图形之间，最近的兩块隔多少像素（都离得很远就返回 limit）"""
    best = limit
    # 只让每一块自己往外长，长到碰到别的块（原地不动的）为止，长了几步就是真实的间距。
    # （早先的写法是几块同时往外长、在中间相遇就记数，量出来的只有真实间距的一半）
    ys, xs = np.where(comps[0])
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    for c in comps[1:]:
        ys, xs = np.where(c)
        x0, x1, y0, y1 = min(x0, xs.min()), max(x1, xs.max()), min(y0, ys.min()), max(y1, ys.max())
    pad = min(best, limit) + 1
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(comps[0].shape[1], x1 + pad + 1), min(comps[0].shape[0], y1 + pad + 1)
    solid = [c[y0:y1, x0:x1] for c in comps]
    grown = [s.copy() for s in solid]
    for d in range(1, min(best, limit) + 1):
        grown = [_grow(g, 1) for g in grown]
        for i in range(len(grown)):
            for j in range(len(grown)):
                if i != j and (grown[i] & solid[j]).any():
                    return d
    return best


def measure(img, level=127):
    """量一张剪影图（Pillow 的图），返回一个字典：
      box        图形的范围 x, y, 宽, 高
      area       实心的像素数
      thin       实心部分里"周围 9×9 不全是实心"的点占多少（0 到 1，越大表示越细碎）
      comps      不相连的部分有几块
      gap        最近的两块之间隔多少像素（只有一块时是 None）
      holes      洞有几个（图形里面透明的地方）
      hole_min   最窄的洞有多宽（没有洞时是 None）
      asym       对称程度：沿重心竖轴翻转后和自己差多少（0 = 完全对称，手绘的图一般在 0.05 以上）
      tint       不透明的像素里最暗的通道值（纯白的话是 255）"""
    im = img.convert("RGBA")
    arr = np.asarray(im)
    a = arr[..., 3] > level
    out = {"box": None, "area": int(a.sum()), "thin": 0.0, "asym": 0.0, "comps": 0, "gap": None, "holes": 0, "hole_min": None, "tint": None}
    if not a.any():
        return out
    ys, xs = np.where(a)
    out["box"] = (int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1))
    solid = arr[..., :3][a]
    out["tint"] = int(solid.min())
    out["thin"] = float(1 - _erode(a, 9).sum() / a.sum())
    # 对称程度：沿图形重心那条竖轴把图翻过来和自己比，差得越少越对称。手绘的图左右总不一样，
    # 矢量图（正圆、等宽的条）几乎完全对称——0.02 以下就太板正了
    nb0 = out["box"]
    cx = xs.mean()
    half = int(max(cx - nb0[0], nb0[0] + nb0[2] - cx)) + 2
    canvas = np.zeros((nb0[3], half * 2), dtype=bool)
    canvas[:, half - int(round(cx - nb0[0])):half - int(round(cx - nb0[0])) + nb0[2]] = a[nb0[1]:nb0[1] + nb0[3], nb0[0]:nb0[0] + nb0[2]]
    out["asym"] = float((canvas ^ canvas[:, ::-1]).sum() / max(1, canvas.sum()))
    comps = _components(a)
    out["comps"] = len(comps)
    if len(comps) > 1:
        out["gap"] = _min_gap(comps)
    # 洞 = 图形里面透明的地方：从画布四边把"外面"灌满，剩下没灌到的透明处才是洞
    h, w = a.shape
    edge = np.zeros_like(a)
    edge[0, :] = edge[-1, :] = True
    edge[:, 0] = edge[:, -1] = True
    outside = _bfs(~a, [(int(y), int(x)) for y, x in zip(*np.where(edge & ~a))])
    holes = _components(~a & ~outside)
    out["holes"] = len(holes)
    if holes:
        # 只有几个像素的小点不算（缩图以后线条的接头处偶尔会圈出一两个像素的空点，那不是画出来的细节）
        real = [hm for hm in holes if int(hm.sum()) >= 6]
        out["hole_min"] = min(_width(hm) for hm in real) if real else None
    return out


# 细节最小尺寸按屏幕像素算（1152×720 的画面上实拍定的；画面越大越宽松）
HOLE_MIN, HOLE_GOOD = 1.5, 3.0          # 洞：不到 1.5 个屏幕像素一定会被填上（不合格）；不到 3 个要连拍确认
GAP_MIN, GAP_GOOD = 1.5, 3.0            # 不相连的几块之间：不到 1.5 个屏幕像素一定会粘上；不到 3 个加抖动要连拍确认
WOBBLE = {"3d": 0.012, "2d": 0.031}     # 着色器的抖动：相邻两块最多错开画布在屏幕上宽度的多少（棋盘上的精灵 / 界面上的精灵）


def check(path, rel, zoom=None, kind="3d", ref=None, name=None):
    """检查一张画好的图，返回 True 表示没有不合格的地方，并把量到的数都打印出来。
      path         新图的路径
      rel          新图在工程里的相对路径（也是默认的参照原版图）
      zoom         这张图在 1152×720 的画面上，一个纹理像素等于几个屏幕像素（游戏里 call pad_adapter.gd debug_rects 查）。
                   不给的话只和原版比，不判断洞和间距够不够
      kind         "3d"（棋盘上的精灵，wobbly.gdshader）或者 "2d"（界面上的精灵，canvas_wobbly_shader.gdshader）
      ref          当参照的原版图的相对路径，新加的文件要指出来：default_body.png 是照着原版的 body.png 画的，
                   就写 ref="assets/sprites/characters/body.png"
    打印出来的 [不合格] 必须改掉；[要看一眼] 的地方要到游戏的连拍里确认它看得出来"""
    new = Image.open(path).convert("RGBA")
    osize, mo = orig_size(ref or rel), orig_measure(ref or rel)
    what = name or rel
    ok = True
    if new.size != osize:
        print("  [错误] %s：画布 %s，原版是 %s。画布大小必须一样" % (what, new.size, osize))
        return False
    mn = measure(new)
    if mn["box"] is None:
        print("  [错误] %s：整张图都是透明的" % what)
        return False
    nb, ob = mn["box"], mo["box"]
    print("  %s（画布 %dx%d%s）" % (what, new.width, new.height, "，zoom %s" % zoom if zoom is not None else ""))
    print("    图形的范围：原版 %dx%d@(x%d,y%d)，新图 %dx%d@(x%d,y%d)" % (ob[2], ob[3], ob[0], ob[1], nb[2], nb[3], nb[0], nb[1]))
    # 新图的图形不能超出原版的范围太多（3 像素以内），也不该比原版小太多
    if nb[0] < ob[0] - 3 or nb[1] < ob[1] - 3 or nb[0] + nb[2] > ob[0] + ob[2] + 3 or nb[1] + nb[3] > ob[1] + ob[3] + 3:
        print("    [不合格] 图形超出了原版的范围（游戏里会压到别的东西上）"); ok = False
    if nb[2] < ob[2] * 0.6 or nb[3] < ob[3] * 0.6:
        print("    [不合格] 图形比原版小太多（宽 %d%%，高 %d%%）" % (100 * nb[2] / ob[2], 100 * nb[3] / ob[3])); ok = False
    elif nb[2] < ob[2] * 0.8 or nb[3] < ob[3] * 0.8:
        print("    [要看一眼] 图形比原版的小（宽 %d%%，高 %d%%）。原版是撑满这个范围的，新图太小的话在游戏里会显得小" % (
            100 * nb[2] / ob[2], 100 * nb[3] / ob[3]))
    # 颜色只能是纯白
    if mn["tint"] < 250:
        print("    [不合格] 有不是纯白的不透明像素（最暗的通道是 %d）" % mn["tint"]); ok = False
    # 细碎程度和原版比
    print("    细碎程度（离边缘不到 4 像素的实心部分占多少）：原版 %.0f%%，新图 %.0f%%" % (100 * mo["thin"], 100 * mn["thin"]))
    if mn["thin"] > max(mo["thin"] * 1.5, mo["thin"] + 0.10):
        print("    [不合格] 新图比原版细碎得多：细的地方在游戏里会被抹掉或者抖散"); ok = False
    px = (lambda v: " ≈ %.1f 屏幕像素" % (v * zoom)) if zoom else (lambda v: "")
    # 手绘感：不能比原版对称得多
    print("    对称程度（0 = 左右完全一样）：原版 %.3f，新图 %.3f" % (mo["asym"], mn["asym"]))
    if mn["asym"] < 0.02 and mn["asym"] < mo["asym"] * 0.45:
        print("    [不合格] 太对称、太板正：原版是手绘的，左右不一样"); ok = False
    elif mn["asym"] < mo["asym"] * 0.6 and mo["asym"] - mn["asym"] > 0.03:
        print("    [要看一眼] 比原版规整，看看是不是丢了手绘的感觉")
    # 不相连的几块之间
    if mn["comps"] > 1:
        print("    不相连的部分：%d 块，最近的兩块隔 %d 像素%s（原版 %d 块，%s）" % (
            mn["comps"], mn["gap"], px(mn["gap"]), mo["comps"],
            "最近的隔 %d 像素" % mo["gap"] if mo["gap"] is not None else "只有一块"))
        if mo["gap"] is not None and mn["gap"] >= mo["gap"]:
            pass                                   # 原版也挨得这么近，游戏里是分得开的
        elif zoom:
            wobble = WOBBLE[kind] * new.width * zoom
            if mn["gap"] * zoom < GAP_MIN:
                print("    [不合格] 兩块之间只有 %.1f 屏幕像素：游戏里它们会粘在一起" % (mn["gap"] * zoom)); ok = False
            elif mn["gap"] * zoom < GAP_GOOD + wobble:
                print("    [要看一眼] 兩块之间只有 %.1f 屏幕像素（抖动最多 %.1f）：到连拍里确认 10 个相位都没粘上" % (mn["gap"] * zoom, wobble))
    # 洞
    if mn["holes"]:
        print("    挖空的洞：%d 个，最窄的 %d 像素%s（原版 %d 个，%s）" % (
            mn["holes"], mn["hole_min"], px(mn["hole_min"]), mo["holes"],
            "最窄的 %d 像素" % mo["hole_min"] if mo["hole_min"] is not None else "没有洞"))
        if mo["hole_min"] is not None and mn["hole_min"] >= mo["hole_min"]:
            pass                                   # 原版的洞也一样窄，游戏里看得出来
        elif zoom:
            if (mn["hole_min"] + 2) * zoom < HOLE_MIN:
                print("    [不合格] 有不到 %.0f 屏幕像素宽的洞：游戏里缩图以后会被填上" % HOLE_MIN); ok = False
            elif mn["hole_min"] * zoom < HOLE_GOOD:
                print("    [要看一眼] 有 %.1f 屏幕像素宽的细洞：到连拍里确认它每个相位都看得出来" % (mn["hole_min"] * zoom))
    print("    %s" % ("合格" if ok else "不合格"))
    return ok


def review_sheet(out, items, cell=260, cols=None):
    """出一张对比图：每个元素三小格——原版、新图、叠在一起（红 = 原版，绿 = 新图，重合处发黄）。
    items 是 (标题, 新图的路径, 工程里的相对路径) 的列表。原版的图不在手边（没设 SW_ORIG）就只有新图一小格"""
    n = len(items)
    cols = cols or n
    rows = (n + cols - 1) // cols
    bg = (14, 22, 40)
    try:
        from PIL import ImageFont
        font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 15)
    except OSError:
        font = ImageFont.load_default()
    from PIL import ImageDraw
    per = 3 if all(has_orig(rel) for _, _, rel in items) else 1
    sheet = Image.new("RGB", ((cell * per + 24) * cols + 12, (cell + 40) * rows + 12), (28, 34, 52))
    draw = ImageDraw.Draw(sheet)
    for i, (title, path, rel) in enumerate(items):
        x0, y0 = 12 + (i % cols) * (cell * per + 24), 12 + (i // cols) * (cell + 40)
        old, new = orig(rel), Image.open(path).convert("RGBA")
        w, h = (old or new).size
        k = min((cell - 6) / w, (cell - 6) / h)
        size = (max(1, round(w * k)), max(1, round(h * k)))
        a_new = new.split()[3].resize(size, Image.BILINEAR)
        tiles = []
        if old is not None:
            a_old = old.split()[3].resize(size, Image.BILINEAR)
            for a in (a_old, a_new):
                t = Image.new("RGB", size, bg)
                t.paste(Image.new("RGB", size, WHITE), (0, 0), a)
                tiles.append(t)
            overlap = Image.new("RGB", size, (0, 0, 0))
            overlap.paste(Image.new("RGB", size, (255, 70, 70)), (0, 0), a_old)
            overlap.paste(Image.new("RGB", size, (90, 255, 110)), (0, 0), a_new)
            tiles.append(overlap)
        else:
            t = Image.new("RGB", size, bg)
            t.paste(Image.new("RGB", size, WHITE), (0, 0), a_new)
            tiles.append(t)
        for j, tile in enumerate(tiles):
            sheet.paste(tile, (x0 + j * (cell + 6) + (cell - size[0]) // 2, y0 + (cell - size[1]) // 2))
        draw.text((x0 + 2, y0 + cell + 6), title[:40], fill=(235, 235, 245), font=font)
    sheet.save(out)
    return sheet.size

#!/usr/bin/env python3
"""守夜人（默认角色）的白色剪影：一张头、一张身子。

和原版的角色图一样：236×248 的画布，图形落在同一块范围里（x 59..177，y 70..178），纯白、实心，
细节用挖空的洞表示。原版是"白色的头 + 下面一份染了颜色的同一张图当身子"；新角色的身子是另一张图
（蓑衣），放在同一个位置上——位置、大小、缩放、染色都不变。两张图在游戏里上下相接：
头那张的图形范围是 y 70..178，身子那张往下挪 105 像素，所以整个人是 118 宽、213 高。

用法: python3 -I watchman.py [预览图的输出路径] [输出目录]
  不带参数就把 default.png（头）和 default_body.png（身子）写进工程（tools/art/regen_all.sh 就是这么跑的）。
  给了预览图的路径就再出一张预览图；再给一个输出目录就写到那里，不写进工程。
只依赖 Pillow。
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CANVAS = (236, 248)
BOX = (59, 70, 118, 108)        # 原版 default.png（头）里图形的范围
BODY_BOX = (66, 56, 105, 154)   # 原版 body.png（身子）里图形的范围
SHIFT = 102                     # 游戏里身子的那张图和头的图错开多少行（两个精灵在场景里的高度差换算过来的）
BODY_X0 = BODY_BOX[0] - BOX[0]  # 身子的图形范围换到"整个人"的坐标里：x 从 7 起、y 从 88 起
BODY_Y0 = BODY_BOX[1] - BOX[1] + SHIFT
K = 8                       # 先按 8 倍大小画，最后缩回去，边缘是平滑的
WHITE = (255, 255, 255)
BODY_COLOR = (52, 78, 128)  # 预览时给身子染的颜色（游戏里是关卡的颜色压暗）
H = BODY_Y0 + BODY_BOX[3]   # 整个人的高度


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
    """一张高分辨率的透明度图（118 宽、H 高）：往上加实心的形状，或者挖洞"""

    def __init__(self):
        self.img = Image.new("L", (math.ceil(118 * K), math.ceil(H * K)), 0)

    def _fill(self, pts, value):
        ImageDraw.Draw(self.img).polygon([(x * K, y * K) for x, y in pts], fill=value)

    def shape(self, points, value=255):
        self._fill(spline(points), value)

    def ellipse(self, cx, cy, rx, ry, value=255):
        self._fill([(cx + rx * math.cos(2 * math.pi * i / 64), cy + ry * math.sin(2 * math.pi * i / 64)) for i in range(64)], value)

    def soften(self, r):
        """把接缝抹圆：模糊之后以一半为界"""
        self.img = self.img.filter(ImageFilter.GaussianBlur(r * K)).point(lambda v: 255 if v >= 128 else 0)

    def union(self, other):
        self.img = ImageChops.lighter(self.img, other.img)

    def cut(self, other):
        self.img = ImageChops.subtract(self.img, other.img)


# ---------------------------------------------------------------- 各个部分（坐标是整个人上的位置，y 向下）
# 上面 0..108 是头那张图的图形范围，下面 105..213 是身子那张图的图形范围

def hat():
    """斗笠：笠顶是个小圆尖，坡面往里凹一点，笠沿又平又宽，明显伸出脸的两边，两头是有点厚的小尖"""
    m = Mask()
    m.shape([
        (54, 2),           # 笠顶
        (61, 5),
        (73, 18),
        (85, 31),
        (96, 41),
        (105, 49),
        (117, 57, 1),      # 右边笠沿的尖
        (106, 60),
        (94, 57),
        (74, 55),
        (54, 55),          # 笠沿中间
        (34, 55),
        (14, 57),
        (1, 58, 1),        # 左边笠沿的尖
        (3, 49),
        (12, 41),
        (23, 31),
        (35, 18),
        (47, 5),
    ])
    return m


def face():
    """脸：接近圆形，腮帮子稍微宽一点，下面接一小段脖子"""
    m = Mask()
    m.shape([
        (54, 30),
        (75, 37),
        (85, 58),
        (82, 82),
        (70, 97),
        (54, 101),
        (38, 97),
        (25, 82),
        (21, 58),
        (33, 37),
    ])
    m.shape([(45, 92), (63, 92), (63, 114), (45, 114)])     # 脖子（到头的图形范围底边为止）
    return m


def eyes():
    m = Mask()
    for x in (41, 67):
        m.ellipse(x, 67, 6.2, 7.0)
    return m


def lantern():
    """手里的灯笼：圆灯身、上下的灯口。离脸和斗笠都留出十个像素左右——游戏里的着色器会让整张图
    的取样位置偏移五六像素，挨得太近的东西会粘在一起"""
    m = Mask()
    m.ellipse(106, 86, 11, 14)                                          # 灯身
    m.shape([(101, 65), (111, 65), (111, 72), (101, 72)])               # 上面的灯口
    m.shape([(101, 97), (111, 97), (111, 103), (101, 103)])             # 下面的灯口
    return m


def lantern_slit():
    """灯身上挖一条竖缝（要够宽，太细了会被着色器的偏移盖住）"""
    m = Mask()
    m.shape([(104, 78), (108, 78), (108, 94), (104, 94)])
    return m


def cape():
    """蓑衣：肩膀又宽又高、紧收在下巴底下（下巴底下不留空，免得格子上的装饰从空隙里透出来），
    往下张开的钟形，一直垂到脚边，下摆是一圈参差的短草尖"""
    m = Mask()
    m.shape([
        (31, 98),          # 左肩
        (20, 106),
        (12, 124),
        (7, 150),
        (5, 184),
        (4, 238, 1),       # 下摆的草尖，一长一短交替
        (14, 233),
        (16, 242, 1),
        (28, 234),
        (33, 243, 1),
        (44, 234),
        (50, 243, 1),
        (60, 234),
        (66, 243, 1),
        (77, 234),
        (82, 242, 1),
        (94, 233),
        (104, 238, 1),
        (103, 184),
        (99, 150),
        (94, 124),
        (86, 106),
        (79, 98),          # 右肩
    ])
    return m


def shoulder():
    """抬起来的右肩和上臂：一团实心的。主角站着不动时，跳跃拖尾的白色粒子聚在胸口偏右、
    画在身子的后面（x 75~103、y 101~121 那一带），原版的身子是实心的，把它们挡住了；
    这里如果不填实，白点就会从胳膊下面的空隙里露出来"""
    m = Mask()
    m.shape([
        (73, 104),
        (82, 98),
        (93, 99),
        (103, 105),
        (105, 115),
        (99, 125),
        (88, 130),
        (76, 126),
        (71, 115),
    ])
    return m


def arm():
    """右臂从右肩伸出来，往上托着灯笼"""
    m = Mask()
    m.shape([
        (84, 118),
        (93, 110),
        (101, 104),
        (106, 105),
        (106, 109),
        (102, 111),
        (97, 115),
        (92, 122),
        (88, 128),
    ])
    return m


def straw_lines():
    """蓑衣下摆上的草纹和腰带：三道粗一点的竖缝，下面一条横的腰带。都画得比较粗，免得被着色器的偏移盖住。
    胸口不挖任何缝：主角站着不动的时候，跳跃拖尾的白色粒子是从胸口往上飘的一列（x 56~90、y 123~170），
    画在身子的后面，原版的实心身子把它们挡住了，胸口有缝就会露出来"""
    m = Mask()
    for x0, x1 in ((40, 36), (54, 54), (68, 72)):
        m.shape([(x0 - 3, 194), (x1 - 3, 220), (x1 + 3, 220), (x0 + 3, 194)])
    m.shape([(22, 226), (86, 226), (86, 232), (22, 232)])
    return m


def figure():
    """返回两张高分辨率的透明度图：头（0..108）、身子（105..213）"""
    head = hat()
    head.union(face())
    head.soften(1.0)
    lam = lantern()
    lam.soften(0.7)
    slit = lantern_slit()
    slit.soften(0.3)
    lam.cut(slit)
    head.union(lam)
    e = eyes()
    e.soften(0.4)
    head.cut(e)

    body = cape()
    body.union(shoulder())
    body.union(arm())
    body.soften(1.0)
    lines = straw_lines()
    lines.soften(0.3)
    body.cut(lines)

    w = head.img.width
    head_a = head.img.crop((0, 0, w, round(BOX[3] * K)))
    body_a = body.img.crop((round(BODY_X0 * K), round(BODY_Y0 * K), round((BODY_X0 + BODY_BOX[2]) * K), round(H * K)))
    return head_a, body_a


def to_canvas(alpha, box, rgb=WHITE):
    """透明度图 → 236×248 的画布，图形缩到 box 的大小、放在 box 的位置上"""
    art = Image.new("RGBA", box[2:], rgb + (0,))
    art.putalpha(alpha.resize((box[2], box[3]), Image.LANCZOS))
    im = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    im.alpha_composite(art, box[:2])
    return im


def preview(path, head_tex, body_tex):
    """预览图：左边是照游戏里的摆法叠出来的新角色和原版角色，右边是头、身子两张图的放大图"""
    # 原版的角色图：只在出预览图时对照用。设了 SW_ORIG（原版工程里放着 assets/ 的目录）才看，没设就没有"原版"那一张
    ref_dir = os.environ.get("SW_ORIG")
    old = Image.open(os.path.join(ref_dir, "assets/sprites/characters/default.png")).convert("RGBA") if ref_dir else None
    bg = (14, 22, 40)
    scale = 3

    def frame(im):
        t = Image.new("RGB", (im.width + 24, im.height + 24), bg)
        t.paste(im, (12, 12))
        return t

    def stacked(head, body, tint):
        top, bottom = BOX[1] - 12, BODY_BOX[1] + BODY_BOX[3] + SHIFT + 6
        x0, x1 = BOX[0] - 16, BOX[0] + BOX[2] + 16
        w, h = (x1 - x0) * scale, (bottom - top) * scale
        im = Image.new("RGB", (w, h), bg)
        # 身子画在后面，头画在前面（和游戏里一样）
        for tex, dy, color in ((body, SHIFT, tint), (head, 0, None)):
            a = tex.split()[3].crop((x0, top, x1, bottom)).resize((w, h), Image.LANCZOS)
            layer = Image.new("RGBA", (w, h), (color or WHITE) + (0,))
            layer.putalpha(a)
            im.paste(layer, (0, dy * scale), layer)
        return im

    new, orig = frame(stacked(head_tex, body_tex, BODY_COLOR)), frame(stacked(old, old, BODY_COLOR)) if old else None
    tiles = []
    for tex, box in ((head_tex, BOX), (body_tex, BODY_BOX)):
        crop = tex.crop((box[0] - 10, box[1] - 10, box[0] + box[2] + 10, box[1] + box[3] + 10))
        crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
        tile = Image.new("RGB", crop.size, bg)
        tile.paste(crop, (0, 0), crop)
        tiles.append(frame(tile))
    width = new.width + (orig.width + 16 if orig else 0) + tiles[0].width + 5 * 16
    height = max(new.height, tiles[0].height + tiles[1].height + 16) + 32
    sheet = Image.new("RGB", (width, height), (28, 34, 52))
    x = 16
    for t in (new, orig, tiles[0]):
        if t is not None:
            sheet.paste(t, (x, 16))
            x += t.width + 16
    sheet.paste(tiles[1], (x, 16))
    sheet.save(path)


if __name__ == "__main__":
    head_a, body_a = figure()
    head_tex, body_tex = to_canvas(head_a, BOX), to_canvas(body_a, BODY_BOX)
    if len(sys.argv) > 2:                             # 给了输出目录就写到那里，不写进工程
        os.makedirs(sys.argv[2], exist_ok=True)
        out_dir = sys.argv[2]
    else:
        out_dir = os.path.join(ROOT, "assets/sprites/characters")      # 不给输出目录就写进工程
    head_tex.save(os.path.join(out_dir, "default.png"))
    body_tex.save(os.path.join(out_dir, "default_body.png"))
    print("已写出 default.png 和 default_body.png 到", out_dir)
    if len(sys.argv) > 1:
        preview(sys.argv[1], head_tex, body_tex)
        print("预览图:", sys.argv[1])

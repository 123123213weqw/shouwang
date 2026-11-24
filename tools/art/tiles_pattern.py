#!/usr/bin/env python3
"""标题页、选人页的背景花纹和过关转场的图案（assets/sprites/tilesarray.png）。

画布和原版一样是 1092×136：7 格横着排，每格 156×136，带透明通道。原版是 7 个小涂鸦（几条鱼、螺旋、小船之类）；
新的是 7 个水乡、巡游的白色剪影。每格的图形落在原版那一格的同一块范围里（BOXES，从原版的图里量出来的），
纯白、实心，细节用挖空的洞和缺口表示，颜色由着色器乘上去（石绿到朱砂之间，压得很暗）。

着色器（shaders/scene_transition.gdshader）是怎么用这张图的，决定了细节能画多细：
  * 整张图铺满屏幕，每格在 1152×720 的画面上是 58.48×56.86 个屏幕像素；格里的贴图只占左上角一块，
    被缩成 39.6×44.2 个屏幕像素，而且横竖缩得不一样：横向一个纹理像素 = 0.254 个屏幕像素，
    纵向 = 0.325 个。所以要在纹理里画成 1.28:1 的椭圆，屏幕上才是圆的。
  * 显卡把贴图缩小 3 到 4 倍时不取平均（没有 mipmap），图案还会按 5 个相位抖动（整格挪动两三个屏幕像素）。
    实拍下来：不到 4 个屏幕像素（横向 16、纵向 12 个纹理像素）的笔画、洞、缺口会发虚；5 个以上才稳。
  * 每个图案在屏幕上只有 28 到 35 个屏幕像素，颜色又暗，所以都要是一整块粗线条的剪影，只留一两个大洞或者通到外面的缺口。

7 个图案放在哪一格：按每格范围的形状来配（清单的顺序是 河灯、宫灯、更鼓、拱桥、荷叶、旌旗、乌篷船。
第 2 格又扁又小，放不下交叉的鼓槌加鼓身，所以把 更鼓 和 拱桥 对调了）：
  0 河灯   1 宫灯   2 拱桥   3 更鼓   4 荷叶   5 旌旗   6 乌篷船

用法: python3 -I tiles_pattern.py <预览图的输出路径> [输出目录]
  不给输出目录就只出预览图（四张：<输出路径> 本身是按着色器模拟出来的整屏花纹；
  同名加 _tiles 是每个图案的大图（原版、新图上下各一排），加 _game 是按游戏里的大小缩小以后的对比，
  加 _overlay 是每个图案和原版叠在一起）。给了输出目录就在里面写出 tilesarray.png 并自检。
只依赖 Pillow 和 numpy。
"""
import colorsys
import importlib.util
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def _doodle():
    spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


d = _doodle()

OUT_REL = "assets/sprites/tilesarray.png"
CANVAS = (1092, 136)
CELL = (156, 136)
WHITE = (255, 255, 255)
NAMES = ["河灯", "宫灯", "拱桥", "更鼓", "荷叶", "旌旗", "乌篷船"]

# 着色器里的几个数（scenes/title.tscn、scenes/uis/scene_transition_control.tscn 里 ShaderMaterial 的参数）
FSIZE = 2.245                    # fsize
SHADER_SCREEN = (1160.0, 650.0)  # screen_size（写着 1160×650，实际画面是 1152×720）
VIEW = (1152.0, 720.0)           # 画面大小
RATIO = SHADER_SCREEN[0] / (CELL[0] * FSIZE)                       # shader 里的 ratio
POS_SCALE = (RATIO * SHADER_SCREEN[0] / CELL[0] / 10, RATIO * SHADER_SCREEN[1] / CELL[1] / 10)   # pos = (UV × 8 − 时间/10) × POS_SCALE
PITCH = (VIEW[0] / (8 * POS_SCALE[0]), VIEW[1] / (8 * POS_SCALE[1]))   # 每格在屏幕上的大小（58.48×56.86）
FIT = (RATIO / FSIZE, RATIO * CELL[1] / CELL[0] / FSIZE)            # 格内坐标 × FIT = 贴图坐标（超过 1 的部分被夹在边上，看不见）
ZOOM = (PITCH[0] / FIT[0] / CELL[0], PITCH[1] / FIT[1] / CELL[1])   # 一个纹理像素等于几个屏幕像素（横 0.254，纵 0.325）
WOBBLE = 3.4                     # 抖动一来回最多挪多少个屏幕像素（FlowMap 的取值范围 × 0.02 × 5 × 一格贴图在屏幕上的宽度）
MIN_PX = 4.0                     # 游戏里看得清的最小尺寸（屏幕像素），比它小的洞和缺口自检时要看连拍

# 原版每一格里图形的范围 (左, 上, 右, 下)。画的时候照它从原版的图里量一遍，对不上就报错
BOXES = [(13, 30, 151, 133), (30, 22, 127, 125), (24, 70, 133, 132), (16, 22, 147, 130),
         (14, 22, 141, 127), (28, 6, 137, 119), (18, 39, 144, 115)]


def box_of(i):
    """第 i 格的范围换成 (x, y, 宽, 高)"""
    b = BOXES[i]
    return b[0], b[1], b[2] - b[0], b[3] - b[1]


# ---------------------------------------------------------------- 画图的小工具（在 doodle.Mask 的基础上）

def mask(w, h):
    return d.Mask(w, h)


def mirror(m):
    """把一张 Mask 左右翻转（宽度不变）"""
    out = mask(math.ceil(m.size[0] / d.K), math.ceil(m.size[1] / d.K))
    out.fill = ImageOps.mirror(m.alpha())
    return out


def teardrop(m, tip, cx, base_y, half_w, bulge_y):
    """火苗那样的滴水形：顶上是一个尖"""
    x, y = tip
    m.shape([(x, y, 1), (cx + half_w * 0.55, y + (bulge_y - y) * 0.42), (cx + half_w, bulge_y),
             (cx + half_w * 0.86, base_y - (base_y - bulge_y) * 0.35), (cx, base_y),
             (cx - half_w * 0.86, base_y - (base_y - bulge_y) * 0.35), (cx - half_w, bulge_y),
             (cx - half_w * 0.55, y + (bulge_y - y) * 0.42)])


def round_rect(m, x0, y0, x1, y1, r):
    """圆角矩形"""
    m.polygon([(x0 + r, y0), (x1 - r, y0), (x1 - r, y1), (x0 + r, y1)])
    m.polygon([(x0, y0 + r), (x1, y0 + r), (x1, y1 - r), (x0, y1 - r)])
    for cx in (x0 + r, x1 - r):
        m.polygon([(cx, y0), (cx, y1)])
        for cy in (y0 + r, y1 - r):
            m.ellipse((cx - r, cy - r, cx + r, cy + r))


def wedge(m, cx, cy, ang, r0, r1, half):
    """从 (cx, cy) 朝 ang 度（0 度朝右、顺时针）张开的一道楔形缺口：里端离中心 r0，外端离中心 r1，外端的半宽是 half"""
    a = math.radians(ang)
    ex, ey = math.cos(a), math.sin(a)
    nx, ny = -ey, ex
    m.polygon([(cx + ex * r0, cy + ey * r0), (cx + ex * r1 + nx * half, cy + ey * r1 + ny * half),
               (cx + ex * r1 - nx * half, cy + ey * r1 - ny * half)])


# ---------------------------------------------------------------- 7 个图案（坐标是各自那一格范围里的位置，原点在范围的左上角）

def m_hedeng():
    """河灯：一朵半开的莲花托着一簇火苗。左右两片尖头的花瓣朝外翻开，下面是圆圆的花萼；火苗比花瓣高出一大截，
    花瓣和火苗之间是两道通到上面的缺口。花瓣试过画成圆头的，缩小以后像一棵三叶草，所以用尖头的"""
    W, H = box_of(0)[2:]
    m = mask(W, H)
    m.shape([(24, 64), (40, 96), (69, 103), (98, 96), (114, 64), (98, 58), (69, 56), (40, 58)])     # 花萼
    petal = mask(W, H)
    petal.shape([(4, 36, 1), (-2, 58), (10, 88), (42, 103, 1), (66, 98), (58, 72), (44, 52), (24, 42)])
    petal.soften(1.8)
    m.union(petal)
    m.union(mirror(petal))
    m.soften(0.6)
    m.ellipse((51, 38, 87, 60))                                                                   # 灯盏
    flame = mask(W, H)
    teardrop(flame, (69, 0), 69, 48, 14, 32)
    flame.soften(0.6)
    m.union(flame)
    return m


def m_gongdeng():
    """宫灯：顶上一个小圆钮，翘檐的盖子夹着略收的灯身，灯身上开一扇竖窗，底下坠一截穗子"""
    W, H = box_of(1)[2:]
    m = mask(W, H)
    m.ellipse((41, 0, 55, 17))                                                                    # 挂钮
    m.polygon([(31, 13), (66, 13), (96, 28), (93, 37), (4, 37), (1, 28)])                         # 上盖
    m.polygon([(13, 36), (84, 36), (78, 80), (19, 80)])                                           # 灯身
    m.polygon([(21, 79), (76, 79), (66, 92), (31, 92)])                                           # 下盖
    m.polygon([(41, 91), (56, 91), (53, 103), (44, 103)])                                         # 穗子
    m.soften(1.4)
    win = mask(W, H)
    win.polygon([(40, 46), (56, 46), (55, 70), (41, 70)])                                         # 竖窗
    win.soften(0.6)
    m.cut(win)
    return m


def m_gongqiao():
    """拱桥：高高拱起来的桥面，桥面下是一个半圆的桥洞。这一格又扁又小，所以不留望柱"""
    W, H = box_of(2)[2:]
    m = mask(W, H)
    deck = [((k / 40) * W, 42 - 38 * (1 - (k / 20 - 1) ** 2)) for k in range(41)]                  # 桥面是一条抛物线
    m.polygon(deck + [(W, H), (0, H)])
    m.soften(1.0)
    arch = mask(W, H)
    arch.ellipse((W / 2 - 34, 30, W / 2 + 34, 30 + 78))                                           # 桥洞
    arch.soften(0.5)
    m.cut(arch)
    return m


def m_genggu():
    """更鼓：两根带圆头的鼓槌交叉着搭在一面桶形大鼓上。两根鼓槌中间的三角一直挖进鼓身里一点：
    只挖到鼓面为止的话它只有五六个屏幕像素高，缩小以后会被填死，看起来就不是交叉的鼓槌了"""
    W, H = box_of(3)[2:]
    m = mask(W, H)
    body = mask(W, H)
    body.shape([(18, 58), (113, 58), (128, 82, 1), (118, 100), (98, 108), (33, 108), (13, 100), (3, 82, 1)])
    body.soften(1.6)
    m.union(body)
    st = mask(W, H)
    st.capsule((9, 62), (123, 8), 15)
    st.capsule((122, 62), (8, 8), 15)
    st.ellipse((112, 0, 134, 20))                                                                 # 鼓槌的圆头
    st.ellipse((-3, 0, 19, 20))
    st.soften(0.6)
    m.union(st)
    h = mask(W, H)
    h.polygon([(65.5, 41), (89, 76), (42, 76)])
    h.soften(0.6)
    m.cut(h)
    return m


def m_heye():
    """荷叶：俯着看的一片圆叶子（纹理里画成 1.28:1 的椭圆，屏幕上才是圆的），朝右下开一道叶柄那一侧的缺口。
    试过再挖叶脉和叶心、加叶柄、配荷花苞、把边缘画成波浪：缩小以后像鸡爪、像字母 Q、像萝卜、像土豆，
    反而认不出是叶子，所以只留这一道缺口（缺口朝右下斜着开，不像张着嘴朝右的小精灵）"""
    W, H = box_of(4)[2:]
    m = mask(W, H)
    m.ellipse((0, 2, W, H - 3))
    h = mask(W, H)
    wedge(h, W / 2, H / 2 + 1, 40, 9, W, 10)
    h.soften(0.6)
    m.cut(h)
    return m


def m_jingqi():
    """旌旗：一根旗杆，顶上是枪尖，旗面从杆顶往右飘开，右边缘是三片火焰似的旗脚，上下边微微起波浪"""
    W, H = box_of(5)[2:]
    m = mask(W, H)
    m.capsule((8, 20), (8, 105), 16)                                                              # 旗杆
    m.shape([(8, 0, 1), (17, 11), (16, 22), (0, 22), (-1, 11)])                                   # 枪尖
    m.soften(0.7)
    flag = mask(W, H)
    flag.shape([(15, 14), (40, 9), (70, 13), (109, 16, 1), (84, 29, 1), (109, 42, 1), (84, 55, 1), (109, 68, 1), (72, 66), (42, 72), (15, 67)])
    flag.soften(1.0)
    m.union(flag)
    return m


def m_wupengchuan():
    """乌篷船：平的船底、两头翘起来的船帮，中段是一个又宽又圆的篷，船底下面三道水纹。
    试过月牙形的船身（像一张长着胡子的脸）、在篷上开圆窗（像独眼）、加船夫（像水鸟）、插竹篙（像茶壶嘴），
    也试过不画水纹：都不如现在这样一眼看出是浮在水上的船"""
    W, H = box_of(6)[2:]
    m = mask(W, H)
    m.shape([(1, 6), (17, 6), (24, 38), (W - 24, 38), (W - 17, 6), (W - 1, 6), (W, H - 27, 1), (0, H - 27, 1)])   # 船身
    cap = mask(W, H)
    round_rect(cap, 34, 0, W - 34, 44, 13)                                                         # 篷
    cap.soften(1.2)
    m.union(cap)
    water = mask(W, H)
    for a, b in ((8, 36), (54, 72), (90, 118)):                                                    # 三道水纹
        round_rect(water, a, 63, b, H, 6)
    water.soften(0.4)
    m.union(water)
    return m


MOTIFS = [m_hedeng, m_gongdeng, m_gongqiao, m_genggu, m_heye, m_jingqi, m_wupengchuan]
# 手绘化（doodle.handdraw_inplace）：原版的图案是马克笔手画的，线是抖的、粗细在变；第一版是规整的矢量图，太板正。
# 只做线抖和粗细变化，图的大小和位置不变
HAND = dict(wobble=0.016, thick=0.02, grain=0.003)


# ---------------------------------------------------------------- 拼成整张图

def clean(a, min_area=6):
    """去掉缩小以后多出来的小点点：不到 min_area 个像素的实心小岛抹掉，不到 min_area 个像素的小孔填上"""
    solid = np.asarray(a) > 127
    for c in d._components(solid):
        if 0 < c.sum() < min_area:
            solid[c] = False
    for c in d._components(~solid):
        if 0 < c.sum() < min_area:
            solid[c] = True
    return Image.fromarray((solid * 255).astype(np.uint8))


def cells():
    """7 张 156×136 的 L 图（每个图案放进它那一格的范围里）"""
    out = []
    for i, fn in enumerate(MOTIFS):
        x, y, w, h = box_of(i)
        a = fn().alpha().crop((0, 0, round(w * d.K), round(h * d.K)))
        a = d.handdraw_inplace(a, seed=500 + i, **HAND)       # 手绘化
        a = clean(a.resize((w, h), Image.LANCZOS))
        cell = Image.new("L", CELL, 0)
        cell.paste(a, (x, y))
        out.append(cell)
    return out


def build():
    """1092×136 的 RGBA 图，纯白"""
    sheet = Image.new("L", CANVAS, 0)
    for i, c in enumerate(cells()):
        sheet.paste(c, (i * CELL[0], 0))
    img = Image.new("RGBA", CANVAS, WHITE + (0,))
    img.putalpha(sheet)
    return img


def split(img):
    """把一张 tilesarray 图裁成 7 格"""
    return [img.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])) for i in range(7)]


# ---------------------------------------------------------------- 自检（每一格单独和原版比）

def holes_of(img):
    """一张图里被图形围起来的洞（从画布四边灌不到的透明地方），一块一个数组"""
    a = np.asarray(img.convert("RGBA"))[..., 3] > 127
    edge = np.zeros_like(a)
    edge[0, :] = edge[-1, :] = True
    edge[:, 0] = edge[:, -1] = True
    outside = d._bfs(~a, [(int(y), int(x)) for y, x in zip(*np.where(edge & ~a))])
    return d._components(~a & ~outside)


def check(path):
    """照 doodle.check 的规矩逐格检查，返回 True 表示没有不合格的地方"""
    new = split(Image.open(path).convert("RGBA"))
    old = d.ORIG[OUT_REL]["cells"]            # 原版图集每一格量好的数（originals.json）
    ok = True
    zx, zy = ZOOM
    for i in range(7):
        cell_ok = True
        mn, mo = d.measure(new[i]), old[i]["measure"]
        nb, ob, bx = mn["box"], mo["box"], box_of(i)
        print("  第 %d 格 %s（游戏里 %.1f×%.1f 个屏幕像素，zoom 横 %.3f 纵 %.3f）" % (
            i, NAMES[i], nb[2] * zx, nb[3] * zy, zx, zy))
        print("    图形的范围：原版 %dx%d@(x%d,y%d)，新图 %dx%d@(x%d,y%d)" % (ob[2], ob[3], ob[0], ob[1], nb[2], nb[3], nb[0], nb[1]))
        if nb[0] < bx[0] - 3 or nb[1] < bx[1] - 3 or nb[0] + nb[2] > bx[0] + bx[2] + 3 or nb[1] + nb[3] > bx[1] + bx[3] + 3:
            print("    [不合格] 图形超出了原版这一格的范围 %s" % (bx,)); cell_ok = False
        if nb[2] < ob[2] * 0.6 or nb[3] < ob[3] * 0.6:
            print("    [不合格] 图形比原版小太多"); cell_ok = False
        elif nb[2] < ob[2] * 0.85 or nb[3] < ob[3] * 0.85:
            print("    [要看一眼] 图形比原版的小（宽 %d%%，高 %d%%）：在游戏里会显得比原版小一号" % (100 * nb[2] / ob[2], 100 * nb[3] / ob[3]))
        if mn["tint"] < 250:
            print("    [不合格] 有不是纯白的不透明像素（最暗的通道是 %d）" % mn["tint"]); cell_ok = False
        print("    细碎程度：原版 %.0f%%，新图 %.0f%%；不相连 %d 块（原版 %d 块），洞 %d 个（原版 %d 个）" % (
            100 * mo["thin"], 100 * mn["thin"], mn["comps"], mo["comps"], mn["holes"], mo["holes"]))
        if mn["thin"] > max(mo["thin"] * 1.5, mo["thin"] + 0.10):
            print("    [不合格] 比原版细碎得多"); cell_ok = False
        # 不相连的几块：doodle 的 gap 是两边各往外长多少步才碰上，换成中间大约隔多少屏幕像素（横竖各算一遍，取小的）
        if mn["gap"] is not None:
            g = min(2.0 * mn["gap"] * zx, 2.0 * mn["gap"] * zy)
            print("    最近的兩块之间大约隔 %.1f 个屏幕像素" % g)
            if g < d.GAP_MIN:
                print("    [不合格] 兩块会粘在一起"); cell_ok = False
            elif g < MIN_PX + WOBBLE:
                print("    [要看一眼] 兩块之间只有 %.1f 个屏幕像素：到连拍里确认没粘上" % g)
        # 洞：逐个量最窄的地方（屏幕像素按横竖 zoom 的平均算）
        if mn["holes"]:
            worst = None
            for hm in holes_of(new[i]):
                wdt = d._width(hm)
                px = wdt * (zx + zy) / 2
                ys, xs = np.where(hm)
                print("    洞：x %d..%d y %d..%d，最窄处 %d 纹理像素 ≈ %.1f 个屏幕像素" % (xs.min(), xs.max(), ys.min(), ys.max(), wdt, px))
                worst = px if worst is None else min(worst, px)
            if worst < d.HOLE_MIN:
                print("    [不合格] 有太窄的洞，缩图以后会被填上"); cell_ok = False
            elif worst < MIN_PX:
                print("    [要看一眼] 有 %.1f 个屏幕像素宽的细洞：到连拍里确认每个相位都看得出来" % worst)
        print("    %s" % ("合格" if cell_ok else "不合格"))
        ok = ok and cell_ok
    return ok


# ---------------------------------------------------------------- 预览：按游戏里的样子缩小

def gpu_minify(a, w, h):
    """像显卡那样把一张 L 图缩成 w×h：每个输出的像素只在原图里取相邻的四个点做双线性插值
    （不取平均，也没有 mipmap），返回 0 到 1 的数组"""
    arr = np.asarray(a, dtype=np.float32) / 255.0
    tx = np.clip((np.arange(w) + 0.5) * (a.width / w) - 0.5, 0, a.width - 1.001)
    ty = np.clip((np.arange(h) + 0.5) * (a.height / h) - 0.5, 0, a.height - 1.001)
    x0, y0 = tx.astype(np.int32), ty.astype(np.int32)
    fx, fy = tx - x0, ty - y0
    return (arr[np.ix_(y0, x0)] * (1 - fx)[None, :] * (1 - fy)[:, None] + arr[np.ix_(y0, x0 + 1)] * fx[None, :] * (1 - fy)[:, None]
            + arr[np.ix_(y0 + 1, x0)] * (1 - fx)[None, :] * fy[:, None] + arr[np.ix_(y0 + 1, x0 + 1)] * fx[None, :] * fy[:, None])


def hsv(h, s, v):
    return colorsys.hsv_to_rgb(h % 1.0, s, v)


def tile_colors(time):
    """照着色器里的算法算每个图案在 time 这一秒的颜色（已经乘上了压暗的系数）"""
    out = []
    for index in range(7):
        hue = 0.46 - ((time + index / 7.0 * 2.5) / 10.0 % 1.0) * 0.52
        val = abs(math.sin((time / 5.0 + index / 4.0) * math.pi))
        k = 0.2 * (abs(math.sin((time + index * 0.5) * math.pi / 2)) / 2.0 + 1.0)
        c = hsv(hue, 0.6, val)
        out.append((c[0] * k, c[1] * k, c[2] * k))
    return out


def simulate(cell_alphas, box, phase, time):
    """照 scene_transition.gdshader 的算法，把 7 格花纹铺到屏幕上的一块（box = x, y, 宽, 高）上。
    返回 (颜色, 透明度) 两个数组。只是近似：图案随时间换序号的算法按 time 那一刻算"""
    x0, y0, w, h = box
    ux, uy = np.meshgrid((x0 + np.arange(w) + 0.5) / VIEW[0], (y0 + np.arange(h) + 0.5) / VIEW[1])   # 每个像素中心的 UV
    rx, ry = (ux * 8 - time / 10) * POS_SCALE[0], (uy * 8 - time / 10) * POS_SCALE[1]                # shader 里的 pos
    cx, cy = np.floor(rx), np.floor(ry)                                                              # 第几格
    idx = np.maximum(cx.astype(np.int64) + cy.astype(np.int64) * 2, 0)
    index = (idx + int(time / 5) + idx // 4) % 7
    pux, puy = rx - cx, ry - cy                                                                     # 格内坐标
    # 抖动：FlowMap 按 UV / 2 取（横坐标再加上相位的偏移），乘 0.02 × 5
    flow = np.asarray(Image.open(os.path.join(ROOT, "assets/sprites/FlowMap.png")).convert("RGB"), dtype=np.float32) / 255.0
    fx = np.clip((ux / 2 + phase / 10.0) * 64 - 0.5, 0, 63.001)
    fy = np.clip(uy / 2 * 64 - 0.5, 0, 63.001)
    ix, iy = fx.astype(np.int32), fy.astype(np.int32)
    gx, gy = fx - ix, fy - iy
    def at(yy, xx):                                    # 在流图里按 (行, 列) 成对地取，结果和坐标网格一样大
        return flow[yy, xx]
    disp = (at(iy, ix) * (1 - gx)[..., None] * (1 - gy)[..., None] + at(iy, ix + 1) * gx[..., None] * (1 - gy)[..., None]
            + at(iy + 1, ix) * (1 - gx)[..., None] * gy[..., None] + at(iy + 1, ix + 1) * gx[..., None] * gy[..., None])
    tu = pux * FIT[0] + disp[..., 0] * 0.02 * 5
    tv = puy * FIT[1] + disp[..., 1] * 0.02 * 5
    alpha = np.zeros((h, w), dtype=np.float32)
    for k in range(7):
        sel = index == k
        if not sel.any():
            continue
        a = np.asarray(cell_alphas[k], dtype=np.float32) / 255.0
        sx = np.clip(np.clip(tu, 0, 1) * CELL[0] - 0.5, 0, CELL[0] - 1.001)[sel]
        sy = np.clip(np.clip(tv, 0, 1) * CELL[1] - 0.5, 0, CELL[1] - 1.001)[sel]
        j, i = sx.astype(np.int32), sy.astype(np.int32)
        fx2, fy2 = sx - j, sy - i
        alpha[sel] = (a[i, j] * (1 - fx2) * (1 - fy2) + a[i, j + 1] * fx2 * (1 - fy2)
                      + a[i + 1, j] * (1 - fx2) * fy2 + a[i + 1, j + 1] * fx2 * fy2)
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    for k, c in enumerate(tile_colors(time)):
        rgb[index == k] = np.array(c)          # 着色器里透明的地方是黑的，这里只给有图案的地方填色
    return rgb * alpha[..., None], alpha


def _font(size):
    for f in ("/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/PingFang.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def preview(path, img):
    """三张预览图：
    <path>          按着色器模拟出来的一块屏幕（4×3 格，7 个图案都有），5 个抖动相位各一张
    <path>_tiles    7 个图案的大图（新图和原版上下各一排）
    <path>_game     按游戏里的大小缩小（39.67×44.26）再放大 8 倍：原版一排、新图一排、5 个相位的抖动各一排"""
    bg, fg = (28, 34, 52), (235, 235, 245)
    font = _font(18)
    base = os.path.splitext(path)[0]
    old_img = d.orig(OUT_REL)                 # 原版的图集不在手边（没设 SW_ORIG）时，预览图里就没有"原版"的那几排
    old_cells = split(old_img) if old_img is not None else None
    new_cells = split(img.convert("RGBA"))
    new_a = [c.split()[3] for c in new_cells]
    old_a = [c.split()[3] for c in old_cells] if old_cells else []

    # ---- 大图
    k = 3
    rows = [(cells, label) for cells, label in ((old_cells, "原版"), (new_cells, "新图")) if cells]
    sheet = Image.new("RGB", (CELL[0] * k * 7 + 8 * 8, (CELL[1] * k + 30) * len(rows) + 16), bg)
    dr = ImageDraw.Draw(sheet)
    for row, (cells, label) in enumerate(rows):
        y = 8 + row * (CELL[1] * k + 30) + 8
        dr.text((8, y), label, fill=fg, font=font)
        for i, c in enumerate(cells):
            t = Image.new("RGB", (CELL[0] * k, CELL[1] * k), (8, 10, 14))
            t.paste(c.resize(t.size, Image.NEAREST), (0, 0), c.resize(t.size, Image.NEAREST))
            sheet.paste(t, (8 + i * (CELL[0] * k + 8), y + 24))
            dr.text((8 + i * (CELL[0] * k + 8) + 6, y + 24 + 4), NAMES[i], fill=(200, 200, 210), font=font)
    sheet.save(base + "_tiles.png")

    # ---- 叠在一起：红 = 原版，绿 = 新图，重合处发黄（确认每个图案的范围和原版重合）
    if old_a:
        k = 2
        sheet = Image.new("RGB", ((CELL[0] * k + 8) * 7 + 8, CELL[1] * k + 44), bg)
        dr = ImageDraw.Draw(sheet)
        for i in range(7):
            a_old = old_a[i].resize((CELL[0] * k, CELL[1] * k), Image.BILINEAR)
            a_new = new_a[i].resize((CELL[0] * k, CELL[1] * k), Image.BILINEAR)
            t = Image.new("RGB", a_old.size, (0, 0, 0))
            t.paste(Image.new("RGB", t.size, (255, 70, 70)), (0, 0), a_old)
            t.paste(Image.new("RGB", t.size, (90, 255, 110)), (0, 0), a_new)
            sheet.paste(t, (8 + i * (CELL[0] * k + 8), 30))
            dr.text((10 + i * (CELL[0] * k + 8), 6), NAMES[i], fill=fg, font=font)
        sheet.save(base + "_overlay.png")

    # ---- 游戏里的大小
    gw, gh = round(PITCH[0] / FIT[0]), round(PITCH[1] / FIT[1])
    k = 8
    rows = [(label, [gpu_minify(a, gw, gh) for a in alphas]) for label, alphas in (("原版", old_a), ("新图", new_a)) if alphas]
    # 抖动的 5 个相位：每个图案单独放进一格（格子的左上角对着这块区域的左上角），按着色器取一遍
    for ph in range(5):
        tiles = [simulate([a] * 7, (0, 0, gw + 4, gh + 4), ph, 0.0)[1] for a in new_a]
        rows.append(("抖动 %d" % ph, tiles))
    tw, th = gw * k + 12, gh * k + 12
    sheet = Image.new("RGB", (tw * 7 + 16, (th + 44) * len(rows) + 16), bg)
    dr = ImageDraw.Draw(sheet)
    for r, (label, tiles) in enumerate(rows):
        y = 8 + r * (th + 44)
        dr.text((8, y), label, fill=fg, font=font)
        for i, t in enumerate(tiles):
            big = Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8)).resize((t.shape[1] * k, t.shape[0] * k), Image.NEAREST)
            tile = Image.new("RGB", big.size, (0, 0, 0))
            tile.paste(Image.new("RGB", big.size, (226, 226, 214)), (0, 0), big)
            sheet.paste(tile, (8 + i * tw, y + 30))
    sheet.save(base + "_game.png")

    # ---- 模拟屏幕
    # 时间取 3.7 秒：图案已经飘动了小半格、颜色也都错开了，但还没有飘出屏幕左上角（模拟里不处理负的格子序号）
    box, k, when = (0, 0, 240, 176), 3, 3.7
    tiles = []
    for ph in range(5):
        rgb = simulate(new_a, box, ph, when)[0]
        tiles.append(Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)).resize((box[2] * k, box[3] * k), Image.NEAREST))
    sheet = Image.new("RGB", ((box[2] * k + 12) * 3 + 8, (box[3] * k + 40) * 2 + 12), bg)
    dr = ImageDraw.Draw(sheet)
    for ph, t in enumerate(tiles):
        x, y = 8 + (ph % 3) * (box[2] * k + 12), 8 + (ph // 3) * (box[3] * k + 40)
        sheet.paste(t, (x, y + 26))
        dr.text((x, y + 2), "模拟着色器：抖动的第 %d 个相位" % ph, fill=fg, font=font)
    sheet.save(path)
    print("预览图:", path, sheet.size, "（每格 %.2f×%.2f，贴图缩成 %.2f×%.2f，zoom 横 %.4f 纵 %.4f）" % (PITCH[0], PITCH[1], PITCH[0] / FIT[0], PITCH[1] / FIT[1], ZOOM[0], ZOOM[1]))
    print("  ", base + "_tiles.png", base + "_game.png", base + "_overlay.png" if old_a else "（没设 SW_ORIG，没有和原版对照的那几张）")


if __name__ == "__main__":
    # 先核对每格的范围和 originals.json 里记下的原版范围对得上
    for i, cell in enumerate(d.ORIG[OUT_REL]["cells"]):
        x, y, w, h = cell["box"]
        bb = (x, y, x + w, y + h)             # 脚本里的 BOXES 记的是左上角、右下角
        if bb != BOXES[i]:
            sys.exit("第 %d 格的范围和原版对不上：原版的图里是 %s，脚本里写的是 %s" % (i, bb, BOXES[i]))
    args = sys.argv[1:]
    img = build()
    if len(args) > 1:                                  # 给了输出目录就写到那里，不写进工程
        os.makedirs(args[1], exist_ok=True)
        out = os.path.join(args[1], "tilesarray.png")
    else:
        out = os.path.join(ROOT, OUT_REL)              # 不给输出目录就写进工程
    img.save(out)
    print("已写出", out, img.size)
    ok = check(out)
    print("自检结果：%s" % ("全部合格" if ok else "有不合格的地方"))
    if args:
        preview(args[0], img)
    sys.exit(0 if ok else 1)

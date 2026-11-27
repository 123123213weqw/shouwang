#!/usr/bin/env python3
"""大厅（标题页）背景墙纸的三版候选：还是 tiles_pattern.py 那一套机制（7 格竖条，着色器铺满、斜着滚、轮流明暗、抖动），
只换每一格里画的是什么。图案还是那么小（屏幕上三十像素上下），所以都只是一两个大形的剪影。

    一 墨梅    梅枝、开放的梅、花苞、落瓣、月亮、竹叶、山石            清、雅、静
    二 夜市    灯笼、纸伞、扇子、铜钱、鱼、糖葫芦、酒坛                热闹，像节庆巡游
    三 书法    守、望、夜、河、灯、水、归 七个字（游戏自己的字体）    字就是图案，满屏的字在流

每一版是一张 assets/sprites/lobby/tiles_<名字>.png，和现在那张 tilesarray.png 一样的尺寸（1092×136），
换上去只要改标题页场景里指着的那张贴图，着色器不用动。

用法（在工程根目录，只依赖 Pillow 和 numpy；录视频还要 ffmpeg）:
    python3 tools/art/lobby_tiles.py                     只出三张预览图到 builds/lobby/（每张是某一时刻的整屏花纹）
    python3 tools/art/lobby_tiles.py --write             另外写出三张墙纸到 assets/sprites/lobby/
    python3 tools/art/lobby_tiles.py --video <目录> [秒数=10] [帧率=16]
                                                         另外录四段会动的预览到那个目录：lobby_<名字>.mp4 三段整屏的，lobby_all.mp4 三版并排
"""
import importlib.util
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "lobby")
PREVIEW_DIR = os.path.join(ROOT, "builds", "lobby")
FONT = os.path.join(ROOT, "assets", "fonts", "ZCOOLKuaiLe-Regular.ttf")


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


tp = _load(os.path.join(HERE, "tiles_pattern.py"), "tiles_pattern")     # 复用它的小工具、每格的范围、手绘化和整屏模拟
d = tp.d


def sector(m, cx, cy, r, a0, a1, n=40, rx=None, ry=None):
    """扇形：以 (cx, cy) 为圆心、半径 r，从 a0 度到 a1 度（0 度朝右，顺时针）。
    给了 rx、ry 就是椭圆弧：横半径 rx、纵半径 ry"""
    rx = r if rx is None else rx
    ry = r if ry is None else ry
    pts = [(cx, cy)]
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        pts.append((cx + math.cos(a) * rx, cy + math.sin(a) * ry))
    m.polygon(pts)


# ================================================================ 一 墨梅
# 每格的范围 (左, 上, 右, 下) 和原来的一样，图案照这个范围画

def m_meizhi():
    """梅枝：一根折了三折的老枝，分两根小杈，枝上三个圆头的节"""
    W, H = tp.box_of(0)[2:]
    m = tp.mask(W, H)
    tp.d.Mask.capsule(m, (6, 104), (52, 70), 17)
    tp.d.Mask.capsule(m, (52, 70), (96, 58), 13)
    tp.d.Mask.capsule(m, (96, 58), (134, 20), 10)
    tp.d.Mask.capsule(m, (54, 70), (26, 26), 9)                # 小杈
    tp.d.Mask.capsule(m, (98, 56), (128, 86), 8)
    for cx, cy in ((52, 70), (96, 58)):                        # 节
        tp.d.Mask.ellipse(m, (cx - 11, cy - 11, cx + 11, cy + 11))
    m.soften(1.0)
    return m


def m_meihua():
    """开放的梅：五个分开的圆花瓣围着一个挖空的圆心。花瓣之间留出缺口，缩到三十像素还看得出是五瓣"""
    W, H = tp.box_of(1)[2:]
    m = tp.mask(W, H)
    cx, cy, r = W / 2, H / 2 + 4, 36
    for k in range(5):
        a = -math.pi / 2 + 2 * math.pi * k / 5
        px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
        m.ellipse((px - 24, py - 24, px + 24, py + 24))
    m.soften(1.6)
    hole = tp.mask(W, H)
    hole.ellipse((cx - 17, cy - 17, cx + 17, cy + 17))
    m.cut(hole)
    gaps = tp.mask(W, H)
    for k in range(5):                                   # 花瓣之间的缺口：从圆心往外挖一条楔形
        a = -math.pi / 2 + math.pi / 5 + 2 * math.pi * k / 5
        tp.wedge(gaps, cx, cy, math.degrees(a), 24, 52, 5)
    m.cut(gaps)
    return m


def m_huabao():
    """花苞：一颗上头尖的骨朵斜朝右上，左下是抱着它的萼和一截短梗。这一格又扁又小，所以斜着放才放得下"""
    W, H = tp.box_of(2)[2:]
    m = tp.mask(W, H)
    m.shape([(40, 44), (48, 16), (74, 4), (W - 2, 24, 1), (80, 52), (56, 56)])     # 骨朵：右上是个尖
    m.soften(1.2)
    tp.d.Mask.capsule(m, (38, 46), (12, 56), 6)                                  # 梗
    m.polygon([(44, 40), (30, 22), (48, 34)])                                    # 萼片：翘起来的两个尖
    m.polygon([(44, 52), (34, 62), (54, 58)])
    m.soften(0.8)
    return m


def m_luoban():
    """落瓣：一片圆头的花瓣斜着飘，右下角还有一片飞远了的"""
    W, H = tp.box_of(3)[2:]
    m = tp.mask(W, H)
    petal = tp.mask(W, H)
    petal.shape([(16, 12, 1), (66, 10), (98, 48), (84, 96, 1), (44, 98), (8, 56)])
    petal.soften(3.0)
    m.union(petal)
    far = tp.mask(W, H)
    far.ellipse((W - 34, 4, W - 6, 30))
    m.union(far)
    vein = tp.mask(W, H)                                  # 花瓣上一道叶脉
    tp.d.Mask.capsule(vein, (24, 20), (76, 88), 3)
    m.cut(vein)
    return m


def m_yueliang():
    """月亮：一轮圆月，右下缺一块（挖掉一个圆）"""
    W, H = tp.box_of(4)[2:]
    m = tp.mask(W, H)
    m.ellipse((8, 6, W - 8, H - 6))
    m.soften(1.2)
    bite = tp.mask(W, H)
    bite.ellipse((W - 70, H - 78, W + 26, H + 18))
    m.cut(bite)
    return m


def m_zhuye():
    """竹叶：三片细长的叶子从一点散开，底下一截竹节"""
    W, H = tp.box_of(5)[2:]
    m = tp.mask(W, H)
    for ang, length, half in ((-62, 92, 13), (-108, 96, 13), (-22, 74, 11)):
        a = math.radians(ang)
        tipx, tipy = W / 2 + 6 + math.cos(a) * length, H - 12 + math.sin(a) * length
        tp.d.Mask.capsule(m, (W / 2 + 6, H - 12), ((W / 2 + 6 + tipx) / 2, (H - 12 + tipy) / 2), half)
        tp.d.Mask.capsule(m, ((W / 2 + 6 + tipx) / 2, (H - 12 + tipy) / 2), (tipx, tipy), half * 0.55)
    tp.d.Mask.capsule(m, (W / 2 - 2, H - 4), (W / 2 + 10, H - 20), 7)
    m.soften(0.8)
    return m


def m_shanshi():
    """山石：两块叠着的石头，各是一整块，上面一块小"""
    W, H = tp.box_of(6)[2:]
    m = tp.mask(W, H)
    m.shape([(10, H - 8), (4, H - 52), (30, H - 64, 1), (86, H - 60), (W - 4, H - 40), (W - 10, H - 8)])
    m.soften(1.2)
    top = tp.mask(W, H)
    top.shape([(34, H - 60), (44, H - 104), (76, H - 110, 1), (98, H - 70)])
    top.soften(1.2)
    m.union(top)
    return m


# ================================================================ 二 夜市

def m_denglong():
    """灯笼：两头收、中间鼓的灯身，上面一根挂绳，底下一撮穗"""
    W, H = tp.box_of(0)[2:]
    m = tp.mask(W, H)
    m.shape([(W / 2 - 20, 36, 1), (W / 2 - 52, 62), (W / 2 - 50, 88), (W / 2 - 22, 106), (W / 2 + 22, 106), (W / 2 + 50, 88), (W / 2 + 52, 62), (W / 2 + 20, 36)])
    m.soften(1.2)
    tp.d.Mask.capsule(m, (W / 2, 0), (W / 2, 40), 6)                       # 绳
    tp.round_rect(m, W / 2 - 26, 32, W / 2 + 26, 42, 4)                     # 盖
    tp.round_rect(m, W / 2 - 24, 104, W / 2 + 24, 114, 4)                   # 底
    for i in range(4):                                                       # 穗
        tp.d.Mask.capsule(m, (W / 2 - 12 + i * 8, 112), (W / 2 - 14 + i * 9, H - 4), 3)
    return m


def m_zhisan():
    """纸伞：一个半圆的伞面，底下一根伞柄。伞面上开三道竖的缝"""
    W, H = tp.box_of(1)[2:]
    m = tp.mask(W, H)
    sector(m, W / 2, 62, W / 2 - 4, 180, 360)                               # 伞面：上半圆
    m.soften(1.0)
    tp.d.Mask.capsule(m, (W / 2, 60), (W / 2, H - 2), 6)                    # 柄
    tp.d.Mask.ellipse(m, (W / 2 - 9, H - 20, W / 2 + 9, H - 2))             # 柄头的疙瘩
    seams = tp.mask(W, H)
    for x in (W * 0.30, W * 0.50, W * 0.70):
        tp.d.Mask.capsule(seams, (W / 2, 60), (x, 16 + abs(x - W / 2) * 0.55), 3)
    m.cut(seams)
    return m


def m_shanzi():
    """折扇：一把张开的折扇，扇钉在正下方，扇面朝上张开，几道折缝从扇钉放射出去。
    这一格又扁又宽：斜着放的扇面伸不出格子（伸出去就被裁掉一条），所以立着放，正好铺满。
    扇面在纹理里横着画宽一些，屏幕上才是匀称的弧（着色器把每一格横着压，见 tiles_pattern.py 开头）"""
    W, H = tp.box_of(2)[2:]
    m = tp.mask(W, H)
    cx, cy = W / 2, H - 3                                           # 扇钉
    rx, ry = W / 2 - 5, H - 12
    a0, a1 = 210, 330                                               # 扇面从朝左下绕过正上到朝右下
    sector(m, cx, cy, 0, a0, a1, rx=rx, ry=ry)
    m.soften(1.2)
    tp.d.Mask.ellipse(m, (cx - 9, cy - 11, cx + 9, cy + 3))          # 扇钉
    folds = tp.mask(W, H)
    for k in range(1, 6):
        a = math.radians(a0 + (a1 - a0) * k / 6)
        ex, ey = math.cos(a), math.sin(a)
        tp.d.Mask.capsule(folds, (cx + ex * 18, cy + ey * 18), (cx + ex * rx * 1.03, cy + ey * ry * 1.03), 3)
    m.cut(folds)
    return m


def m_tongqian():
    """铜钱：一个圆，中间挖一个方孔"""
    W, H = tp.box_of(3)[2:]
    m = tp.mask(W, H)
    cx, cy, r = W / 2, H / 2, 50
    m.ellipse((cx - r, cy - r, cx + r, cy + r))
    m.soften(1.2)
    hole = tp.mask(W, H)
    hole.polygon([(cx - 17, cy - 17), (cx + 17, cy - 17), (cx + 17, cy + 17), (cx - 17, cy + 17)])
    m.cut(hole)
    return m


def m_yu():
    """鱼：一滴水那样的身子，分叉的尾巴，眼睛挖掉。头朝左"""
    W, H = tp.box_of(4)[2:]
    m = tp.mask(W, H)
    m.shape([(8, H / 2, 1), (34, H / 2 - 34), (74, H / 2 - 30), (98, H / 2 - 6), (98, H / 2 + 6), (74, H / 2 + 30), (34, H / 2 + 34)])
    m.soften(1.2)
    m.polygon([(94, H / 2), (W - 4, H / 2 - 36), (W - 16, H / 2), (W - 4, H / 2 + 36)])      # 尾巴
    m.soften(0.8)
    eye = tp.mask(W, H)
    eye.ellipse((26, H / 2 - 14, 40, H / 2))
    m.cut(eye)
    return m


def m_tanghulu():
    """糖葫芦：一根签子斜着穿三颗山楂，签子的下半截露在外面。
    莲蓬试过了：缩小以后三个孔看不出来，像个铃铛"""
    W, H = tp.box_of(5)[2:]
    m = tp.mask(W, H)
    tp.d.Mask.capsule(m, (W / 2 + 7, 2), (W / 2 - 9, H - 2), 7)                    # 签子
    for cx, cy in ((W / 2 + 5, 27), (W / 2 - 1, 56), (W / 2 - 7, 85)):             # 三颗（横着画宽一点，屏幕上才是圆的）
        tp.d.Mask.ellipse(m, (cx - 24, cy - 20, cx + 24, cy + 20))
    m.soften(0.6)
    return m


def m_jiutan():
    """酒坛：鼓着的坛身，一个窄口，口上贴着封纸（一块方方的红纸）"""
    W, H = tp.box_of(6)[2:]
    m = tp.mask(W, H)
    m.shape([(W / 2 - 24, 28, 1), (W / 2 - 34, 50), (W / 2 - 62, 84), (W / 2 - 50, H - 4), (W / 2 + 50, H - 4), (W / 2 + 62, 84), (W / 2 + 34, 50), (W / 2 + 24, 28)])
    m.soften(1.4)
    tp.round_rect(m, W / 2 - 30, 16, W / 2 + 30, 32, 6)                   # 口
    seal = tp.mask(W, H)                                                   # 封纸上一道十字（挖空）
    tp.d.Mask.capsule(seal, (W / 2 - 18, 24), (W / 2 + 18, 24), 3)
    m.cut(seal)
    band = tp.mask(W, H)                                                   # 坛腰上一道箍（挖空）
    tp.d.Mask.capsule(band, (W / 2 - 58, 86), (W / 2 + 58, 86), 4)
    m.cut(band)
    return m


# ================================================================ 三 书法

CALLIGRAPHY = ["守", "望", "夜", "河", "灯", "水", "归"]
GLYPH_BOX = (12, 16, 144, 120)      # 每个字的范围 (左, 上, 右, 下)，七个字都一样：一样大、都在格子正中，像一张字帖
SX = tp.ZOOM[1] / tp.ZOOM[0]        # 着色器把每一格横着压了多少（约 1.28）：纹理里横着画宽这么多，屏幕上的字才是方的


def dilate(a, rx, ry):
    """把白的地方往两边加粗：横着各加 rx 个像素，竖着各加 ry 个像素。a 是 0 到 255 的数组"""
    b = a > 127
    for _ in range(rx):
        b = b | np.roll(b, 1, axis=1) | np.roll(b, -1, axis=1)
    for _ in range(ry):
        b = b | np.roll(b, 1, axis=0) | np.roll(b, -1, axis=0)
    return b.astype(np.uint8) * 255


def glyph_cell(text, bold=(2, 2)):
    """一格 156×136 的 L 图：字撑满 GLYPH_BOX 那块范围。
    字在纹理里横着画宽 SX 倍，屏幕上才是方方正正的；笔画加粗 bold 那么多（横、竖各一边加几个像素），
    因为不到四个屏幕像素的笔画缩小以后会发虚。bold 给 (0, 0) 就不加粗"""
    x, y, r, b = GLYPH_BOX
    w, h = r - x, b - y
    font = ImageFont.truetype(FONT, 200)
    left, top, right, bottom = font.getbbox(text)
    tmp = Image.new("L", (right - left + 8, bottom - top + 8), 0)
    ImageDraw.Draw(tmp).text((4 - left, 4 - top), text, font=font, fill=255)
    k = min((w - 10) / (tmp.width * SX), (h - 10) / tmp.height)         # 撑满这块范围（横竖取小的那个方向）
    tmp = tmp.resize((max(1, round(tmp.width * k * SX)), max(1, round(tmp.height * k))), Image.LANCZOS)
    a = dilate(np.asarray(tmp), *bold) if bold != (0, 0) else np.asarray(tmp)
    tmp = Image.fromarray(a).filter(ImageFilter.GaussianBlur(0.6))     # 加粗出来的锯齿边揉一揉
    img = Image.new("L", (round(w), round(h)), 0)
    img.paste(tmp, (round((w - tmp.width) / 2), round((h - tmp.height) / 2)))
    return img


# ================================================================ 拼成墙纸

SETS = {
    "plum": ("墨梅", [m_meizhi, m_meihua, m_huabao, m_luoban, m_yueliang, m_zhuye, m_shanshi]),
    "market": ("夜市", [m_denglong, m_zhisan, m_shanzi, m_tongqian, m_yu, m_tanghulu, m_jiutan]),
}


def build(key):
    """7 格 → 1092×136 的 RGBA，纯白。手绘化和原来的一样"""
    if key == "script":
        cells = [glyph_cell(t) for t in CALLIGRAPHY]
        sheet = Image.new("L", tp.CANVAS, 0)
        for i, c in enumerate(cells):
            sheet.paste(c, (i * tp.CELL[0] + GLYPH_BOX[0], GLYPH_BOX[1]))
    else:
        cells = []
        for i, fn in enumerate(SETS[key][1]):
            x, y, w, h = tp.box_of(i)
            a = fn().alpha().crop((0, 0, round(w * d.K), round(h * d.K)))
            a = d.handdraw_inplace(a, seed=700 + i, **tp.HAND)
            a = tp.clean(a.resize((round(w), round(h)), Image.LANCZOS))
            cell = Image.new("L", tp.CELL, 0)
            cell.paste(a, (x, y))
            cells.append(cell)
        sheet = Image.new("L", tp.CANVAS, 0)
        for i, c in enumerate(cells):
            sheet.paste(c, (i * tp.CELL[0], 0))
    img = Image.new("RGBA", tp.CANVAS, (255, 255, 255, 0))
    img.putalpha(sheet)
    return img


def cells_of(img):
    return [img.crop((i * tp.CELL[0], 0, (i + 1) * tp.CELL[0], tp.CELL[1])).getchannel("A") for i in range(7)]


def phase_at(time):
    """抖动的相位：着色器里一秒钟换 8 次，五个相位轮着来"""
    return int(time * 8.0) % 5


def screen(cells, box, time):
    """time 这一秒屏幕上一块（x, y, 宽, 高）的花纹，和着色器的算法一样，带标题页的暗底色"""
    rgb, _ = tp.simulate(cells, box, phase_at(time), time)
    return np.clip(rgb, 0, 1)


def frame(img, time, phase=0.0):
    """某一时刻的整屏花纹（和着色器的算法一样），带标题页的暗底色"""
    rgb, _ = tp.simulate(cells_of(img), (0, 0, int(tp.VIEW[0]), int(tp.VIEW[1])), phase, time)
    return np.clip(rgb, 0, 1)


def video(path, panels, seconds, fps):
    """录一段视频（本机模拟，不用开游戏）：panels 是 (墙纸, 屏幕上的一块 (x, y, 宽, 高), 左上角的字) 的列表，几块横着并排。
    帧率取 16：抖动一秒钟换 8 次，这样每个相位正好两帧，不会看着一顿一顿的"""
    cells = [cells_of(img) for img, _, _ in panels]
    tags = []
    for _, box, text in panels:                                   # 左上角的字：先画成一张带透明通道的小图，每一帧贴上去
        tag = Image.new("RGBA", (box[2], 44), (0, 0, 0, 0))
        if text:
            ImageDraw.Draw(tag).text((12, 10), text, font=tp._font(22), fill=(255, 250, 235, 190))
        tags.append(np.asarray(tag, dtype=np.float32) / 255.0)
    w = sum(p[1][2] for p in panels)
    h = panels[0][1][3]
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h),
           "-r", str(fps), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", "-movflags", "+faststart", path]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for n in range(round(seconds * fps)):
        t = n / fps
        parts = []
        for k, (_, box, _) in enumerate(panels):
            a = screen(cells[k], box, t)
            al = tags[k][..., 3:4]
            a[:al.shape[0]] = a[:al.shape[0]] * (1.0 - al) + tags[k][..., :3] * al
            parts.append(a)
        ff.stdin.write((np.concatenate(parts, axis=1) * 255).astype(np.uint8).tobytes())
    ff.stdin.close()
    if ff.wait() != 0:
        raise SystemExit("ffmpeg 没录完：%s" % path)
    print("视频：%s（%.1f 秒，每秒 %d 帧，%d×%d）" % (path, seconds, fps, w, h))


def main(argv):
    write = "--write" in argv
    at = argv.index("--video") if "--video" in argv else -1
    keys = [("plum", "墨梅"), ("market", "夜市"), ("script", "书法")]
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    built = {}
    for key, name in keys:
        img = built[key] = build(key)
        sheet = Image.new("RGB", (int(tp.VIEW[0]) * 2, int(tp.VIEW[1])), (0, 0, 0))
        for k, t in enumerate((0.0, 7.0)):
            a = (frame(img, t) * 255).astype(np.uint8)
            sheet.paste(Image.fromarray(a), (k * int(tp.VIEW[0]), 0))
        out = os.path.join(PREVIEW_DIR, "tiles_%s.png" % key)
        sheet.save(out)
        print("%s %s %s（左 0 秒，右 7 秒）" % (name, "已写出墙纸" if write else "", out))
        if write:
            os.makedirs(OUT_DIR, exist_ok=True)
            p = os.path.join(OUT_DIR, "tiles_%s.png" % key)
            img.save(p)
            print("   墙纸：" + p)
    if at < 0:
        return 0
    rest = [a for a in argv[at + 1:] if not a.startswith("--")]
    vdir = rest[0]
    seconds = float(rest[1]) if len(rest) > 1 else 10.0
    fps = int(rest[2]) if len(rest) > 2 else 16
    os.makedirs(vdir, exist_ok=True)
    whole = (0, 0, int(tp.VIEW[0]), int(tp.VIEW[1]))
    for key, name in keys:                                        # 三段整屏的
        video(os.path.join(vdir, "lobby_%s.mp4" % key), [(built[key], whole, "　".join(SETS.get(key, (name,))))], seconds, fps)
    crop = (256, 160, 640, 400)                                   # 三版并排：各取屏幕中间一块，大小不变
    video(os.path.join(vdir, "lobby_all.mp4"), [(built[k], crop, n) for k, n in keys], seconds, fps)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

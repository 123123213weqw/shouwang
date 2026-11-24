#!/usr/bin/env python3
"""a2 这一组的元素脚本共用的小工具：加载 doodle，以及出预览图。
预览图每个元素（或者每个变体）一行：原版、新图（都只看图形附近，放大 2 倍）、
新图按游戏里的大小缩小（zoom）再放大 8 倍（最近邻，看清像素）。"""
import importlib.util
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

CANVAS = (156, 136)
DIR = "assets/sprites/upgrades/"


def box_of(rel):
    """原版图里图形的范围 (x, y, 宽, 高)"""
    return doodle.orig_box(rel)


def crop_of(rel, pad=12):
    """图形附近的一块（左上角 x、y，右下角 x、y）"""
    x, y, w, h = box_of(rel)
    return x - pad, y - pad, x + w + pad, y + h + pad


def preview(path, items, zooms=(0.29, 0.35, 0.44), big=2, k=8):
    """items 是 (标题, 原版的相对路径, 新图) 的列表，每个一行。
    zooms 默认是游戏里实测到的三档大小：第 12 关最远一排（0.29）、中排（0.35）、近排（0.44）"""
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 16)
    bg, bg2, tint = (14, 22, 40), (26, 22, 20), (96, 196, 150)
    row_h, tiles_w = 0, []
    rows = []
    for title, rel, new in items:
        crop = crop_of(rel)
        cw, ch = crop[2] - crop[0], crop[3] - crop[1]
        tiles = []

        def tile(im, scale, back, resample, z=1.0):
            c = im.crop(tuple(round(v * z) for v in crop)).resize((max(1, round(cw * z * scale)), max(1, round(ch * z * scale))), resample)
            t = Image.new("RGB", c.size, back)
            t.paste(Image.new("RGB", c.size, (226, 238, 234) if back == bg else tint), (0, 0), c)
            return t

        for im, label in ((doodle.orig(rel), "原版"), (new, title)):
            if im is None:                   # 原版的图不在手边（没设 SW_ORIG），就不放这一格
                continue
            t = tile(im, big, bg, Image.NEAREST)
            tiles.append((t, label))
        for z in zooms:
            small = new.resize((max(1, round(CANVAS[0] * z)), max(1, round(CANVAS[1] * z))), Image.LANCZOS)
            tiles.append((tile(small, k, bg2, Image.NEAREST, z), "游戏里的大小 ×%.2f" % z))
        rows.append(tiles)
        row_h = max(row_h, max(t.height for t, _ in tiles) + 36)
        for i, (t, _) in enumerate(tiles):
            while len(tiles_w) <= i:
                tiles_w.append(0)
            tiles_w[i] = max(tiles_w[i], t.width)
    sheet = Image.new("RGB", (sum(tiles_w) + 14 * (len(tiles_w) + 1), row_h * len(rows) + 10), (28, 34, 52))
    draw = ImageDraw.Draw(sheet)
    for r, tiles in enumerate(rows):
        x, y = 14, 6 + r * row_h
        for t, label in tiles:
            sheet.paste(t, (x, y + 28))
            draw.text((x, y + 4), label, fill=(235, 235, 245), font=font)
            x += t.width + 14
    sheet.save(path)
    print("预览图:", path, sheet.size)


def save(imgs, out_dir):
    """imgs 是 (文件名, 图) 的列表"""
    os.makedirs(out_dir, exist_ok=True)
    for name, im in imgs:
        im.save(os.path.join(out_dir, name))
    print("已写出 %s 到 %s" % ("、".join(n for n, _ in imgs), out_dir))

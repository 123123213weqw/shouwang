#!/usr/bin/env python3
"""把原版工程的图量一遍，结果写进同目录的 originals.json：画布大小、图形的范围、环中间那块、measure() 的各项。
tools/art 里的脚本重画和自检时只读这个文件，原版工程的图不用放在手边（它们是原作者的东西，不进这个仓库）。

用法: python3 tools/art/bake_originals.py <原版工程里放着 assets/ 和 icon.svg 的那个目录>
量哪些图：这个工程的 assets/ 里的每一张图和 icon.svg，在原版工程里的同名文件。改过名的两张单独对应：
  assets/sprites/ui/title-logo.png ← assets/sprites/ui/ooqo-title.png
  assets/boot_splash.png           ← assets/ooqo-title-itch.png
tilesarray.png 是 7 格拼成的图集，除了整张的数，每一格也单独量（存在 cells 里）。
只在添了新的美术元素、或者发现数对不上的时候才需要重跑；平时不用管。
"""
import importlib.util
import json
import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "originals.json")
RENAME = {"assets/sprites/ui/title-logo.png": "assets/sprites/ui/ooqo-title.png",
          "assets/boot_splash.png": "assets/ooqo-title-itch.png"}
CELL = (156, 136)                       # tilesarray.png 每一格的大小（和 tiles_pattern.py 的 CELL 一致）


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def inner_of(im, level=200):
    """环（边框）中间那块不实心的范围：从画布中心往四个方向量。中间是实心的返回 None"""
    W, H = im.size
    px = im.split()[3].load()
    cx, cy = W // 2, H // 2
    if px[cx, cy] >= level:
        return None

    def run(dx, dy):
        n = 0
        while 0 <= cx + dx * (n + 1) < W and 0 <= cy + dy * (n + 1) < H and px[cx + dx * (n + 1), cy + dy * (n + 1)] < level:
            n += 1
        return n
    return [cx - run(-1, 0), cy - run(0, -1), cx + run(1, 0), cy + run(0, 1)]


def entry(im, measure):
    a = im.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
    return {
        "size": list(im.size),
        "box": [a[0], a[1], a[2] - a[0], a[3] - a[1]] if a else None,
        "inner": inner_of(im),
        "measure": measure(im),
    }


def rounded(value):
    """measure() 的结果里的小数只留 6 位，写出来的文件才稳定"""
    if isinstance(value, float):
        return round(value, 6)
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [rounded(v) for v in value]
    return value


def main():
    if len(sys.argv) != 2:
        sys.exit("用法: python3 tools/art/bake_originals.py <原版工程里放着 assets/ 和 icon.svg 的那个目录>")
    src = os.path.abspath(sys.argv[1])
    measure = load("doodle").measure
    data, skipped = {}, []
    for d, _, files in os.walk(os.path.join(ROOT, "assets")):
        for f in sorted(files):
            if not f.lower().endswith(".png"):
                continue
            rel = os.path.relpath(os.path.join(d, f), ROOT)
            orig_rel = RENAME.get(rel, rel)
            path = os.path.join(src, orig_rel)
            if not os.path.exists(path):
                skipped.append(rel)
                continue
            im = Image.open(path).convert("RGBA")
            data[orig_rel] = rounded(entry(im, measure))
            if rel == "assets/sprites/tilesarray.png":
                data[orig_rel]["cells"] = [rounded(entry(im.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])), measure)) for i in range(7)]
    icon = os.path.join(src, "icon.svg")
    if os.path.exists(icon):
        root = ET.parse(icon).getroot()
        data["icon.svg"] = {"svg_root": {"tag": root.tag, "attrib": dict(root.attrib)}}
    else:
        skipped.append("icon.svg")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print("已写出 tools/art/originals.json：%d 张图" % len(data))
    if skipped:
        print("原版工程里没有同名文件、没有量的：", "、".join(skipped))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""看图画得对不对的命令行工具（配合 doodle.py）。

  python3 -I review.py check [--zoom 0.55] [--kind 3d|2d] <工程根目录> <相对路径>...     自检（zoom = 一个纹理像素等于几个屏幕像素）
  python3 -I review.py strip <输出.png> <倍数> <截图路径模板:x,y,w,h>...   抖动条：同一块地方在 10 个相位的连拍里各是什么样，模板里写 {i}
                                                                              （模板最后带上 :x,y,w,h 是只裁这一块；一行 5 个相位，默认取 P0 到 P9）
  python3 -I review.py sheet <输出.png> <工程根目录> <标题=相对路径>...   对比图：每个元素 原版 | 新图 | 叠在一起
  python3 -I review.py zoom <输出.png> <截图> <x,y,w,h> <倍数> [标题]     把截图的一块放大（最近邻，看清像素）
  python3 -I review.py mini <输出.png> <zoom> <新图.png>...              不进游戏的快速预览：把新图按游戏里的大小缩小
                                                                              （zoom = 一个纹理像素等于几个屏幕像素，比如 0.31）再放大 8 倍并排，
                                                                              先看"在最小的那种情况下还认不认得出"。真的算数还是要进游戏连拍
  python3 -I review.py crops <输出.png> <截图>:<倍数>:<标题>:<x,y,w,h>...  好几块并排放在一张图里

crops 的每一项写成 截图路径:倍数:标题:x,y,w,h，例如：
  review.py crops out.png shots/p1_a.png:10:河灯:520,300,60,40 shots/base.png:10:原版:520,300,60,40
"""
import importlib.util
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))


def load_doodle():
    spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def font(size):
    for f in ("/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/PingFang.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    cmd = sys.argv[1]
    if cmd == "check":
        args, opts = [], {"zoom": None, "kind": "3d"}
        for arg in sys.argv[2:]:
            if arg.startswith("--zoom="):
                opts["zoom"] = float(arg.split("=", 1)[1])
            elif arg.startswith("--kind="):
                opts["kind"] = arg.split("=", 1)[1]
            else:
                args.append(arg)
        root, rels = os.path.abspath(args[0]), args[1:]
        doodle = load_doodle()
        all_ok = True
        for rel in rels:
            # 新加的文件（原版里没有同名的那张）拿同目录里最像的原版图当参照：写在文件名后面，写成 相对路径=原版的相对路径
            ref = None
            if "=" in rel:
                rel, ref = rel.split("=", 1)
            elif rel not in doodle.ORIG:
                sys.exit("原版里没有 %s，照着哪张原版画的请写成 %s=原版的相对路径" % (rel, rel))
            if not doodle.check(os.path.join(root, rel), rel, zoom=opts["zoom"], kind=opts["kind"], ref=ref, name=rel):
                all_ok = False
        print("自检结果：%s" % ("全部合格" if all_ok else "有不合格的地方"))
        sys.exit(0 if all_ok else 1)
    if cmd == "sheet":
        out, root, opts, args = os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3]), {"cols": None, "cell": 260}, []
        for arg in sys.argv[4:]:
            if arg.startswith("--cols="):
                opts["cols"] = int(arg.split("=", 1)[1])
            elif arg.startswith("--cell="):
                opts["cell"] = int(arg.split("=", 1)[1])
            else:
                args.append(arg)
        items = []
        for item in args:
            title, rel = item.split("=", 1)
            items.append((title, os.path.join(root, rel), rel))
        print("对比图:", out, load_doodle().review_sheet(out, items, cell=opts["cell"], cols=opts["cols"]))
        return
    bg = (28, 34, 52)
    f = font(22)
    if cmd == "zoom":
        out, shot = sys.argv[2], sys.argv[3]
        x, y, w, h = (int(v) for v in sys.argv[4].split(","))
        k = float(sys.argv[5])
        title = sys.argv[6] if len(sys.argv) > 6 else os.path.basename(shot)
        items = [(shot, k, title, (x, y, w, h))]
    elif cmd == "crops":
        out = sys.argv[2]
        items = []
        for item in sys.argv[3:]:
            shot, k, title, rect = item.rsplit(":", 3)
            items.append((shot, float(k), title, tuple(int(v) for v in rect.split(","))))
    elif cmd == "mini":
        out, z = sys.argv[2], float(sys.argv[3])
        k = 8
        tiles = []
        for path in sys.argv[4:]:
            im = Image.open(path).convert("RGBA")
            # 先裁到图形周围一圈再缩小：画布四周的空白在游戏里是透明的，不算在大小里
            box = im.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
            if box:
                m = 12
                im = im.crop((max(0, box[0] - m), max(0, box[1] - m), min(im.width, box[2] + m), min(im.height, box[3] + m)))
            small = im.resize((max(1, round(im.width * z)), max(1, round(im.height * z))), Image.LANCZOS)
            big = small.resize((small.width * k, small.height * k), Image.NEAREST)
            t = Image.new("RGB", (big.width, big.height), (16, 40, 36))
            t.paste(Image.new("RGB", t.size, (226, 238, 234)), (0, 0), big)
            tiles.append((os.path.basename(path), t))
        w = max(t.width for _, t in tiles) + 12
        h = max(t.height for _, t in tiles) + 48
        cols = min(6, len(tiles))
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (w * cols + 8, h * rows + 8), bg)
        draw = ImageDraw.Draw(sheet)
        for i, (name, t) in enumerate(tiles):
            x, y = 4 + (i % cols) * w, 4 + (i // cols) * h
            sheet.paste(t, (x + 6, y + 38))
            draw.text((x + 6, y + 6), "%s  ×%.2f" % (name, z), fill=(240, 240, 248), font=f)
        sheet.save(out)
        print("已写出:", out, sheet.size)
        return
    elif cmd == "strip":
        out, k = sys.argv[2], float(sys.argv[3])
        # 连拍的文件名是相位编号，不是先后顺序：按文件的修改时间排成真实的先后
        rows = []
        for item in sys.argv[4:]:
            tpl, rect = item.rsplit(":", 1)
            frames = sorted(range(10), key=lambda i: os.path.getmtime(tpl.format(i=i)))
            rows.append([(tpl.format(i=i), "第%d张 P%d" % (n + 1, i), tuple(int(v) for v in rect.split(","))) for n, i in enumerate(frames)])
        cols, bg2 = 5, (44, 52, 76)
        cw = int(max(w * k for row in rows for _, _, (_, _, w, _) in row)) + 6
        ch = int(max(h * k for row in rows for _, _, (_, _, _, h) in row)) + 44
        width = 54 + cols * cw + 10
        height = sum(ch * ((len(row) + cols - 1) // cols) + 10 for row in rows) + 10
        sheet = Image.new("RGB", (width, height), bg)
        draw = ImageDraw.Draw(sheet)
        y = 10
        for row in rows:
            for n, (shot, label, (cx, cy, w, h)) in enumerate(row):
                x = 54 + (n % cols) * cw
                yy = y + (n // cols) * ch
                crop = Image.open(shot).convert("RGB").crop((cx, cy, cx + w, cy + h)).resize((round(w * k), round(h * k)), Image.NEAREST)
                sheet.paste(crop, (x + 3, yy + 24))
                draw.text((x + 3, yy + 2), label, fill=(240, 240, 248), font=f)
                draw.rectangle([x + 2, yy + 23, x + crop.width + 3, yy + crop.height + 24], outline=bg2)
            draw.text((10, y + 26), "相位", fill=(240, 240, 248), font=f)
            y += ch * ((len(row) + cols - 1) // cols) + 10
        sheet.save(out)
        print("已写出:", out, sheet.size)
        return
    else:
        print(__doc__)
        sys.exit(1)
    tiles = []
    for shot, k, title, (x, y, w, h) in items:
        crop = Image.open(shot).convert("RGB").crop((x, y, x + w, y + h)).resize((round(w * k), round(h * k)), Image.NEAREST)
        tile = Image.new("RGB", (crop.width + 16, crop.height + 56), bg)
        tile.paste(crop, (8, 44))
        ImageDraw.Draw(tile).text((8, 8), title, fill=(240, 240, 248), font=f)
        tiles.append(tile)
    cols = min(4, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    tw, th = max(t.width for t in tiles), max(t.height for t in tiles)
    sheet = Image.new("RGB", (tw * cols + 8 * (cols + 1), th * rows + 8 * (rows + 1)), bg)
    for i, tile in enumerate(tiles):
        sheet.paste(tile, (8 + (i % cols) * (tw + 8), 8 + (i // cols) * (th + 8)))
    sheet.save(out)
    print("已写出:", out, sheet.size)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""游戏图标 icon.svg：夜色的圆角底 + 一盏红灯笼，灯身上一个金色的"守"字。

保持是 SVG，根元素和原文件一样（只有 xmlns、width="128" height="128"，没有 viewBox）；icon.svg.import 不动。
Godot 自己导入 SVG，所以只用矩形、椭圆、折线路径，不用文字、滤镜、蒙版、渐变、外部字体。
"守"字的轮廓是站酷快乐体（游戏界面在用的字体）里的三圈折线（SHOU：字体坐标，1000 号字，y 朝上），
这里直接换算成图标上的坐标写成路径——这个字在字体里本来就是三圈直线，没有曲线。

颜色和游戏一致：底是夜色的墨绿（石绿压暗），灯笼是朱砂，灯钮、灯盖、灯穗绳是金色，字是浅金，灯笼底下两道石绿的水纹。

用法: python3 -I icon_svg.py [预览图的输出路径] [输出目录]
  不带参数就自检并把 icon.svg 写进工程（tools/art/regen_all.sh 就是这么跑的）。
  给了预览图的路径就再出预览图：装了 cairosvg 的话把图标按 128、64、32、16 像素各渲染一遍，看小尺寸下还认不认得出。
  再给一个输出目录就写到那里，不写进工程。
写 SVG 和自检只用到标准库；渲染预览要用 cairosvg（没装就跳过）；核对字体要用 fontTools（没装就跳过）。
"""
import io
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# 原版的图标：只在出预览图时对照用（SW_ORIG = 原版工程里放着 assets/ 和 icon.svg 的目录）
REF = os.path.abspath(os.environ["SW_ORIG"]) if os.environ.get("SW_ORIG") else None
# 原版图标根元素的标签和属性（量好的数在同目录的 originals.json 里）
ORIG_ROOT = json.load(open(os.path.join(HERE, "originals.json"), encoding="utf-8"))["icon.svg"]["svg_root"]

OUT_REL = "icon.svg"

# "守"在站酷快乐体里的三圈轮廓（用 fontTools 从字形 uni5B88 里取出来的，只有 moveTo / lineTo / closePath）
SHOU = [
    [(61, 587), (105, 644), (417, 660), (379, 741), (464, 781), (518, 666), (810, 681), (859, 627), (835, 462), (742, 476), (757, 585), (165, 552), (182, 466), (90, 447)],
    [(679, 297), (670, -18), (611, -61), (382, -1), (406, 90), (577, 45), (584, 300), (131, 314), (134, 407), (587, 395), (591, 524), (686, 520), (682, 392), (806, 389), (804, 294)],
    [(182, 239), (272, 269), (341, 64), (251, 34)],
]
SHOU_BOUNDS = (61, -61, 859, 781)            # 这三圈轮廓的范围（字体坐标）

NIGHT, NIGHT_EDGE = "#0F2E33", "#06191D"     # 底、底的边
RED, RED_DARK = "#E2533C", "#C2412E"         # 灯笼、灯笼上的竹骨
GOLD, GOLD_LIGHT = "#E9B94C", "#F7D774"      # 灯钮、灯盖、灯穗绳；灯身上的字
JADE = "#3FA79B"                             # 水纹（石绿）

ALLOWED_TAGS = {"svg", "rect", "ellipse", "circle", "path", "polygon", "line"}
ALLOWED_ATTRS = {"xmlns", "width", "height", "x", "y", "rx", "ry", "cx", "cy", "r", "d", "points", "x1", "y1", "x2", "y2",
                 "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin"}


def glyph_path(cx, cy, height):
    """把 守 字写成一条路径：缩放到 height 像素高、中心放在 (cx, cy)。SVG 的 y 朝下，所以字体坐标的 y 要反过来"""
    x0, y0, x1, y1 = SHOU_BOUNDS
    k = height / (y1 - y0)
    ox, oy = cx - (x0 + x1) / 2 * k, cy + (y0 + y1) / 2 * k
    return "".join("M" + "L".join("%.1f %.1f" % (ox + x * k, oy - y * k) for x, y in contour) + "Z" for contour in SHOU)


def svg_text():
    return """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
  <rect x="2" y="2" width="124" height="124" rx="18" fill="%s" stroke="%s" stroke-width="4"/>
  <path d="M20 111h16M92 111h16" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>
  <circle cx="64" cy="19" r="4" fill="none" stroke="%s" stroke-width="2.5"/>
  <rect x="59" y="23" width="10" height="9" rx="3" fill="%s"/>
  <rect x="46" y="30" width="36" height="9" rx="3" fill="%s"/>
  <ellipse cx="64" cy="63" rx="39" ry="29" fill="%s"/>
  <path d="M64 34v58M49 36q-13 27 0 54M79 36q13 27 0 54M35 46q-8 17 0 34M93 46q8 17 0 34" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>
  <rect x="49" y="88" width="30" height="8" rx="3" fill="%s"/>
  <path d="M64 96v8" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"/>
  <circle cx="64" cy="105" r="3.2" fill="%s"/>
  <path d="M61 108l-1 10M64 108.5v11M67 108l1 10" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"/>
  <path d="%s" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>
</svg>
""" % (NIGHT, NIGHT_EDGE, JADE, GOLD, GOLD, GOLD, RED, RED_DARK, GOLD, GOLD, GOLD, RED, glyph_path(64, 63, 40), GOLD_LIGHT, GOLD_LIGHT)


def local(tag):
    """去掉命名空间：{http://www.w3.org/2000/svg}rect → rect"""
    return tag.rsplit("}", 1)[-1]


def check(text):
    """自检：是合法的 XML；根元素的属性和原文件一模一样；只用了矩形、椭圆、路径这些基本元素和它们的基本属性。
    返回 True 表示合格"""
    ok = True
    root = ET.fromstring(text)
    orig = ORIG_ROOT
    print("  %s" % OUT_REL)
    if root.tag != orig["tag"] or root.attrib != orig["attrib"]:
        print("    [不合格] 根元素和原文件不一样：新图 %s %s，原版 %s %s" % (root.tag, root.attrib, orig["tag"], orig["attrib"])); ok = False
    if text.count('xmlns="') != 1:
        print("    [不合格] xmlns 只应该在根元素上出现一次"); ok = False
    n = 0
    for el in root.iter():
        tag = local(el.tag)
        if tag == "svg":
            continue
        n += 1
        if tag not in ALLOWED_TAGS:
            print("    [不合格] 用了 %s（只能用矩形、椭圆、圆、直线、折线路径）" % tag); ok = False
        for k in el.attrib:
            if k not in ALLOWED_ATTRS:
                print("    [不合格] %s 上有不允许的属性 %s" % (tag, k)); ok = False
        if (el.text or "").strip() or len(el):
            print("    [不合格] %s 里面有文字或者嵌套了别的元素" % tag); ok = False
        for k in ("fill", "stroke"):
            if (el.get(k) or "").startswith("url("):
                print("    [不合格] 用了引用别的元素的填充（渐变、图案之类）"); ok = False
    if (root.text or "").strip():
        print("    [不合格] 根元素里直接写了文字"); ok = False
    print("    根元素的属性：xmlns 和 %s；一共 %d 个元素，都是矩形、椭圆、路径" % (root.attrib, n))
    print("    %s" % ("合格" if ok else "不合格"))
    return ok


def check_font():
    """装了 fontTools 的话，核对 SHOU 和字体里的轮廓还是一致的。一致返回 True，不一致返回 False，没装返回 None"""
    try:
        from fontTools.pens.recordingPen import RecordingPen
        from fontTools.ttLib import TTFont
    except ImportError:
        return None
    font = TTFont(os.path.join(ROOT, "assets/fonts/ZCOOLKuaiLe-Regular.ttf"))
    pen = RecordingPen()
    font.getGlyphSet()[font.getBestCmap()[ord("守")]].draw(pen)
    contours, cur = [], None
    for op, args in pen.value:
        if op == "moveTo":
            cur = [tuple(int(round(v)) for v in args[0])]
        elif op == "lineTo":
            cur.append(tuple(int(round(v)) for v in args[0]))
        elif op == "closePath":
            contours.append(cur)
            cur = None
        else:
            return False
    return contours == SHOU


def preview(path, text):
    """用 cairosvg 把图标按几种尺寸渲染出来：上面一行是 128、64、32、16 像素（放在浅色底上），下面是放大 4 倍的 128 和原版的图标"""
    try:
        import cairosvg
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("  没装 cairosvg（或 Pillow），跳过渲染预览")
        return
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 16)
    bg, fg = (28, 34, 52), (235, 235, 245)

    def render(svg, s):
        return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=s, output_height=s))).convert("RGBA")

    # 原版的图不在手边（没设 SW_ORIG）时，最后那一格不画
    old = open(os.path.join(REF, OUT_REL), encoding="utf-8").read() if REF else None
    sheet = Image.new("RGB", (760, 736), bg)
    dr = ImageDraw.Draw(sheet)
    x = 8
    for label, svg, s in (("新图 128", text, 128), ("新图 64", text, 64), ("新图 32", text, 32), ("新图 16", text, 16), ("原版 128", old, 128)):
        if svg is None:
            continue
        box = Image.new("RGB", (140, 140), (232, 232, 232))
        t = render(svg, s)
        box.paste(t, ((140 - s) // 2, (140 - s) // 2), t)
        sheet.paste(box, (x, 28))
        dr.text((x + 4, 8), label, fill=fg, font=font)
        x += 150
    dr.text((20, 176), "新图放大到 512（上面一行是浅色底上的原大）", fill=fg, font=font)
    big = render(text, 512)
    sheet.paste(big, (20, 200), big)
    sheet.save(path)
    print("预览图:", path, sheet.size)


if __name__ == "__main__":
    args = sys.argv[1:]
    text = svg_text()
    same = check_font()
    if same is False:
        sys.exit("字体里的 守 和脚本里存下来的轮廓对不上了：请照文件开头的说明，重新从字体里取一遍")
    if same is None:
        print("（没装 fontTools，没有核对字体里的 守 和脚本里的轮廓）")
    ok = check(text)
    out_dir = args[1] if len(args) > 1 else ROOT          # 不给输出目录就写进工程
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, OUT_REL)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("已写出", out, "%d 字节" % len(text.encode("utf-8")))
    if len(args) > 0:
        preview(args[0], text)
    sys.exit(0 if ok else 1)

#!/usr/bin/env python3
"""界面上的九宫格底板和边框（assets/sprites/ui/nine-patch.png、nine-patch-border.png）。

两张都是 311×316 的画布。原版是手绘的圆角方块（实心的那张）和圆角方框（只有一圈边的那张）：
线条有点歪，四条边都不是直的（下边和右边外缘上下差四五个像素），四个角的弧也不太匀。
新图画成"月洞门"式的圆角方，再过一遍手绘化（线抖、粗细变化，见下面的 HAND_INSET）：
  - 外缘、内缘的平均位置不变，落在原版量出来的位置上（场景里的 patch_margin 就是按这些位置定的）；
    手绘化以后四条边微微鼓着或瘪着（两三个像素），边的粗细也在变。
    外缘用两把尺子量（透明度大于 24、大于 127）都和原版一模一样，内孔（x 53..257、y 53..258）也和原版一致；
  - 边框的四个角是更大、更饱满的圆弧（江南园林里月洞门、海棠窗的那种弧度）：半径 74 到 79 像素（原版约 60），
    四个角略有不同，每段弧还各有半像素到两个像素的鼓或瘪，内外弧的鼓瘪不一样，所以角上的边宽有两三个像素的出入——
    留着手绘的不匀，不像尺子画出来的。四条边的中段不受影响；
  - 底板会被九宫格拉伸，四个角的弧必须整个落在场景里最小的那一块角（82 像素宽，减去外缘离画布边的 32 像素）里面，
    所以半径只有 46 到 48.5 像素，比原版略方一点。边框从不被拉伸，不受这个限制。
没有加任何角花：边框在游戏里最小的用法是纪录页、结算页里每行纪录的头像框，只有 50 像素宽（一圈边才三个多像素），
其次是主界面正下方的技能按钮（116 像素，边宽七八个像素）和选人卡片（128 像素）。
角上再小的东西都会被着色器的抖动搅花。
实心的那张底板（nine-patch.png）在游戏里几乎看不见：纪录行的底色那一层是不显示的（节点是隐藏的，透明度也只有 6%），
解锁新角色的提示又是一块接近纯黑的小面板。所以它只有自检和本地的拉伸预览，没有游戏里的实拍。

用法: python3 -I nine_patch.py [预览图的输出路径]
  不带参数只把两张图写到工程里并自检；带了参数再出一张预览图
  （两张图的对比图，加上边框按游戏里的大小缩小后的样子：技能按钮 116 像素、选人卡片 128 像素）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL_PANEL = "assets/sprites/ui/nine-patch.png"         # 实心的底板
REL_BORDER = "assets/sprites/ui/nine-patch-border.png"  # 只有一圈边
ZOOM_MIN = 0.37                            # 自检用的：主界面正下方的技能按钮，整张 116 像素（选人卡片是 128 像素，0.41；纪录行的头像框只有 50 像素、0.16，靠实拍确认）

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

CANVAS = doodle.orig_size(REL_BORDER)      # (311, 316)

# 位置都是从原版量出来的（像素坐标，含两端）。外缘取原版图形的范围，内缘取原版内孔的范围
PANEL_BOX = doodle.orig_box(REL_PANEL)     # (32, 33, 247, 251)：x 32..278，y 33..283
BORDER_BOX = doodle.orig_box(REL_BORDER)   # (32, 32, 247, 251)：x 32..278，y 32..282
INNER = (53, 53, 257, 258)                 # 边框内孔的像素范围：x 53..257，y 53..258（和原版内孔一致）

# 边框四个角外弧的半径：左上、右上、右下、左下（原版约 60）。边框在游戏里都是整张贴图（选人卡片、技能按钮、纪录行的头像框、
# 结算页的分数框），从来不会被九宫格拉伸，所以弧可以画得又大又饱满。内弧的半径 = 外弧减去这一角的边宽，和原版的边宽一样
RADII = (77.0, 75.0, 79.0, 74.0)
# 底板四个角的半径就小得多。底板会被九宫格拉伸（解锁提示、纪录行的底色），场景里最小的那一块角只有 82 像素宽，
# 减去外缘离画布边的 32 像素，放得下弧的宽度只剩 50 像素左右；弧伸出角块的话，拉伸的时候伸出去的那一段会被拉长，角上就出折角。
# （原版的弧约 60，本来就伸出角块四五个像素。）
PANEL_RADII = (48.0, 46.5, 48.5, 46.0)
PANEL_BUMPS = (0.012, -0.010, 0.015, -0.012)


def px(x0, y0, x1, y1):
    """像素范围（含两端）→ 连续坐标的框（左上、右下，右下不含）"""
    return (float(x0), float(y0), float(x1) + 1.0, float(y1) + 1.0)


# 外轮廓从这个框的四边往里收这么多。原版的边缘是一条渐渐变透明的手绘线，新图是先按 8 倍大小画、再缩回来的，
# 几何边界正好压在像素线上时，边界外那一列像素还会剩下三十多的透明度。往里收这么多以后：
# 用原版量范围的尺子（透明度大于 24）量，范围和原版一模一样；按透明度大于 127 再量一遍，也和原版一模一样
# （试过 0.65 到 0.9 都行，取中间的 0.75）
EDGE = 0.75


def box_px(box):
    """orig_box 量出来的 (x, y, 宽, 高) → 像素范围（含两端）"""
    return (box[0], box[1], box[0] + box[2] - 1, box[1] + box[3] - 1)


def inset(box, more=0.0):
    """把框的四边往里收 EDGE（再外加 more）"""
    return (box[0] + EDGE + more, box[1] + EDGE + more, box[2] - EDGE - more, box[3] - EDGE - more)


# 手绘化（doodle.handdraw_inplace）：原版是马克笔手画的，四条边都微微鼓着或瘪着，边的粗细沿着轮廓在变。
# 第一版为了九宫格拉伸干净，把四边画成了严格的直线，太板正。现在外轮廓先往里收一点再手绘化，
# 线往外鼓的地方正好到原版的范围；只做线抖和粗细变化，不转不拉，所以外缘、内缘的平均位置不变
HAND_INSET = 2.5                              # 外轮廓先往里收这么多（像素）
HAND_PANEL = dict(seed=911, wobble=0.009, thick=0.012, grain=0.003)   # 底板会被拉伸，抖得轻一点
HAND_BORDER = dict(seed=913, wobble=0.011, thick=0.015, grain=0.003)   # 边框在游戏里都是整张贴图，从不拉伸


# 四个角的弧各自带一点鼓或瘪（比例：外弧的半径在中段鼓起或收进这么多，角的两端不动，所以和直边还是相切的）。
# 外弧和内弧的鼓瘪不一样，角上的边宽就有两三个像素的出入——手画的线就是这样不匀
BUMP_OUT = (0.022, -0.016, 0.026, -0.020)   # 左上、右上、右下、左下
BUMP_IN = (-0.030, 0.024, -0.018, 0.030)


def outline(box, radii, bumps):
    """圆角方的轮廓点列（顺时针一圈，屏幕坐标 y 向下）：四条边的中段是直线，四个角是带一点鼓瘪的四分之一圆弧"""
    x0, y0, x1, y1 = box
    rt, rr, rb, rl = radii
    pts = []

    def corner(cx, cy, r, a0, bump):        # 从角 a0 起顺时针转 90 度；弧的中段按 bump 鼓起（正）或收进（负）
        n = 60
        for i in range(n + 1):
            t = i / n
            a = a0 + math.pi / 2 * t
            rad = r * (1 + bump * math.sin(math.pi * t) ** 2)
            pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))

    # 直边只用两个端点，中段不插任何点，所以是严格的直线
    pts.append((x0 + rl, y1))
    corner(x0 + rl, y1 - rl, rl, math.pi / 2, bumps[3])        # 左下角：从下边转到左边
    pts.append((x0, y0 + rt))
    corner(x0 + rt, y0 + rt, rt, math.pi, bumps[0])            # 左上角：从左边转到上边
    pts.append((x1 - rr, y0))
    corner(x1 - rr, y0 + rr, rr, -math.pi / 2, bumps[1])       # 右上角：从上边转到右边
    pts.append((x1, y1 - rb))
    corner(x1 - rb, y1 - rb, rb, 0.0, bumps[2])                # 右下角：从右边转到下边
    return pts


def rounded(w, h, box, radii, bumps=BUMP_OUT):
    """圆角方的 Mask：实心部分就是上面那条轮廓围起来的地方"""
    m = doodle.Mask(w, h)
    m.polygon(outline(box, radii, bumps))
    return m


def panel():
    """实心的底板"""
    return rounded(CANVAS[0], CANVAS[1], inset(px(*box_px(PANEL_BOX)), HAND_INSET), PANEL_RADII, PANEL_BUMPS)


def border():
    """只有一圈边的边框：外轮廓减去内孔。内弧的半径是外弧减去边宽（左右上三边 21 像素、下边 24 像素）"""
    outer, inner = inset(px(*box_px(BORDER_BOX)), HAND_INSET), px(*INNER)    # 内孔不收：它的范围本来就和原版一模一样
    wl, wt, wr, wb = inner[0] - outer[0], inner[1] - outer[1], outer[2] - inner[2], outer[3] - inner[3]
    m = rounded(CANVAS[0], CANVAS[1], outer, RADII, BUMP_OUT)
    # 内孔四个角的半径：外弧减去这个角上两条边里较窄的那条边宽
    hole = rounded(CANVAS[0], CANVAS[1], inner, (RADII[0] - min(wl, wt), RADII[1] - min(wt, wr),
                                                 RADII[2] - min(wr, wb), RADII[3] - min(wb, wl)), BUMP_IN)
    m.cut(hole)
    return m


def preview(path, panel_img, border_img):
    """预览：原版和新图的边框按游戏里的大小（116、128 像素）缩小后放大五倍，底色用深色"""
    old = doodle.orig(REL_BORDER)            # 原版的图不在手边（没设 SW_ORIG）时是 None，预览图里就没有"原版"那两格
    tiles = []
    for name, im in (("原版", old), ("新图", border_img)):
        if im is None:
            continue
        for size in (116, 128):
            a = im.split()[3].resize((size, size), Image.LANCZOS)
            t = Image.new("RGB", (size + 12, size + 12), (10, 24, 22))
            t.paste(Image.new("RGB", (size, size), (205, 215, 210)), (6, 6), a)
            tiles.append((name, size, t.resize((t.width * 4, t.height * 4), Image.NEAREST)))
    w = sum(t.width for _, _, t in tiles) + 10 * (len(tiles) - 1)
    h = max(t.height for _, _, t in tiles) + 30
    sheet = Image.new("RGB", (w, h), (28, 34, 52))
    draw = ImageDraw.Draw(sheet)
    x = 0
    for name, size, t in tiles:
        sheet.paste(t, (x, 26)); draw.text((x + 4, 6), "%s %d 像素 x4" % (name, size), fill=(235, 235, 245))
        x += t.width + 10
    sheet.save(path)


if __name__ == "__main__":
    p_img = doodle.full(doodle.handdraw_inplace(panel().alpha(), **HAND_PANEL), CANVAS)
    b_img = doodle.full(doodle.handdraw_inplace(border().alpha(), **HAND_BORDER), CANVAS)
    p_img.save(os.path.join(ROOT, REL_PANEL))
    b_img.save(os.path.join(ROOT, REL_BORDER))
    print("已写出", REL_PANEL, "和", REL_BORDER)
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("底板 nine-patch  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL_PANEL), REL_PANEL),
                                          ("边框 nine-patch-border  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL_BORDER), REL_BORDER)], cell=300)
        preview(os.path.splitext(sys.argv[1])[0] + "_small.png", p_img, b_img)
        print("预览图:", sys.argv[1], "和", os.path.splitext(sys.argv[1])[0] + "_small.png")
    doodle.check(os.path.join(ROOT, REL_PANEL), REL_PANEL, zoom=ZOOM_MIN, kind="2d")
    doodle.check(os.path.join(ROOT, REL_BORDER), REL_BORDER, zoom=ZOOM_MIN, kind="2d")

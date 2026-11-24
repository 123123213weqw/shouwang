#!/usr/bin/env python3
"""格子上的装饰二（assets/sprites/foliages/algae-1.png）：两株芦苇——细长的秆，顶上一支芦花穗，几片尖叶子。

原版是两根分叉的水藻（256×256 的画布，图形在 x 50..183、y 125..232，左右两块，中间隔着 40 像素）。
新图照原版的布局：左边一株高的（顶到范围的最上边），右边一株矮的，两株是分开的两块，间距不比原版近。
  - 秆：直直地往上长，下端落在原版两块水藻的根上（游戏里正好立在格子面上）；
  - 穗：秆顶上一支饱满的芦花穗，下面圆、上面尖，比秆粗一截——一眼认出是芦苇就靠它；
  - 叶：从秆的下半截斜着伸出去的长尖叶，基部宽、先端渐尖。
线条的粗细照原版水藻来（原版 15 到 20 像素宽），不比它更细。
芦苇在中国诗词里就是"蒹葭"（《诗经》"蒹葭苍苍，白露为霜"），是江南水边最常见的东西，没有任何日本元素。

用法: python3 -I reeds.py [预览图的输出路径]
  不带参数只把图写到工程里并自检；带了参数再出一张对比图（原版 | 新图 | 叠在一起）。
只依赖 Pillow 和 numpy（经 doodle.py）。
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REL = "assets/sprites/foliages/algae-1.png"
ZOOM_MIN = 0.24                            # 最小的情况：和 algae.png 一样是第 12 关最远一排

spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doodle)

CANVAS = doodle.orig_size(REL)             # (256, 256)
BOX = doodle.orig_box(REL)                 # 原版图形的范围 (50, 125, 134, 108)
W, H = BOX[2], BOX[3]                      # 设计范围：134 宽、108 高

STALK_W = 14.0                             # 秆的宽度
PLUME_W = 26.0                             # 穗最粗处的宽度（不算两侧毛茸茸的小鼓包）。穗要比秆粗出一大截，才不像一个芽苞
LEAF_W = 12.5                              # 叶子基部的宽度

# 左株（高）：秆从根到穗底经过的点；穗底、穗尖；叶子 = (秆上的出发点, 叶尖, 弯的方向和大小)。叶子都斜着往上伸，
# 像原版左边那根水藻的分叉；右株（矮）顶在范围的上半截，和原版右边那根水藻一样矮一截
# 左株（高）：秆从根往右上略斜，穗偏向右边；一片长叶往左上斜伸，一片短些的往右斜伸。
# 右株（矮）：穗偏向左边，和左株错开；顶在范围的上半截，和原版右边那根水藻一样矮一截。
# 叶子 = (秆上的出发点, 叶子中线的控制点, 叶尖)
LEFT = dict(
    stalk=[(24, H - STALK_W / 2 - 0.5), (27, 72), (30, 47)],
    plume=((30, 47), (44, 3)),
    leaves=[((27, 86), (12, 72), (1, 38)), ((30, 76), (46, 68), (59, 46))],
)
RIGHT = dict(
    stalk=[(123, H - STALK_W / 2 - 0.5), (120, 80)],
    plume=((120, 80), (112, 38)),
    leaves=[((124, 98), (111, 88), (105, 64))],
)


def plume(base, tip, w, lean=1.0):
    """芦花穗：底下从秆的宽度起，先鼓成最宽，往上渐渐收窄，最后收成一个偏向一侧的细尖（像一撇羽毛）。
    lean 是尖偏向哪一侧、偏多少。穗的两侧再各鼓出两个小圆，轮廓毛毛糙糙的，才像芦花而不像一个花苞"""
    m = doodle.Mask(W, H)
    bx, by = base
    tx, ty = tip
    dx, dy = tx - bx, ty - by
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L                       # 和穗垂直的方向
    prof = [(0.0, 0.32), (0.18, 0.44), (0.42, 0.42), (0.66, 0.33), (0.86, 0.17)]

    def side(t, k, c=0.0):
        return (bx + dx * t + nx * (w * k + lean * c), by + dy * t + ny * (w * k + lean * c))
    m.shape([side(t, k) for t, k in prof] + [(tx, ty, 1)] + [side(t, -k) for t, k in prof][::-1])
    # 毛茸茸的小鼓包：沿穗两侧交错着放，越往上越小
    for t, k, r in ((0.16, 0.50, 5.0), (0.34, -0.52, 4.6), (0.52, 0.50, 4.0), (0.70, -0.44, 3.2)):
        px, py = side(t, k)
        m.ellipse((px - r, py - r, px + r, py + r))
    m.soften(0.5)
    return m


def leaf(root, ctrl, tip):
    """一片细长的叶（芦苇的叶是线形的：基部宽，中段几乎一样宽，先端拖成细尖）。
    叶子的中线是从 root（秆上的出发点）出发、往 ctrl 的方向弯出去、到 tip（叶尖）的一条曲线"""
    m = doodle.Mask(W, H)
    pts = []
    n = 14
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((u * u * root[0] + 2 * u * t * ctrl[0] + t * t * tip[0], u * u * root[1] + 2 * u * t * ctrl[1] + t * t * tip[1]))
    side = [[], []]
    for i, (x, y) in enumerate(pts):
        t = i / n
        x0, y0 = pts[max(i - 1, 0)]
        x1, y1 = pts[min(i + 1, n)]
        L = math.hypot(x1 - x0, y1 - y0) or 1.0
        nx, ny = -(y1 - y0) / L, (x1 - x0) / L
        w = LEAF_W * (1 - t ** 2.2) ** 0.75          # 半宽：基部是 LEAF_W 的一半，中段还有七八成，到尖上收到零
        side[0].append((x + nx * w / 2, y + ny * w / 2))
        side[1].append((x - nx * w / 2, y - ny * w / 2))
    m.polygon(side[0] + side[1][::-1])
    return m


def plant(p):
    """一株芦苇：秆 + 穗 + 叶，全连在一起"""
    m = doodle.Mask(W, H)
    m.path(p["stalk"], STALK_W)
    m.union(plume(p["plume"][0], p["plume"][1], PLUME_W))
    for root, ctrl, tip in p["leaves"]:
        m.union(leaf(root, ctrl, tip))
    m.soften(0.9)                           # 把叶子和秆接缝的地方抹圆
    return m


def build():
    """返回设计范围里的透明度图（高分辨率）：两株芦苇，分开的两块"""
    m = doodle.Mask(W, H)
    m.union(plant(LEFT))
    m.union(plant(RIGHT))
    return m.alpha()


def render(alpha):
    """把设计范围里的图等比缩进原版图形的范围、放到 256×256 的画布上（纯白）"""
    return doodle.place(alpha, CANVAS, BOX)


if __name__ == "__main__":
    img = render(build())
    img.save(os.path.join(ROOT, REL))
    print("已写出", REL)
    if len(sys.argv) > 1:
        doodle.review_sheet(sys.argv[1], [("algae-1 芦苇  原版 | 新图 | 叠在一起", os.path.join(ROOT, REL), REL)], cell=300)
        print("预览图:", sys.argv[1])
    doodle.check(os.path.join(ROOT, REL), REL, zoom=ZOOM_MIN, kind="3d")

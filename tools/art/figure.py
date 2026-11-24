"""角色（头 + 身子）的脚本共用的小工具。每个元素一个脚本（body.py、fisher.py、boatboy.py、netgirl.py、
peddler.py、drummer.py），画法都一样：直接在 236×248 的画布坐标里画（doodle.Mask(236, 248)），图形落在原版
那张图的范围里（doodle.orig_box），最后用 doodle.full() 缩回原尺寸。这里管四件事：

  1. 坐标关系（stack、INGAME）。头和身子是上下叠在一起的两张同样大的画布，上下对齐的时候身子的画布比头的
     低 SHIFT 行、身子在后面、头在前面。但游戏里的镜头是俯视的透视镜头：头比身子离镜头近一点，在屏幕上
     身子会相对头往右下错开，整个精灵竖向还被压扁——第 1 关量到的是错开约 (21, 87) 个纹理像素、压到 0.68，
     第 12 关约 (41, 89)、压到 0.54，而且错开多少随主角在棋盘上的位置变（debug_rects 实测，挪了两格以后
     错开从 12 变到 9 个屏幕像素）。预览图里照这个样子再叠一遍，离线就能看出接缝行不行。
  2. 出图前查一遍（verify、pure_white）：图形有没有超出原版的范围、是不是撑满了。
  3. 几个共用的小形状（mirrored、flip、eyes）。
  4. 预览图（preview、sheet、lineup）：上下对齐叠起来的新图和原版、照游戏里第 1 关和第 12 关的样子缩小的图、
     六个头并排。

用法（在元素脚本里，见 body.py 的开头怎么加载）：
    fig = 加载进来的这个模块；fig.doodle 就是 doodle.py
    img = fig.to_canvas(画好的 alpha)
    fig.verify(img, "assets/sprites/characters/body.png")
    fig.preview(输出路径, "标题", 头的路径, 身子的路径, 头的原版相对路径, 身子的原版相对路径)

只依赖 Pillow。真正的验收还是要进游戏连拍（tools/playtest/agent.sh）。
"""
import importlib.util
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
CANVAS = (236, 248)
CHARS = "assets/sprites/characters/"
SHIFT = 102                      # 上下对齐的时候，身子的画布比头的低多少个纹理像素（和 watchman.py 一致）
WHITE = (255, 255, 255)
TINT = (40, 84, 74)              # 预览时给身子染的颜色（游戏里是关卡的颜色压暗）
BG = (14, 22, 40)


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


doodle = _load("doodle")


def box(rel):
    """原版那张图里图形的范围 (x, y, 宽, 高)"""
    return doodle.orig_box(rel)


def to_canvas(alpha, turn=True):
    """高分辨率的透明度图 → 236×248 的纯白剪影。
    先做一遍手绘化（doodle.handdraw_inplace）：原版的头是马克笔手画的，左右不一样、线是抖的；
    第一版是左右对称的圆和弧，太板正。线抖一抖、粗细变一变，头再整体歪两度上下（turn=False 就不歪，
    共用的身子用它：身子要立正）。图形始终留在原来的位置上，所以头和身子的接缝、胸口挡粒子的那一块都不受影响"""
    # 手绘化会把轮廓往外推一两个像素。先绕着图的中心把整张图缩一点点（一个多像素），
    # 推出去的地方就落回原来的范围里，图形的范围和原版仍然对得上（脖子、肩头的位置也只动一个像素）
    w, h = alpha.size
    nw, nh = max(1, round(w * 0.982)), max(1, round(h * 0.982))
    shrunk = Image.new("L", alpha.size, 0)
    shrunk.paste(alpha.resize((nw, nh), Image.LANCZOS), ((w - nw) // 2, (h - nh) // 2))
    alpha = doodle.handdraw_inplace(shrunk, turn=turn, wobble=0.009, thick=0.010, grain=0.002, tilt=1.5, squash=0.02)
    # 线抖是一整片一起挪的，图形可能整体跑偏一两个像素：把图形范围的中心挪回去，图形还在原来的位置上
    b0, b1 = shrunk.getbbox(), alpha.getbbox()
    if b0 and b1:
        dx, dy = round((b0[0] + b0[2] - b1[0] - b1[2]) / 2.0), round((b0[1] + b0[3] - b1[1] - b1[3]) / 2.0)
        if dx or dy:
            alpha = ImageChops.offset(alpha, dx, dy)
    return doodle.full(alpha, CANVAS, WHITE)


def load(path):
    return Image.open(path).convert("RGBA")


def orig(rel):
    return doodle.orig(rel)


def bbox(img):
    a = img.split()[3].point(lambda v: 255 if v > 127 else 0).getbbox()
    return (a[0], a[1], a[2] - a[0], a[3] - a[1]) if a else None


def verify(img, rel, ref=None, slack=1, fill=8):
    """图形的范围要落在原版的范围里（最多超出 slack 像素），而且至少高低撑满、左右差不超出 fill 像素
    （和 doodle.place 的"等比缩进同一个范围"一个意思：高矮撑满，左右居中，差一点没关系）。返回 True/False，并把量到的数打印出来"""
    b, ob = bbox(img), box(ref or rel)
    ok = True
    over = (ob[0] - b[0], ob[1] - b[1], b[0] + b[2] - ob[0] - ob[2], b[1] + b[3] - ob[1] - ob[3])
    short = (-over[0], -over[1], -over[2], -over[3])
    if max(over) > slack:
        print("  [不合格] %s：图形超出了原版的范围（左 %d、上 %d、右 %d、下 %d 像素，允许 %d 以内）" % ((rel,) + over + (slack,)))
        ok = False
    if short[1] > 3 or short[3] > 3 or short[0] > fill or short[2] > fill:
        print("  [不合格] %s：图形没有撑满原版的范围（左 %d、上 %d、右 %d、下 %d 像素；上下允许 3 以内，左右允许 %d 以内）" % (
            (rel,) + short + (fill,)))
        ok = False
    if ok:
        print("  范围核对 %s：原版 (%d,%d) %d×%d，新图 (%d,%d) %d×%d，差 (左 %d、上 %d、右 %d、下 %d)" % (
            (rel,) + ob + b + short))
    return ok


def mirrored(points, cx):
    """给出左边一半的锚点（从顶上中间起、沿着左边往下到底下中间为止），补上关于 x = cx 对称的右半边"""
    return list(points) + [(2 * cx - x, y) + tuple(rest) for x, y, *rest in reversed(points)]


def flip(points, cx):
    """把一串锚点关于 x = cx 左右翻过来（画对称的另一只耳朵、另一条辫子用）"""
    return [(2 * cx - x, y) + tuple(rest) for x, y, *rest in points]


def eyes(centers, rx, ry):
    """眼睛（挖空的圆点）：centers 是各个眼睛的中心，rx、ry 是半径。
    返回一张实心部分就是眼睛的 Mask，用 head.cut(eyes(...)) 挖下去"""
    d = doodle.Mask(CANVAS[0], CANVAS[1])
    for x, y in centers:
        d.ellipse((x - rx, y - ry, x + rx, y + ry))
    return d


def pure_white(img):
    """不透明的像素是不是都是纯白 (255,255,255)"""
    import numpy as np
    arr = np.asarray(img.convert("RGBA"))
    op = arr[arr[..., 3] == 255]
    return len(op) > 0 and int(op[:, :3].min()) == 255


def write(img, out_dir, name):
    """把图写进输出目录；不给输出目录就写进工程的 assets/sprites/characters/（别的画图脚本都是默认写进工程）"""
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, name)
    else:
        path = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "sprites", "characters", name)
    img.save(path)
    if out_dir:
        print("已写出", name, "到", out_dir)
    return path


def stack(head, body, tint=TINT, dx=0, dy=SHIFT):
    """照游戏里的摆法叠起来：身子在后面（染成 tint）、往右下错开 (dx, dy)，头在前面（白的）。
    不给 dx、dy 就是上下对齐（身子的画布比头的低 SHIFT 行）；游戏里镜头是斜的，身子在屏幕上会往右下错开
    （见 INGAME），预览时照那个样子叠一遍。返回 (236+dx)×(248+dy) 的图"""
    w, h = CANVAS[0] + max(dx, 0), CANVAS[1] + max(dy, 0)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer = Image.new("RGBA", body.size, tint + (0,))
    layer.putalpha(body.split()[3])
    im.alpha_composite(layer, (dx, dy))
    im.alpha_composite(head, (0, 0))
    return im


# 游戏里量到的（debug_rects，主角在第 12 关和第 1 关的起点上）：身子相对头的错开（换算成纹理像素）、
# 竖向压扁的程度（镜头是俯视的，竖着的精灵被压扁）。横着量的东西（宽度、左右的口子）不受压扁影响，
# 竖着量的东西（横线的粗细、上下的间距）在第 12 关只剩一半
INGAME = {
    "第1关": (21, 87, 0.68),      # (身子往右错开多少, 往下错开多少, 竖向压成原来的多少)
    "第12关": (41, 89, 0.54),
}
ZOOM = {"第1关": 0.33, "第12关": 0.29, "选人卡片": 0.52}

FRAME = (20, 36, 236, 344)      # 预览时裁出来的范围（头的画布坐标，右下留出身子错开的地方）
DARK = (16, 34, 30)              # 小图背景，接近游戏里棋盘的颜色


def _tile(im, k, bg=BG, pad=8):
    """放大 k 倍，放在底色上"""
    im = im.resize((im.width * k, im.height * k), Image.LANCZOS)
    t = Image.new("RGB", (im.width + pad * 2, im.height + pad * 2), bg)
    t.paste(im, (pad, pad), im if im.mode == "RGBA" else None)
    return t


def _mini(im, zoom, k=8, sy=1.0, bg=DARK):
    """按游戏里的大小缩小再放大 k 倍（最近邻）：先压在底色上再缩，颜色和游戏里一样（头白、身子是染的颜色）。
    sy 是竖向再压扁成多少"""
    flat = Image.new("RGB", im.size, bg)
    flat.paste(im, (0, 0), im)
    small = flat.resize((max(1, round(flat.width * zoom)), max(1, round(flat.height * zoom * sy))), Image.LANCZOS)
    return small.resize((small.width * k, small.height * k), Image.NEAREST)


def _font(size=16):
    for f in ("/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/PingFang.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _head_img(head):
    return load(head) if isinstance(head, str) else head


def _body_img(body):
    return load(body) if isinstance(body, str) else body


def sheet(out, title, items, k_big=3, k_small=7):
    """出一张预览图，一行是一个图（新图、原版各一行），三列：
      [上下对齐叠起来 ×k_big] [照第 1 关的样子：身子错开、竖向压扁，再缩到游戏里的大小放大 k_small 倍]
      [照第 12 关的样子，同样缩小]。
    items 是 (行标题, 头的路径或者图, 身子的路径或者图) 的列表"""
    font = _font()
    rows = []
    for label, head, body in items:
        head, body = _head_img(head), _body_img(body)
        tiles = [_tile(stack(head, body).crop(FRAME), k_big)]
        for name in ("第1关", "第12关"):
            dx, dy, sy = INGAME[name]
            im = stack(head, body, dx=dx, dy=dy).crop((FRAME[0], FRAME[1], FRAME[2] + dx, FRAME[3] + dy))
            tiles.append(_tile(_mini(im, ZOOM[name], k_small, sy), 1, bg=(28, 34, 52), pad=0))
        rows.append((label, tiles))
    cw = max(t.width for _, tiles in rows for t in tiles) + 16
    ch = max(max(t.height for t in tiles) for _, tiles in rows) + 40
    cols = 3
    out_im = Image.new("RGB", (cw * cols + 8 * (cols + 1), ch * len(rows) + 8 * (len(rows) + 1) + 36), (28, 34, 52))
    draw = ImageDraw.Draw(out_im)
    draw.text((8, 6), title, fill=(240, 240, 248), font=font)
    heads = ["上下对齐 ×%d" % k_big, "第 1 关的样子（0.33 倍，压到 0.68）", "第 12 关的样子（0.29 倍，压到 0.54）"]
    for r, (label, tiles) in enumerate(rows):
        for c, t in enumerate(tiles):
            x = 8 + c * (cw + 8)
            y = 36 + 8 + r * (ch + 8)
            draw.text((x, y), "%s　%s" % (label, heads[c]), fill=(200, 205, 220) if r else (240, 240, 248), font=font)
            out_im.paste(t, (x, y + 24))
    out_im.save(out)
    print("预览图:", out, out_im.size)


def preview(out, title, head_path, body_path, rel_head, rel_body):
    """一个元素的预览：上一行是新图（头叠在身子上），下一行是原版照同样的摆法叠起来。
    rel_head、rel_body 是对应的原版图在工程里的相对路径"""
    items = [("新图", head_path, body_path)]
    # 原版的图不在手边（没设 SW_ORIG）时就不放"原版"那一行
    if orig(rel_head) is not None and orig(rel_body) is not None:
        items.append(("原版", orig(rel_head), orig(rel_body)))
    sheet(out, title, items)


def lineup(out, title, pairs, zoom=0.52, k=5, name="选人卡片"):
    """一排头并排（只有头，没有身子），按 zoom 缩小再放大 k 倍：看光凭轮廓能不能一眼分清。
    pairs 是 (小字, 头的路径或者图) 的列表"""
    font = _font()
    tiles = []
    for label, head in pairs:
        im = _head_img(head).crop((30, 40, 206, 210))
        small = im.resize((round(im.width * zoom), round(im.height * zoom)), Image.LANCZOS)
        small = small.resize((small.width * k, small.height * k), Image.NEAREST)
        t = Image.new("RGB", small.size, (20, 22, 26))
        t.paste(small, (0, 0), small)
        tiles.append((label, t))
    tw = max(t.width for _, t in tiles) + 16
    th = max(t.height for _, t in tiles) + 50
    out_im = Image.new("RGB", (tw * len(tiles) + 8, th + 40), (28, 34, 52))
    draw = ImageDraw.Draw(out_im)
    draw.text((8, 6), "%s　（%.2f 倍，再放大 %d 倍）" % (title, zoom, k), fill=(240, 240, 248), font=font)
    for i, (label, t) in enumerate(tiles):
        x = 8 + i * tw
        draw.text((x + 4, 30), label, fill=(240, 240, 248), font=font)
        out_im.paste(t, (x + 8, 54))
    out_im.save(out)
    print("并排图:", out, out_im.size)

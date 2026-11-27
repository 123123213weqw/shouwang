#!/usr/bin/env python3
"""一支蜡烛和插着它的灯盏：难度里"夜巡"这条规矩的计时，挂在游戏画面左上角。蜡从头上往下烧，烧完最远的一盏河灯就灭；
每跳一下蜡长回一点（游戏里 scripts/uis/rule_hud.gd 只露出下半截，烧掉的部分裁掉，火苗另画）。
两张新图，原版里没有，各拿一张形状差不多的原版图当参照：

  candle.png         蜡烛（会烧的那一支）
      参照 assets/sprites/peer.png：又高又窄的图形。256×256 的画布，图形落在它的范围里（x 87..168，y 40..221，81×181）。
      一支矮胖的蜡烛：比着粗头马克笔的线宽画的（52 个纹理像素粗），下粗上细，往右歪一点点，左边挂着一道淌下来的蜡，
      顶面不平（烧化了的蜡油）。游戏里 64 屏幕像素高（zoom 约 0.35），粗 18 个屏幕像素。
  candle_holder.png  灯盏（蜡烛插在里头；蜡烧完了它也还在）
      参照 assets/sprites/ui/lock.png。311×316 的画布，图形落在它的范围里（x 108..203，y 107..208，95×101）。
      一只口宽底圆的小盏，口沿比盏身宽出一圈，沿口不平直。图形 95×70，宽撑满、高是参照的七成：盏本来就矮。
      （先画的是一只浅碟正中鼓一个小杯：缩到游戏里的大小像一顶草帽，认不出是盏，改成了这样。）

两张都是纯白、实心，不描边、不画明暗，颜色在游戏里乘上去。

用法: python3 -I candle.py
  把 candle.png 和 candle_holder.png 写到工程的 assets/sprites/ui/rules/ 里并自检。
  想看它们在游戏里的大小：python3 -I review.py mini 预览.png 0.35 assets/sprites/ui/rules/candle.png
只依赖 Pillow 和 numpy。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))            # 工程的根目录

CANDLE = dict(
    rel="assets/sprites/ui/rules/candle.png", ref="assets/sprites/peer.png",
    canvas=(256, 256), w=81, h=181, zoom=64.0 / 181.0,       # 游戏里蜡烛 64 屏幕像素高
    hand=dict(seed=45, wobble=0.012, thick=0.014, tilt=0.8),
)
# 蜡烛：从左下角出发，沿左边往上（中段有一道淌下来的蜡，鼓出去一块），过顶面（两头保持角，中间凹一点），
# 再沿右边下来。下粗上细，整支往右歪一点
CANDLE_OUTLINE = [
    (14.0, 178.0, 1), (13.0, 150.0), (12.4, 128.0), (7.5, 118.0), (7.8, 108.0), (13.4, 99.0), (14.6, 70.0), (15.4, 36.0), (16.0, 4.0, 1),
    (38.0, 10.0), (62.0, 2.0, 1), (64.0, 40.0), (65.4, 80.0), (66.6, 122.0), (67.6, 150.0), (68.0, 178.0, 1),
]

HOLDER = dict(
    rel="assets/sprites/ui/rules/candle_holder.png", ref="assets/sprites/ui/lock.png",
    canvas=(311, 316), w=95, h=101, zoom=44.0 / 95.0,        # 游戏里烛台 48 屏幕像素宽
    hand=dict(seed=77, wobble=0.016, thick=0.02, tilt=1.0),
)
# 灯盏：口沿左端（尖角）→ 盏身左鼓 → 圆底 → 盏身右鼓 → 口沿右端（尖角）→ 沿口从右回到左（不平直）
HOLDER_OUTLINE = [
    (1.0, 32.0, 1), (8.0, 40.0), (16.0, 62.0), (27.0, 82.0), (47.0, 92.0), (67.0, 82.0), (78.0, 62.0), (86.0, 40.0), (94.0, 30.0, 1),
    (76.0, 24.0), (52.0, 27.0), (30.0, 23.0), (12.0, 26.0),
]


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    doodle = _load("doodle")
    ok = True
    for part, outline in ((CANDLE, CANDLE_OUTLINE), (HOLDER, HOLDER_OUTLINE)):
        d = doodle.Mask(part["w"], part["h"])
        d.shape(outline)
        d.soften(0.8)
        img = doodle.place(d.alpha(), doodle.orig_size(part["ref"]), doodle.orig_box(part["ref"]), hand=part["hand"])
        out = os.path.join(ROOT, part["rel"])
        img.save(out)
        print("已写出", out)
        ok = doodle.check(out, part["rel"], zoom=part["zoom"], kind="2d", ref=part["ref"], name=part["rel"]) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

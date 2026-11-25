#!/usr/bin/env python3
"""三个开场动画各自的声音：assets/audio/opening/openA.wav 到 openD.wav（48 千赫、16 位、立体声，五秒多一段）。

声音是算出来的（tools/audio/synth.py 是工具，instruments.py 是每样东西怎么响），这里只写"什么东西在哪一刻响、在哪边、多响"。
每一刻都对着 scripts/uis/opening.gd 里动画的时间点（那边改了动作的时刻，这边要跟着改）：
   A 一灯破夜    0.20 灯花忽明忽暗 → 1.04 定下来 → 0.75 起一串灯从水底涌上来 → 2.05 汇向标志 → 2.60 炸开 → 2.95 揭出标题
   B 水墨惊雷    0.15 墨滴落下 → 0.25 化开 → 0.95 标志浮现 → 1.95 大印落下、2.12 盖实 → 2.55 墨铺满 → 3.28 露出标题页
   D 守夜人点灯  0.25 起五块石台升起 → 0.95 起一格一格跳（1.25 起每落一下点一盏灯）→ 2.55 举灯 → 2.70 揭出 → 3.05 迸火星
乐器是古筝和琵琶（tools/audio/instruments_cn.py），音都从标题音乐的调里来：升 C 宫五声（升 C、E、升 F、升 G、B）。
三段各用一样的招牌技法，一听就分得出是哪一段：
   A 刮奏（手指扫过一串弦，音往上走）—— 一串河灯从水底涌起来，正好是刮奏在往上走
   B 扫弦（四根弦依次扫过去）加重按音（把弦按下去、音往上滑）—— 大印盖下去的那一下用扫弦最沉
   D 五声一步一个音往上走，最后摇指 —— 守夜人一格一格跳过去，每落一步是一个音
   B 里"印章砸下去"是堂鼓：皮膜的音先高后落，不是电子闷响
三段是一套的：
   底都是夜里的河面；水、木头、石头、纸、火这几样只是拟音（不是乐器）；用的是同一个混响空间；
   最后都落在升 C 上，紧接着标题音乐从它的第一个和弦进来。
用法（在工程根目录）: python3 tools/audio/opening.py            算三段，写文件，报每段的响度
                      python3 tools/audio/opening.py A --check  只算 A，另外在 builds/audio/ 里画一张频谱和波形图
"""
import importlib.util
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "opening")
BUILD_DIR = os.path.join(ROOT, "builds", "audio")


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


synth, inst, cn = _load("synth"), _load("instruments"), _load("instruments_cn")
N = inst.NOTE

# 每段的时长（秒）：要装得下动画和混响的尾巴
LENGTH = {"A": 5.8, "B": 5.8, "D": 5.6}
# 混响：夜里水面上，开阔、偏暗，一秒二衰完。三段共用同一个空间
IR = synth.make_ir(rt60=1.2, predelay=0.02, g=np.random.default_rng(2026))


def bed(mix, stereo, gain, fin, fout, at=0.0):
    """铺底：从 at 秒起，fin 秒淡入，最后 fout 秒淡出（立体声，不进混响）"""
    n = mix.n - synth.samples(at)
    x = stereo[:, :n]
    env = np.ones(x.shape[1])
    a, b = synth.samples(fin), synth.samples(fout)
    env[:a] = np.linspace(0.0, 1.0, a)
    env[-b:] = np.linspace(1.0, 0.0, b)
    mix.dry[:, synth.samples(at):] += x * env * gain


def sparkle(mix, g, t0, t1, count, gain=0.07, lo=2200.0, hi=6200.0, spread=0.8):
    """一把火星：count 颗又高又轻的小水珠，散在 t0 到 t1 秒之间"""
    for _ in range(count):
        at = g.uniform(t0, t1)
        f = g.uniform(lo, hi)
        mix.add(inst.plink(f * 0.55, f, 0.14, g), at, gain * g.uniform(0.5, 1.0), g.uniform(-spread, spread), 0.55)


# ================================================================ A 一灯破夜

def cue_a(g):
    """一灯破夜：古筝。一声带吟揉的长音当作"第一盏灯"，一串灯涌起来用刮奏往上扫，炸开那一下古筝和琵琶一起"""
    m = synth.Mix(LENGTH["A"], IR, g)
    bed(m, inst.night_water(LENGTH["A"], g, flow=0.12), 0.06, 0.8, 1.4)
    # 一点灯花，忽明忽暗三次（0.20 起每 0.28 秒一下）
    for i in range(3):
        at = 0.20 + i * 0.28
        m.add(inst.rustle(0.07, g, 2600.0, 8500.0, 0.006), at, 0.05, 0.0, 0.1)
        m.add(inst.flame(g, 0.16), at + 0.01, 0.035 + 0.01 * i, 0.0, 0.2)
    # 1.04 灯定住了：古筝一声，吟揉慢慢颤起来
    m.add(inst.flame(g, 0.42), 1.04, 0.14, 0.0, 0.15)
    m.add(cn.guzheng(61, 3.0, g, vibrato=16.0), 1.04, 0.55, 0.0, 0.45)
    # 三圈涟漪
    for i, (a, b) in enumerate(((520.0, 790.0), (470.0, 870.0), (560.0, 990.0))):
        m.add(inst.plink(a, b, 0.32, g), 1.05 + i * 0.25, 0.09, -0.08 + 0.08 * i, 0.35)
    # 这盏灯从水底浮上来：气泡，带一点水花
    m.add(inst.splash(0.16, 0.4, g), 1.30, 0.07, 0.0, 0.15)
    for i in range(5):
        m.add(inst.bubble(230.0 * (1.0 + 0.22 * i), 0.08, g), 1.30 + i * 0.085, 0.04 - 0.004 * i, 0.05, 0.25)
    # 一串河灯从水底涌起来：古筝刮奏，从低往上一路扫过去（0.80 起，1.25 秒扫完）
    m.add(cn.guzheng_gliss(cn.penta(-2, 13), 1.25, g, each=0.85), 0.80, 0.36, 0.0, 0.45)
    # 每一盏出水的那一下（拟音，压在刮奏底下）
    for i in range(12):
        fx = 0.14 + 0.72 * (float((i * 5) % 12) / 11.0)
        at, k = synth.humanize(g, 0.75 + i * 0.11, 0.02, 0.18)
        m.add(inst.splash(0.12, 0.3, g), at + 0.01, 0.04 * k, (fx - 0.5) * 1.3, 0.12)
    # 汇向标志：一股上扬的气，三声琵琶从三边凑过来（每一句都往上推半音）
    m.add(inst.riser(0.55, 320.0, 6800.0, g), 2.03, 0.14, 0.0, 0.2)
    for at, note, p, bend in ((2.10, 66, -0.3, 2.0), (2.22, 68, 0.0, 3.0), (2.34, 71, 0.3, 2.0)):
        m.add(cn.pipa(note, 1.1, g, bend=bend), at, 0.30, p, 0.45)
    # 2.56 闪一下、2.60 炸开成光：古筝和琵琶一起
    m.add(inst.thump(122.0, 46.0, 0.5, g), 2.56, 0.50, 0.0, 0.25)
    m.add(inst.swish(0.36, 3200.0, 900.0, g), 2.56, 0.06, 0.0, 0.2)
    m.add(cn.guzheng(73, 3.0, g, vibrato=10.0), 2.60, 0.62, 0.0, 0.45)
    m.add(cn.pipa(80, 1.6, g), 2.60, 0.22, 0.15, 0.55)
    sparkle(m, g, 2.60, 3.35, 12, 0.032, 2400.0, 6600.0)
    # 3.30 收：古筝一声轻的，把余音交给标题音乐
    m.add(cn.guzheng(73, 2.6, g, vibrato=20.0), 3.30, 0.20, 0.0, 0.6)
    return m


# ================================================================ B 水墨惊雷

def cue_b(g):
    """水墨惊雷：琵琶。墨落在纸上是一声扫弦，大印盖下去是最重的一声扫弦；古筝按音把标志从墨里"按"出来"""
    m = synth.Mix(LENGTH["B"], IR, g)
    air = inst.room_air(LENGTH["B"], g) * 0.7 + inst.night_water(LENGTH["B"], g, flow=0.0) * 0.3
    bed(m, air / np.abs(air).max(), 0.04, 0.5, 1.2)
    # 0.15 一滴墨落下来（一声很短的琵琶高音），0.25 落在纸上
    m.add(cn.pipa(80, 0.4, g), 0.15, 0.16, 0.0, 0.3)
    m.add(inst.bubble(760.0, 0.05, g), 0.15, 0.05, 0.0, 0.3)
    m.add(cn.drum(188.0, 0.5, g, muffled=0.75), 0.25, 0.13, 0.0, 0.2)
    m.add(inst.brush(0.95, g), 0.25, 0.08, -0.1, 0.1)
    # 墨化开：琵琶扫弦（四根弦依次扫过去）
    m.add(cn.pipa_strum([49, 56, 61, 66], 2.2, g, spread=0.020), 0.25, 0.42, 0.0, 0.45)
    # 溅开的几点墨
    for _ in range(5):
        at, k = synth.humanize(g, g.uniform(0.17, 0.55), 0.0, 0.2)
        m.add(inst.bubble(g.uniform(520.0, 1150.0), 0.05, g), at, 0.035 * k, g.uniform(-0.55, 0.55), 0.3)
    # 0.95 标志从墨里浮出来：古筝按音，音往上滑一个全音
    m.add(inst.swish(0.65, 600.0, 1700.0, g), 0.88, 0.04, 0.0, 0.3)
    m.add(cn.guzheng(66, 3.0, g, bend=2.0, vibrato=0.0), 0.95, 0.50, 0.0, 0.5)
    m.add(cn.guzheng(49, 3.0, g, vibrato=6.0), 0.95, 0.24, 0.0, 0.5)
    # 1.95 大印从空中落下，2.12 盖实（扫弦最重的一下）
    m.add(inst.riser(0.17, 3300.0, 900.0, g, curve=1.6), 1.95, 0.07, 0.3, 0.2)
    # 印章砸在纸上：堂鼓一声（皮膜的音先高后落，是"砸"不是"咚一下电子闷响"），再叠一点纸的声音
    m.add(cn.drum(104.0, 1.0, g), 2.12, 0.82, 0.3, 0.32)
    m.add(inst.rustle(0.06, g, 1500.0, 9000.0, 0.004), 2.12, 0.12, 0.3, 0.15)
    m.add(cn.pipa_strum([49, 56, 61, 68], 1.9, g, spread=0.010), 2.12, 0.62, 0.3, 0.4)
    m.add(cn.guzheng(49, 3.0, g, vibrato=8.0), 2.12, 0.34, 0.2, 0.5)
    # 震了一下，溅起几点墨
    for _ in range(6):
        at, k = synth.humanize(g, g.uniform(2.16, 2.56), 0.0, 0.25)
        m.add(inst.bubble(g.uniform(600.0, 1400.0), 0.05, g), at, 0.025 * k, 0.3 + g.uniform(-0.3, 0.3), 0.4)
    # 2.55 墨铺满全屏：古筝刮奏往下扫（墨往下淌），远处一声闷雷
    m.add(cn.guzheng_gliss(cn.penta(-1, 12), 0.55, g, each=0.7, rising=False), 2.55, 0.40, 0.0, 0.45)
    m.add(inst.rumble(1.0, g, 150.0), 2.62, 0.26, 0.0, 0.1)
    # 3.15 墨散开，3.28 露出标题页：古筝一声
    m.add(inst.swish(0.75, 1900.0, 520.0, g), 3.12, 0.05, 0.0, 0.3)
    m.add(cn.guzheng(73, 2.6, g, vibrato=18.0), 3.28, 0.50, 0.0, 0.55)
    return m


# ================================================================ D 守夜人点灯

def cue_d(g):
    """守夜人点灯：古筝五声一步一个音往上走（和五块石台一一对应），最后摇指举灯"""
    m = synth.Mix(LENGTH["D"], IR, g)
    bed(m, inst.night_water(LENGTH["D"], g, flow=0.1), 0.05, 0.5, 1.2)
    xs = (0.30, 0.40, 0.50, 0.60, 0.70)
    # 夜里的水面：几圈很淡的涟漪
    for i in range(5):
        x = 0.12 + 0.19 * i
        m.add(inst.splash(0.10, 0.6, g), 0.20 + i * 0.5, 0.045, (x - 0.5) * 1.2, 0.3)
    # 五块石台从水里升起来（0.25 起每 0.09 秒一块）
    for k, x in enumerate(xs):
        at = 0.25 + k * 0.09
        p = (x - 0.5) * 1.3
        m.add(inst.gurgle(0.5, g, 125.0 + 12.0 * k), at, 0.13, p, 0.2)
        m.add(inst.splash(0.26, 0.7, g), at + 0.30, 0.09, p, 0.15)
    # 0.70 守夜人现身：蓑衣动了一下
    m.add(inst.swish(0.36, 500.0, 1500.0, g), 0.70, 0.045, -0.45, 0.2)
    # 一格一格跳过去：每落一步，石台上响一下、点亮一盏灯，古筝在五声上高一阶
    #   升 C、E、升 F、升 G、B：五块石台正好五个音
    notes = (61, 64, 66, 68, 71)                      # 五声：宫、角、徵、羽…… 一步一步往上
    gains = (0.42, 0.44, 0.46, 0.48, 0.56)
    for k, x in enumerate(xs):
        p = (x - 0.5) * 1.3
        m.add(inst.woodblock(1400.0, 0.14, g), 0.95 + k * 0.3, 0.03, p - 0.08, 0.2)
        m.add(inst.stone_step(g), 1.25 + k * 0.3, 0.19, p, 0.25)
        m.add(inst.flame(g, 0.42), 1.25 + k * 0.3, 0.11, p, 0.15)
        m.add(cn.guzheng(notes[k], 2.6 + 0.2 * k, g, vibrato=12.0 + 2.0 * k), 1.25 + k * 0.3, gains[k], p * 0.7, 0.5)
    # 2.55 举起灯：古筝摇指（同一个音来回摇，越摇越开），火苗窜高
    m.add(cn.guzheng_roll(73, 0.8, g, rate=9.0), 2.52, 0.42, 0.26, 0.45)
    m.add(inst.riser(0.32, 500.0, 5200.0, g, curve=1.8), 2.55, 0.10, 0.26, 0.25)
    m.add(inst.flame(g, 0.5), 2.55, 0.13, 0.26, 0.15)
    # 2.72 光扫开：琵琶扫弦 + 古筝
    m.add(cn.pipa_strum([61, 66, 68, 73], 1.7, g, spread=0.014), 2.72, 0.32, 0.0, 0.5)
    m.add(cn.guzheng(73, 2.6, g, vibrato=14.0), 2.72, 0.34, 0.0, 0.5)
    # 2.80 石台、灯和人汇向标志，3.05 迸出火星
    m.add(inst.swish(0.5, 1200.0, 3300.0, g), 2.80, 0.05, 0.0, 0.2)
    m.add(inst.thump(104.0, 48.0, 0.5, g), 3.05, 0.28, 0.0, 0.3)
    sparkle(m, g, 3.05, 3.75, 9, 0.028, 2500.0, 6500.0)
    return m


CUES = {"A": ("一灯破夜", cue_a), "B": ("水墨惊雷", cue_b), "D": ("守夜人点灯", cue_d)}


## 最响的那一小段有多响（分贝）。开场的重头戏定在 -13 分贝上下：和标题音乐（有效值 -20 分贝）比略响一点，
## 音乐回来的时候不觉得开场突然哑了，也不至于压过音乐
ACCENT_DB = -13.0
## 最响的一个采样点不能超过多少（分贝）。给后面留着头寸
PEAK_DB = -2.5


def render(which, check=False):
    name, build = CUES[which]
    g = np.random.default_rng(1100 + ord(which))
    out = build(g).render()
    out = synth.finish(out, peak_db=0.0, drive=1.15)
    # 按"最响的 0.25 秒"定整体轻重，再看单个采样点有没有超
    win = synth.SR // 4
    loudest = max(float(np.sqrt((out[:, i:i + win] ** 2).mean())) for i in range(0, out.shape[1] - win, win // 2))
    out = out * (10.0 ** (ACCENT_DB / 20.0) / (loudest + 1e-12))
    peak = 20 * np.log10(float(np.abs(out).max()) + 1e-12)
    if peak > PEAK_DB:
        out = out * (10.0 ** (PEAK_DB / 20.0) / float(np.abs(out).max()))
    return name, out


def main(argv):
    which = [a for a in argv if a in CUES] or list(CUES)
    check = "--check" in argv
    os.makedirs(OUT_DIR, exist_ok=True)
    if check:
        os.makedirs(BUILD_DIR, exist_ok=True)
        look = _load("look")
    for w in which:
        name, out = render(w)
        path = os.path.join(OUT_DIR, "open%s.wav" % w)
        synth.write_wav(path, out)
        print("== %s %s → %s（%.1f 秒）" % (w, name, os.path.relpath(path, ROOT), out.shape[1] / synth.SR))
        print("   " + synth.report(out).replace("\n", "\n   "))
        if check:
            look.draw(out, os.path.join(BUILD_DIR, "open%s.png" % w), "%s %s" % (w, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

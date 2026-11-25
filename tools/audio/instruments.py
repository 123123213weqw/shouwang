"""一样一样东西各自怎么响：水珠、水花、木块、石台上的脚步、水车的木头、宣纸上的笔、灯火、磬、夜里的河面。

每一样都是照着它发声的道理凑出来的，不是拿现成的波形硬凑：
   水珠   气泡在水里一颤，频率往上滑一下，所以是"叮"的一声而不是"啪"
   水花   低的一团"扑"加高的一片"沙"，后面跟着几颗溅起来的小水珠
   磬     泛音不是整倍数，越高的泛音灭得越快；每个泛音用两根差一点点频率的正弦叠着，有细细的拍频
   木头   几个不成整倍数的共鸣，很短；水车的吱呀是木头一下抓住、一下滑开
   灯火   火苗窜起来是一小段往上跑的噪声，底下托着一口气
音高都对着标题音乐：升 C 小调一带。NOTE 里是开场里用到的几个音。
"""
import importlib.util
import os

import numpy as np

# 按文件路径加载同目录下的 synth.py（隔离模式下运行脚本的时侯，脚本所在的目录不在模块搜索路径里）
_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("synth", os.path.join(_here, "synth.py"))
synth = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(synth)
SR, samples, noise = synth.SR, synth.samples, synth.noise
lowpass, highpass, bandpass, swept_noise = synth.lowpass, synth.highpass, synth.bandpass, synth.swept_noise
env_decay, env_ar, slow_lfo = synth.env_decay, synth.env_ar, synth.slow_lfo
fade, normalize, resonant = synth.fade, synth.normalize, synth.resonant

TWO_PI = 2.0 * np.pi
NOTE = {
    "C#3": 138.59, "F#3": 185.00, "G#3": 207.65,
    "C#4": 277.18, "F#4": 369.99, "G#4": 415.30, "B4": 493.88,
    "C#5": 554.37, "F#5": 739.99, "G#5": 830.61, "C#6": 1108.73,
}


def _t(n):
    return np.arange(n) / SR


# ================================================================ 磬

def bell(f0, dur=3.4, g=None, bright=1.0):
    """一声磬。f0 是频率（赫兹），bright 小于 1 更暗更软"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = _t(n)
    ratios = [1.0, 2.0, 2.41, 3.0, 3.98, 5.21, 6.73]
    amps = [1.0, 0.40, 0.24, 0.18, 0.10, 0.055, 0.03]
    taus = [1.0, 0.60, 0.44, 0.35, 0.25, 0.19, 0.14]
    base = 1.0 * (NOTE["C#4"] / f0) ** 0.45          # 低的磬响得久一些；升 C 这一声一秒左右衰完
    s = np.zeros(n)
    # 敲下去的头几十毫秒整个磬绷得紧一点，略高半音分之几，然后松回来
    bend = 0.006 * 0.012 * (1.0 - np.exp(-t / 0.012))
    for k in range(len(ratios)):
        amp = amps[k] * bright ** k
        if amp < 0.004:
            continue
        f = f0 * ratios[k] * (1.0 + g.normal(0.0, 0.0005))
        for det in (-0.0013, 0.0013):
            s += amp * np.sin(TWO_PI * f * (1.0 + det) * (t + bend) + g.uniform(0.0, TWO_PI)) * np.exp(-t / (base * taus[k]))
    s *= 1.0 - np.exp(-t / 0.004)
    # 磬锤碰上去那一小点
    s += bandpass(noise(n, g), 1400.0, 4200.0, 1) * env_decay(n, 0.007, 0.0008) * 0.22 * bright
    return normalize(fade(s, 0.0, 0.08))


# ================================================================ 水

def plink(f_lo=430.0, f_hi=880.0, dur=0.32, g=None):
    """一颗水珠落进水里"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = _t(n)
    f = f_hi - (f_hi - f_lo) * np.exp(-t / 0.014)
    ph = TWO_PI * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.055) + 0.28 * np.sin(2.0 * ph) * np.exp(-t / 0.028)
    s += bandpass(noise(n, g), 2600.0, 9500.0, 1) * env_decay(n, 0.006, 0.0005) * 0.10
    s *= 1.0 - np.exp(-t / 0.0012)
    return normalize(fade(s, 0.0, 0.03))


def bubble(f0=400.0, dur=0.07, g=None):
    """一个小气泡冒上来：往上滑的一小声"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = _t(n)
    f = f0 * (1.0 + 0.55 * np.clip(t / 0.022, 0.0, 1.0))
    s = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.018) * (1.0 - np.exp(-t / 0.001))
    return fade(normalize(s), 0.0, 0.01)


def splash(size=0.5, dur=None, g=None):
    """一小片水花。size 0 到 1：小到还没离开水面就没了，大一点是东西从水里出来"""
    g = g or np.random.default_rng(0)
    dur = dur or (0.55 + 0.55 * size)
    n = samples(dur)
    t = _t(n)
    body = lowpass(noise(n, g), 330.0 + 320.0 * size, 2) * env_decay(n, 0.045 + 0.09 * size, 0.002)
    spray = bandpass(noise(n, g), 1300.0, 9500.0, 1) * env_decay(n, 0.06 + 0.13 * size, 0.004)
    s = body * 0.95 + spray * 0.55
    # 溅起来又落回去的几颗水珠
    for _ in range(2 + int(6.0 * size)):
        at = g.uniform(0.035, 0.22 + 0.4 * size)
        d = plink(g.uniform(520.0, 820.0), g.uniform(1000.0, 1500.0), 0.22, g) * g.uniform(0.08, 0.26) * (1.0 - at / dur)
        i = samples(at)
        s[i:i + len(d)] += d[: n - i]
    return normalize(fade(s, 0.0, 0.05))


def gurgle(dur=0.35, g=None, lo=130.0):
    """东西从水里升上来：一串越冒越高、越冒越小的气泡，最后一点小水花"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    s = np.zeros(n)
    k = 4 + int(g.integers(0, 3))
    for i in range(k):
        at = (i / k) ** 1.3 * (dur - 0.12)
        f0 = lo * (1.0 + 1.4 * i / k) * g.uniform(0.9, 1.1)
        b = bubble(f0, 0.08, g) * (0.5 + 0.5 * i / k)
        j = samples(at)
        s[j:j + len(b)] += b[: n - j]
    sp = splash(0.18, 0.4, g)
    j = max(0, samples(dur - 0.42))
    k = min(len(sp), n - j)
    s[j:j + k] += sp[:k] * 0.55
    return normalize(fade(s, 0.002, 0.05))


# ================================================================ 木头、石头、纸、火

def thump(f_hi=110.0, f_lo=44.0, dur=0.45, g=None):
    """沉的一下：频率掉下去，像很重的东西落在垫了东西的台面上"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = _t(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.045)
    s = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.11) * (1.0 - np.exp(-t / 0.0015))
    s += bandpass(noise(n, g), 900.0, 3800.0, 1) * env_decay(n, 0.004, 0.0005) * 0.35
    return normalize(fade(s, 0.0, 0.06))


def woodblock(f0=820.0, dur=0.28, g=None):
    """梆子、木鱼那一下"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = _t(n)
    s = np.zeros(n)
    for ratio, amp, tau in ((1.0, 1.0, 0.055), (2.92, 0.5, 0.03), (5.43, 0.25, 0.016), (8.2, 0.1, 0.009)):
        s += amp * np.sin(TWO_PI * f0 * ratio * g.uniform(0.99, 1.01) * t + g.uniform(0, TWO_PI)) * np.exp(-t / tau)
    s += bandpass(noise(n, g), 1600.0, 6000.0, 1) * env_decay(n, 0.003, 0.0004) * 0.5
    s *= 1.0 - np.exp(-t / 0.0006)
    return normalize(fade(s, 0.0, 0.03))


def stone_step(g=None, wet=True):
    """脚落在石台上。wet：石台是湿的，带一点水"""
    g = g or np.random.default_rng(0)
    dur = 0.4
    n = samples(dur)
    t = _t(n)
    s = np.zeros(n)
    for f, amp, tau in ((168.0, 1.0, 0.07), (415.0, 0.55, 0.04), (985.0, 0.3, 0.02), (2100.0, 0.12, 0.01)):
        s += amp * np.sin(TWO_PI * f * g.uniform(0.96, 1.04) * t + g.uniform(0, TWO_PI)) * np.exp(-t / tau)
    s += bandpass(noise(n, g), 700.0, 5200.0, 1) * env_decay(n, 0.006, 0.0005) * 0.7
    s *= 1.0 - np.exp(-t / 0.0008)
    if wet:
        sp = splash(0.12, 0.3, g)
        s[: len(sp)] += sp * 0.32
    return normalize(fade(s, 0.0, 0.04))


def creak(dur=0.9, g=None, lo=260.0, hi=640.0):
    """木头吱呀：一下抓住、一下滑开，所以中心频率慢慢地飘，时强时弱还有细颗粒"""
    g = g or np.random.default_rng(0)
    k = max(3, int(dur * 4.0) + 2)
    pts = np.clip(lo + (hi - lo) * g.uniform(0.0, 1.0, k), lo, hi)
    ts = np.linspace(0.0, dur, k)
    f_of_t = lambda tt: float(np.interp(tt, ts, pts))
    s = swept_noise(dur, f_of_t, 0.10, g, hop=0.005, n_fft=4096)
    n = len(s)
    t = _t(n)
    grain = 0.62 + 0.38 * np.sin(TWO_PI * np.cumsum(22.0 + 9.0 * slow_lfo(n, 3.0, g)) / SR)
    s = s * grain * (0.45 + 0.55 * slow_lfo(n, 2.2, g))
    s = s + lowpass(s, 200.0, 2) * 0.8          # 底下一点木头的闷响
    s *= env_ar(n, dur * 0.25, dur * 0.35, 1.5)
    return normalize(fade(s, 0.005, 0.03))


def rustle(dur=0.6, g=None, lo=1700.0, hi=9500.0, grains=0.009):
    """笔在纸上、纸翻动：高频的沙沙，一粒一粒的轻重不一样"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    s = bandpass(noise(n, g), lo, hi, 1)
    size = samples(grains)
    amps = g.uniform(0.25, 1.0, n // size + 2)
    a = np.interp(np.arange(n), np.arange(len(amps)) * size, amps)
    s *= 0.4 + 0.6 * a
    return normalize(fade(s, 0.004, 0.02))


def brush(dur=0.7, g=None):
    """一笔下去：沙沙声随着笔的速度先重后轻"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    s = bandpass(noise(n, g), 1300.0, 7000.0, 2)
    t = _t(n) / dur
    s *= np.exp(-t * 3.2) * (1.0 - np.exp(-t / 0.03)) * (0.55 + 0.45 * slow_lfo(n, 25.0, g))
    s = lowpass(s, 4500.0, 1) + rustle(dur, g) * 0.25
    return normalize(fade(s, 0.0, 0.05))


def flame(g=None, dur=0.42):
    """火苗窜起来那一下：一小段往上跑的气，底下托着一口气，后面有两三声很小的火星"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    rise = min(0.17, dur * 0.6)            # 火苗窜上去用多久（短的火苗窜得也短）
    up = swept_noise(rise, lambda tt: 380.0 + 2800.0 * min(tt / (rise * 0.5), 1.35), 0.55, g)
    t = _t(len(up))
    up *= (1.0 - np.exp(-t / 0.006)) * np.exp(-t / 0.05)
    whump = lowpass(noise(n, g), 210.0, 2) * env_decay(n, 0.085, 0.004)
    s = whump * 0.8
    s[: len(up)] += up * 0.5
    for _ in range(int(g.integers(2, 6))):
        at = g.uniform(0.03, dur - 0.03)
        c = bandpass(noise(samples(0.012), g), 2200.0, 7000.0, 1) * env_decay(samples(0.012), 0.003, 0.0004) * g.uniform(0.15, 0.4)
        i = samples(at)
        s[i:i + len(c)] += c
    return normalize(fade(s, 0.0, 0.03))


def riser(dur=0.6, f0=320.0, f1=6800.0, g=None, width=0.75, curve=2.2):
    """往上扬的一段气声，到头就断（接着是重头戏）"""
    g = g or np.random.default_rng(0)
    s = swept_noise(dur, lambda tt: f0 * (f1 / f0) ** (tt / dur), width, g)
    t = _t(len(s)) / dur
    s *= t ** curve
    return normalize(fade(s, 0.01, 0.012))


def swish(dur=0.5, f0=900.0, f1=2600.0, g=None, width=0.9):
    """一阵风、一挥手、布料动了一下"""
    g = g or np.random.default_rng(0)
    s = swept_noise(dur, lambda tt: f0 * (f1 / f0) ** (tt / dur), width, g)
    s *= env_ar(len(s), dur * 0.45, dur * 0.4, 1.6)
    return normalize(fade(s, 0.01, 0.02))


def rumble(dur=1.0, g=None, cutoff=120.0):
    """远处的闷雷、大东西在动：很低的一片，时强时弱"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    s = lowpass(noise(n, g), cutoff, 3) * (0.35 + 0.65 * slow_lfo(n, 2.6, g))
    s *= env_ar(n, dur * 0.2, dur * 0.5, 1.3)
    return normalize(fade(s, 0.01, 0.05))


# ================================================================ 底：夜里的河面

def night_water(dur, g=None, flow=0.0):
    """夜里的河面，立体声。flow 大一点是流着的水（水车旁边），小是几乎不动的池塘"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    chans = []
    for _ in range(2):
        nz = noise(n, g)
        # 水一下一下拍着：低通噪声被一条慢起伏线调着强弱
        lapping = lowpass(nz, 540.0, 2) * (0.30 + 0.70 * slow_lfo(n, 0.42, g))
        # 水面自己的空腔感：两个相距不远的共鸣，哪个响一些慢慢地换来换去
        soft = lowpass(nz, 1100.0, 1)
        drift = slow_lfo(n, 0.17, g)
        hollow = resonant(soft, 265.0, 0.22, 2.2) * (1.0 - drift) + resonant(soft, 410.0, 0.22, 2.2) * drift
        flowing = bandpass(nz, 230.0, 2500.0, 1) * (0.45 + 0.55 * slow_lfo(n, 1.2, g)) * flow
        chans.append(lapping * 0.9 + hollow * 0.4 + flowing * 0.8)
    bed = np.stack(chans)
    # 零零星星的小水珠和气泡
    rate = 2.2 + 9.0 * flow
    for _ in range(int(dur * rate * g.uniform(0.8, 1.2))):
        at = g.uniform(0.0, dur - 0.35)
        if g.uniform() < 0.55:
            d = plink(g.uniform(900.0, 1300.0), g.uniform(1900.0, 3100.0), 0.16, g) * g.uniform(0.02, 0.06)
        else:
            d = bubble(g.uniform(260.0, 620.0), 0.06, g) * g.uniform(0.04, 0.10)
        i = samples(at)
        l, r = g.uniform(0.3, 1.0), g.uniform(0.3, 1.0)
        bed[0, i:i + len(d)] += d[: n - i] * l
        bed[1, i:i + len(d)] += d[: n - i] * r
    for ch in range(2):
        bed[ch] = lowpass(highpass(bed[ch], 45.0, 2), 2600.0, 2)
    # 两个声道各响各的太散了，叠一层两边都有的，合到一个喇叭上放也不会忽大忽小
    mid = bed.mean(axis=0)
    bed = bed * 0.75 + mid * 0.35
    return bed / np.abs(bed).max()


def room_air(dur, g=None):
    """宣纸那一段的底：很轻的空气声，比水面干一些"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    chans = []
    for _ in range(2):
        nz = noise(n, g)
        chans.append(bandpass(nz, 160.0, 2600.0, 2) * (0.3 + 0.7 * slow_lfo(n, 0.3, g)))
    bed = np.stack(chans)
    mid = bed.mean(axis=0)
    bed = bed * 0.75 + mid * 0.35
    return bed / np.abs(bed).max()

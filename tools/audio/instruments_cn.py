"""古筝、琵琶。

声音是照着弦振动的道理凑出来的，不是拿现成的采样（采样的来源和授权不好交代）：
    一根弦被拨响，响的是它的整倍数泛音。真实的弦有一点不整齐，越高的泛音偏得越多（B 是那个"不整齐"的程度）；
    拨在哪个位置，决定了哪些泛音响、哪些几乎不响：拨在弦长八分之一的地方，第八、十六个泛音就没了；
    越高的泛音灭得越快，所以起手亮、慢慢变暗；木头琴身又有几个固定的共鸣。
两样乐器在这些地方不一样：
    古筝  丝缠钢丝弦，二十一根，音域宽。起手的亮更软，余音长、会唱。吟揉是音高的细颤，
          按音是把弦按下去、音往上滑（滑一个到两个音），摇指是同一个音来回摇。
    琵琶  四根弦，品上按，戴义甲弹。义甲碰弦那一下很硬（一下很短的亮声），余音比古筝短，更脆。
          轮指是五个指头轮着弹同一条弦，听起来是一串很密的音而不是一个长音；扫弦是四根弦依次扫过去。
音高按升 C 宫五声（升 C、E、升 F、升 G、B），和标题音乐同一个调。MIDI 音高：升 C4 是 61。
"""
import importlib.util
import math
import os

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("synth", os.path.join(_here, "synth.py"))
synth = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(synth)
SR, samples, noise = synth.SR, synth.samples, synth.noise
lowpass, highpass, bandpass, resonant = synth.lowpass, synth.highpass, synth.bandpass, synth.resonant
fade, normalize, env_decay, env_ar = synth.fade, synth.normalize, synth.env_decay, synth.env_ar

# 升 C 宫五声：宫（升 C）、商（升 D）以外的四个加上角、徵、羽
PENTA = [61, 64, 66, 68, 71]          # 升 C4、E4、升 F4、升 G4、B4（往上一组就是 +12）


def hz(note):
    """MIDI 音高 → 频率。69 是 A4 = 440"""
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def penta(base=0, count=5, step=1):
    """五声里从 base 起往上数 count 个音（跨过一组就自动加 12）。返回 MIDI 音高的列表"""
    out = []
    i = 0
    while len(out) < count:
        k = base + i * step
        out.append(PENTA[k % 5] + 12 * (k // 5))
        i += 1
    return out


def _bend_curve(n, semitones, ms=110.0):
    """按音：音高从原来的地方滑到往上 semitones 个半音，用 ms 毫秒滑过去，之后停在那儿。
    返回每个采样点的频率倍数（1.0 是不变）"""
    t = np.arange(n) / SR
    k = 2.0 ** (semitones / 12.0)
    x = np.clip(t / max(ms / 1000.0, 1e-4), 0.0, 1.0)
    return 1.0 + (k - 1.0) * x ** 1.6


def _vibrato_curve(n, cents=16.0, rate=5.4, delay=0.22, grow=0.5):
    """吟揉：音高细细地颤，起手不颤，一点一点颤起来"""
    t = np.arange(n) / SR
    env = np.clip((t - delay) / max(grow, 1e-3), 0.0, 1.0)
    k = 2.0 ** (cents / 1200.0) - 1.0
    return 1.0 + k * env * np.sin(2.0 * np.pi * rate * t)


def _pluck(f0, dur, g, *, B=0.0002, modes=26, pluck=0.18, tau0=1.5, damp=0.5, bright=1.0,
           bend=None, click=0.0, click_band=(2200.0, 8500.0), click_ms=3.0,
           body_mix=1.0, body=None, detune=0.0):
    """拨一根弦：泛音一根一根叠起来，高的灭得快；可以带音高变化（吟揉、按音）"""
    n = samples(dur)
    t = np.arange(n) / SR
    f0 = max(f0, 20.0)
    sig = np.zeros(n)
    for k in range(1, modes + 1):
        fk = k * f0 * math.sqrt(1.0 + B * k * k)
        if fk > 9000.0:
            break
        amp = abs(math.sin(math.pi * k * pluck)) / (k ** 1.2)
        amp *= bright ** (k - 1)
        if amp < 2e-4:
            break
        tau = tau0 / (1.0 + damp * (k - 1) ** 1.05)
        fk2 = fk * (1.0 + detune)
        for f in ((fk,) if detune == 0.0 else (fk, fk2)):
            if bend is None:
                ph = 2.0 * np.pi * f * t
            else:
                ph = 2.0 * np.pi * np.cumsum(f * bend) / SR
            sig += amp * np.exp(-t / tau) * np.sin(ph)
    # 起手：指甲或义甲碰弦那一下
    if click > 0.0:
        c = bandpass(noise(n, g), click_band[0], click_band[1], 1) * env_decay(n, click_ms / 1000.0, 0.0004)
        sig += c * click * 2.4
    # 木头琴身的几个共鸣
    if body_mix > 0.0:
        for f, amount in (body or ()):
            sig = resonant(sig, f, 0.28, 1.0 + (amount - 1.0) * body_mix)
    sig *= 1.0 - np.exp(-t / 0.0012)
    return sig


def guzheng(note=61, dur=2.2, g=None, *, vibrato=16.0, bend=0.0, bright=0.9, pluck=0.18, gain=1.0, tail_noise=0.02):
    """古筝的一声。vibrato 是吟揉的深浅（音分，0 不颤）；bend 是按音往上滑几个半音"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    curve = _bend_curve(n, bend) if bend else None
    if vibrato > 0.0:
        v = _vibrato_curve(n, vibrato)
        curve = v if curve is None else curve * v
    sig = _pluck(hz(note), dur, g, B=0.00016, modes=30, pluck=pluck, tau0=1.9, damp=0.46,
                 bright=bright, bend=curve, click=0.10, click_band=(1500.0, 6500.0), click_ms=4.0,
                 body=((186.0, 1.7), (322.0, 1.5), (515.0, 1.3), (880.0, 1.15)), detune=0.0009)
    # 弦自己的一点气息：很轻的高频沙沙，跟着音量走
    if tail_noise > 0.0:
        air = bandpass(noise(n, g), 2600.0, 8000.0, 1) * np.exp(-np.arange(n) / SR / 0.35)
        sig += air * tail_noise
    return normalize(fade(sig * gain, 0.0, 0.05))


def pipa(note=61, dur=1.1, g=None, *, bright=1.0, pluck=0.16, gain=1.0, bend=0.0):
    """琵琶的一声：义甲碰弦那一下比古筝硬，余音短，更脆"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    # 推拉弦：推得越高，推的时间越长（推三个半音和推半个半音不一样）
    curve = _bend_curve(n, bend, ms=90.0 + 55.0 * abs(bend)) if bend else None
    sig = _pluck(hz(note), dur, g, B=0.00022, modes=26, pluck=pluck, tau0=0.85, damp=0.62,
                 bright=bright, bend=curve, click=0.42, click_band=(2400.0, 9000.0), click_ms=2.6,
                 body=((410.0, 1.8), (820.0, 1.5), (1680.0, 1.3), (2900.0, 1.2)), detune=0.0006)
    return normalize(fade(sig * gain, 0.0, 0.04))


# ================================================================ 技法

def drum(note=104.0, dur=1.0, g=None, gain=1.0, muffled=1.0, bend=0.22):
    """堂鼓：一面蒙皮的鼓，鼓槌打下去"咚"的一声。
    皮膜振动不像弦那样是整倍数（大致 1 : 1.59 : 2.14 : 2.65 : 3.16），越高的灭得越快；
    打下去那一瞬间音高先高后落（皮被撑紧又松回来），"砸"的感觉就在这一下；
    槌头打在皮上还有一点短促的中高频。muffled 小于 1 更闷（像闷鼓）"""
    g = g or np.random.default_rng(0)
    n = samples(dur)
    t = np.arange(n) / SR
    ratios = (1.0, 1.59, 2.14, 2.65, 3.16, 3.90)
    amps = (1.0, 0.58, 0.34, 0.20, 0.11, 0.06)
    taus = (0.34, 0.22, 0.15, 0.10, 0.07, 0.05)
    s = np.zeros(n)
    curve = 1.0 + bend * np.exp(-t / 0.035)
    for k in range(len(ratios)):
        f = note * ratios[k] * g.uniform(0.995, 1.005)
        amp = amps[k]
        ph = 2.0 * np.pi * np.cumsum(f * curve) / SR
        s += amp * np.sin(ph + g.uniform(0.0, 2.0 * np.pi)) * np.exp(-t / taus[k])
    # 槌头打在皮上
    s += bandpass(noise(n, g), 700.0, 3400.0, 1) * env_decay(n, 0.007, 0.0005) * 0.55
    s *= 1.0 - np.exp(-t / 0.0012)
    # 皮厚，声音闷
    s = lowpass(s, 1500.0 * muffled, 2)
    return normalize(fade(s * gain, 0.0, 0.06))


def guzheng_gliss(notes, dur=1.1, g=None, *, gain=1.0, each=0.9, easing=0.75, rising=True):
    """刮奏：手指从一头扫到另一头，一串音很快地过去。
    notes 是音高（从低到高排）；dur 是扫完用多久；each 是每个音自己响多久"""
    g = g or np.random.default_rng(0)
    notes = list(notes)
    if not rising:
        notes = notes[::-1]
    total = samples(dur + each) + SR // 10
    out = np.zeros(total)
    k = len(notes)
    for i, note in enumerate(notes):
        at = (i / max(k - 1, 1)) ** easing * dur
        at, amp = synth.humanize(g, at, 0.004, 0.16)
        s = guzheng(note, each, g, vibrato=0.0, bright=0.95, pluck=0.14)
        # 越往高音越轻（高音弦短、手扫得快），最后两个音再抬一点，收得住
        x = i / max(k - 1, 1)
        s = s * (0.95 - 0.35 * x + (0.18 if i >= k - 2 else 0.0))
        j = samples(at)
        m = min(len(s), total - j)
        out[j:j + m] += s[:m] * amp
    return normalize(fade(out * gain, 0.002, 0.12))


def guzheng_roll(note=73, dur=1.6, g=None, *, rate=8.5, gain=1.0):
    """摇指：同一个音来回摇，一串音连成一片"""
    g = g or np.random.default_rng(0)
    total = samples(dur + 0.8)
    out = np.zeros(total)
    t = 0.0
    i = 0
    while t < dur:
        at, amp = synth.humanize(g, t, 0.008, 0.12)
        s = guzheng(note, 0.75, g, vibrato=0.0, bright=0.92, pluck=0.12 + 0.04 * (i % 2))
        j = samples(at)
        m = min(len(s), total - j)
        # 摇指是越摇越开：两头轻一点
        shape = math.sin(math.pi * min(t / dur, 1.0)) ** 0.4
        out[j:j + m] += s[:m] * amp * (0.55 + 0.45 * shape)
        t += 1.0 / rate * g.uniform(0.94, 1.06)
        i += 1
    return normalize(fade(out * gain, 0.002, 0.12))


def pipa_roll(note=66, dur=1.4, g=None, *, rate=13.0, gain=1.0, accent=5):
    """轮指：五个指头轮着弹，一串很密的音。每五个里第一个重一点"""
    g = g or np.random.default_rng(0)
    total = samples(dur + 0.7)
    out = np.zeros(total)
    t = 0.0
    i = 0
    while t < dur:
        at, amp = synth.humanize(g, t, 0.006, 0.14)
        s = pipa(note, 0.45, g, bright=0.95, pluck=0.14 + 0.03 * (i % 2))
        j = samples(at)
        m = min(len(s), total - j)
        # 轮起来是一条由轻到响再收住的弧线
        swell = 0.55 + 0.45 * math.sin(math.pi * min(at / dur, 1.0)) ** 0.5
        out[j:j + m] += s[:m] * amp * (1.15 if i % accent == 0 else 0.8) * swell
        t += 1.0 / rate * g.uniform(0.93, 1.07)
        i += 1
    return normalize(fade(out * gain, 0.002, 0.1))


def pipa_strum(notes, dur=1.4, g=None, *, gain=1.0, spread=0.016, down=True, bend=0.0):
    """扫弦：四根弦依次扫过去，每根弦差十几毫秒"""
    g = g or np.random.default_rng(0)
    notes = list(notes)
    if not down:
        notes = notes[::-1]
    total = samples(dur) + SR // 10
    out = np.zeros(total)
    for i, note in enumerate(notes):
        at = i * spread * g.uniform(0.85, 1.15)
        s = pipa(note, dur, g, bright=1.05 if down else 0.95, pluck=0.2, bend=bend)
        j = samples(at)
        m = min(len(s), total - j)
        out[j:j + m] += s[:m] * (1.0 - 0.12 * i)
    return normalize(fade(out * gain, 0.001, 0.06))


def pipa_roll_bend(note=66, dur=1.6, g=None, *, rate=13.0, semitones=1.0, gain=1.0):
    """轮指加上推拉弦：一边轮一边把音推上去，是琵琶最有味道的句子之一"""
    g = g or np.random.default_rng(0)
    total = samples(dur + 0.7)
    out = np.zeros(total)
    t = 0.0
    while t < dur:
        at, amp = synth.humanize(g, t, 0.006, 0.14)
        # 推到哪儿：前四成在原音，之后慢慢推上去
        prog = min(max((at - dur * 0.35) / (dur * 0.5), 0.0), 1.0)
        s = pipa(note, 0.45, g, bright=0.95, pluck=0.15, bend=semitones * prog)
        j = samples(at)
        m = min(len(s), total - j)
        out[j:j + m] += s[:m] * amp
        t += 1.0 / rate * g.uniform(0.93, 1.07)
    return normalize(fade(out * gain, 0.002, 0.1))

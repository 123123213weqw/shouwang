"""算声音用的小工具，只用 numpy。给开场动画配音用的（tools/audio/opening.py），别的的地方要用也行。

这里都是离线渲染：同一段声音只由传进去的随机种子决定，每次算出来一模一样（和贴图脚本一个道理）。
滤波都在频率域里做：把整段声音做傅里叶变换，乘上滤波器的频率响应，再变回来。这样没有相位延迟，结果也稳定。
采样率固定 48000，和游戏里原有的音频一致。
"""
import wave
import numpy as np

SR = 48000


# ================================================================ 基础

def samples(dur):
    return int(round(dur * SR))


def time_axis(dur):
    return np.arange(samples(dur)) / SR


def noise(n, g):
    return g.standard_normal(n)


def _response(n, gain_of_freq):
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    with np.errstate(divide="ignore", invalid="ignore"):
        h = gain_of_freq(np.maximum(freqs, 1e-3))
    return np.nan_to_num(h, nan=0.0, posinf=0.0, neginf=0.0)


def _filter(x, gain_of_freq):
    n = len(x)
    if n < 16:
        return x.copy()
    # 补到 2 的整次幂再变换，快很多；频率响应按补完以后的长度算，所以要先补再算
    m = 1 << int(np.ceil(np.log2(n)))
    xp = np.concatenate([x, np.zeros(m - n)])
    return np.fft.irfft(np.fft.rfft(xp) * _response(m, gain_of_freq), m)[:n]


def lowpass(x, cutoff, order=2):
    """低通。order 每加一，斜率多 6 分贝/倍频程"""
    return _filter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / cutoff) ** (2 * order)))


def highpass(x, cutoff, order=2):
    return _filter(x, lambda f: 1.0 / np.sqrt(1.0 + (cutoff / f) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return lowpass(highpass(x, lo, order), hi, order)


def resonant(x, f0, width_oct=0.08, amount=6.0):
    """在某一个频率上凸起来一块（像空腔、木板自己的共鸣）。width_oct 是这块多宽（倍频程），amount 是最多放大几倍"""
    def gain(f):
        return 1.0 + (amount - 1.0) * np.exp(-0.5 * (np.log2(f / f0) / width_oct) ** 2)
    return _filter(x, gain)


def swept_noise(dur, freq_of_t, width_oct=0.6, g=None, hop=0.006, n_fft=2048):
    """频率随时间变的一段噪声：呼啸、上扬、火苗、水流都用它。
    freq_of_t(秒) 给出那一刻噪声的中心频率。一小窗一小窗地做：每窗只留下中心频率附近的那些频率，再叠回去"""
    g = g or np.random.default_rng(1)
    n = samples(dur)
    x = noise(n + n_fft, g)
    win = np.hanning(n_fft)
    hop_n = samples(hop)
    out = np.zeros(n + n_fft)
    weight = np.zeros(n + n_fft)
    freqs = np.fft.rfftfreq(n_fft, 1.0 / SR)
    freqs[0] = freqs[1]
    for start in range(0, n, hop_n):
        seg = x[start:start + n_fft] * win
        fc = float(freq_of_t((start + n_fft / 2.0) / SR))
        mask = np.exp(-0.5 * (np.log2(freqs / fc) / width_oct) ** 2)
        out[start:start + n_fft] += np.fft.irfft(np.fft.rfft(seg) * mask) * win
        weight[start:start + n_fft] += win * win
    weight[weight < 1e-6] = 1.0
    return (out / weight)[:n]


def env_decay(n, tau, attack=0.003):
    """一下敲下去然后慢慢消失的那种包络：attack 秒升到最响，再按 tau（秒）指数衰减"""
    t = np.arange(n) / SR
    e = np.exp(-t / tau)
    a = samples(attack)
    if a > 0:
        e[:a] *= np.linspace(0.0, 1.0, a) ** 1.5
    return e


def env_ar(n, attack, release, curve=2.0):
    """升上去再落下来，两头都是曲线"""
    t = np.arange(n) / SR
    dur = n / SR
    up = np.clip(t / max(attack, 1e-4), 0, 1) ** curve
    down = np.clip((dur - t) / max(release, 1e-4), 0, 1) ** curve
    return np.minimum(up, down)


def slow_lfo(n, rate, g, smooth=0.4, lo=0.0, hi=1.0):
    """慢悠悠、不规则的一条起伏线（0 到 1 之间），给水面、风声做时强时弱用。rate 是每秒大概起伏几次"""
    k = max(2, int(n / SR * rate) + 3)
    pts = g.uniform(lo, hi, k)
    xs = np.linspace(0, n - 1, k)
    return np.interp(np.arange(n), xs, pts)


def fade(x, fin=0.002, fout=0.01):
    """两头各淡一点，免得接缝处咔哒一声"""
    x = x.copy()
    a, b = min(samples(fin), len(x)), min(samples(fout), len(x))
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


def normalize(x, peak=1.0):
    m = float(np.abs(x).max())
    return x * (peak / m) if m > 1e-12 else x


def humanize(g, t, jitter=0.012, spread=0.12):
    """人手做出来的东西不会一丝不差：时刻前后差十几毫秒，轻重有涨落。
    返回 (挪动过的时刻, 轻重的倍数)。jitter 是时刻大概差多少秒，spread 是轻重大概差多少成"""
    return max(0.0, float(t) + g.normal(0.0, jitter / 2.0)), float(np.exp(g.normal(0.0, spread)))


# ================================================================ 立体声和混响

def pan_gains(p):
    """等功率的左右分配：p 是 -1（全在左）到 1（全在右）"""
    a = (np.clip(p, -1.0, 1.0) + 1.0) * np.pi / 4.0
    return np.cos(a), np.sin(a)


def make_ir(rt60=1.2, predelay=0.02, g=None, brightness=4200.0, early=((0.011, 0.45), (0.019, 0.3), (0.031, 0.24), (0.047, 0.16))):
    """一条人工的混响响应（左右各一条）：夜里水面上那种开阔、偏暗的空间。
    前几十毫秒亮一些（early 是几颗早反射），越往后越暗，声音在 rt60 秒里衰到听不见"""
    g = g or np.random.default_rng(7)
    n = samples(rt60 * 1.25)
    t = np.arange(n) / SR
    tails = []
    for _ in range(2):
        nz = noise(n, g)
        bright = lowpass(nz, brightness, 1)
        dark = lowpass(nz, 1900.0, 2)
        blend = np.exp(-t / 0.45)           # 前面亮、后面暗
        tail = (bright * blend + dark * (1.0 - blend)) * np.exp(-6.91 * t / rt60)
        for delay, gain in early:
            i = samples(delay)
            if i < n:
                tail[i] += gain * 2.5
        tail = lowpass(tail, 9000.0, 1)
        pd = samples(predelay)
        tail = np.concatenate([np.zeros(pd), tail])[: n + pd]
        tail[:samples(0.003)] *= np.linspace(0.0, 1.0, samples(0.003))
        tails.append(tail / np.sqrt((tail ** 2).sum()))
    return tails[0], tails[1]


def _conv(x, ir):
    n = len(x) + len(ir) - 1
    m = 1 << int(np.ceil(np.log2(n)))
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]


class Mix:
    """一条立体声的时间线：把一段段单声道的声音按时刻、左右位置、轻重放上去，最后统一加混响、收尾、写出文件"""

    def __init__(self, dur, ir, g=None):
        self.n = samples(dur)
        self.dry = np.zeros((2, self.n))
        self.send = np.zeros(self.n)
        self.ir = ir
        self.g = g or np.random.default_rng(3)
        self.log = []

    def add(self, sig, at, gain=1.0, p=0.0, rev=0.35):
        """把 sig 放在 at 秒处。p 是左右位置（-1 到 1），gain 是轻重，rev 是送进混响的比例（0 全干，1 全湿）"""
        if sig is None or len(sig) == 0:
            return
        i = samples(at)
        if i >= self.n:
            return
        sig = sig[: self.n - i]
        l, r = pan_gains(p)
        w = gain / (1.0 + rev)
        self.dry[0, i:i + len(sig)] += sig * l * w * (1.0 - rev)
        self.dry[1, i:i + len(sig)] += sig * r * w * (1.0 - rev)
        self.send[i:i + len(sig)] += sig * w * rev * np.sqrt(2.0) * 0.5
        self.log.append((at, gain, p))

    def render(self):
        wet = np.stack([_conv(self.send, self.ir[0]), _conv(self.send, self.ir[1])])[:, : self.n]
        out = self.dry + wet * 1.0
        out = np.stack([highpass(ch, 28.0, 2) for ch in out])
        return out


def finish(out, peak_db=-3.0, drive=0.0):
    """收尾：轻轻压一下（drive 大压得多，给一点模拟设备那种黏在一起的感觉），再把最响的地方对到 peak_db"""
    out = out.copy()
    if drive > 0.0:
        out = np.tanh(out * drive) / np.tanh(drive)
    m = float(np.abs(out).max())
    if m > 1e-12:
        out = out * (10.0 ** (peak_db / 20.0) / m)
    return out


def write_wav(path, out):
    """写 16 位的 WAV。写之前加一点点抖动（量化噪声），安静的地方不会有发颗粒的感觉"""
    assert out.shape[0] == 2, "out 应该是 2 × 样本数"
    q = np.clip(out.T, -1.0, 1.0)
    dither = (np.random.default_rng(99).random(q.shape) - np.random.default_rng(100).random(q.shape)) / 32768.0
    pcm = np.round((q + dither) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ================================================================ 看结果用的数（我听不见，只能量）

def report(out, step=0.25):
    """每 step 秒报一次响度（有效值，分贝），外加最响的地方和左右是不是反相"""
    n = out.shape[1]
    rows = []
    for i in range(0, n, samples(step)):
        seg = out[:, i:i + samples(step)]
        rms = float(np.sqrt((seg ** 2).mean())) if seg.size else 0.0
        rows.append("%5.1f" % (20 * np.log10(rms + 1e-9)))
    peak = 20 * np.log10(float(np.abs(out).max()) + 1e-12)
    corr = float(np.corrcoef(out[0], out[1])[0, 1])
    return "每 %.2f 秒的有效值（分贝）：%s\n最响 %.1f 分贝，左右相关 %.2f（应大于 0）" % (step, " ".join(rows), peak, corr)

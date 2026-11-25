#!/usr/bin/env python3
"""把一段声音画成图：上面是频谱（低频在下、高频在上，越亮越响），下面是左右声道的波形，再标出每半秒的响度。
我听不见声音，靠这张图看：每一下是不是落在该落的时刻、在不在该在的频段、有没有削顶。
用法: python3 tools/audio/look.py <音频文件> [输出图]      也可以从别的脚本里调 draw(数组, 路径, 标题)
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

import importlib.util
_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("synth", os.path.join(_here, "synth.py"))
synth = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(synth)

NOTES = {"C#3": 138.59, "F#3": 185.0, "G#3": 207.65, "C#4": 277.18, "F#4": 369.99, "G#4": 415.3, "B4": 493.88,
         "C#5": 554.37, "F#5": 739.99, "G#5": 830.61, "C#6": 1108.73}


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(synth.SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.copy()


def draw(out, path, title=""):
    """out 是 2 × 样本数的立体声数组"""
    SR = synth.SR
    mono = out.mean(axis=0)
    n = len(mono)
    dur = n / SR
    W, HS, HW, HH = 1160, 460, 150, 60
    img = Image.new("RGB", (W, 14 + HS + 8 + HW + HH), (14, 16, 16))
    d = ImageDraw.Draw(img)
    # 频谱
    N, hop = 4096, max(1, n // (W * 2))
    win = np.hanning(N)
    frames = []
    for i in range(0, max(n - N, 1), hop):
        seg = mono[i:i + N]
        if len(seg) < N:
            seg = np.concatenate([seg, np.zeros(N - len(seg))])
        frames.append(np.abs(np.fft.rfft(seg * win)))
    S = np.array(frames).T
    freqs = np.fft.rfftfreq(N, 1.0 / SR)
    ys = np.geomspace(40.0, 16000.0, HS)
    idx = np.clip(np.searchsorted(freqs, ys), 0, len(freqs) - 1)
    cols = np.linspace(0, S.shape[1] - 1, W)
    grid = np.zeros((HS, W))
    for x in range(W):
        a, b = int(cols[x]), max(int(cols[x]) + 1, int(cols[min(x + 1, W - 1)]) + 1)
        grid[:, x] = S[idx, a:b].max(axis=1) if b > a else S[idx, a]
    db = 20 * np.log10(grid + 1e-9)
    top = float(db.max())
    v = np.clip((db - (top - 84.0)) / 84.0, 0, 1)
    spec = np.stack([v ** 0.7, v ** 1.4, v ** 2.6], axis=2)[::-1]      # 低频画在下面
    img.paste(Image.fromarray((spec * 255).astype(np.uint8)), (14, 14))
    # 时间的网格线：每 0.5 秒一条，每整秒写数字
    for k in range(int(dur * 2) + 1):
        t = k * 0.5
        x = 14 + int(t / dur * (W - 1))
        if x >= 14 + W:
            break
        for y in range(14, 14 + HS):
            c = img.getpixel((x, y))
            img.putpixel((x, y), (c[0] // 2, c[1] // 2, c[2] // 2))
        if k % 2 == 0:
            d.text((x + 2, 14 + HS + 1 - 12), "%.0f" % t, fill=(200, 210, 200))
    # 几个音的位置（左边标出来）
    for name, f in NOTES.items():
        if name.endswith("4") or name in ("C#5", "C#6", "C#3"):
            y = 14 + HS - 1 - int(np.searchsorted(ys, f))
            d.line([(14, y), (22, y)], fill=(230, 230, 120))
            d.text((24, y - 6), name, fill=(200, 200, 120))
    for f in (100.0, 1000.0, 10000.0):
        y = 14 + HS - 1 - int(np.searchsorted(ys, f))
        d.text((W - 60 + 14, y - 6), "%gk" % (f / 1000.0) if f >= 1000 else "%g" % f, fill=(150, 160, 150))
    # 波形
    top_y = 14 + HS + 8
    step = max(1, n // (W * 2))
    for ch, colour in ((0, (120, 220, 170)), (1, (220, 170, 110))):
        seg = out[ch][: n // step * step].reshape(-1, step)
        lo, hi = seg.min(axis=1), seg.max(axis=1)
        xs = (np.arange(len(seg)) / max(len(seg) - 1, 1) * (W - 1) + 14).astype(int)
        for i in range(len(seg)):
            d.line([(int(xs[i]), top_y + HW // 2 - int(hi[i] * HW / 2)), (int(xs[i]), top_y + HW // 2 - int(lo[i] * HW / 2))], fill=colour)
    d.line([(14, top_y + HW // 2), (14 + W, top_y + HW // 2)], fill=(60, 70, 60))
    # 每 0.25 秒的响度
    base_y = top_y + HW + 6
    d.line([(14, base_y), (14 + W, base_y)], fill=(60, 70, 60))
    for k in range(int(dur * 4)):
        i = k * SR // 4
        seg = out[:, i:i + SR // 4]
        lv = 20 * np.log10(float(np.sqrt((seg ** 2).mean())) + 1e-9) if seg.size else -120.0
        h = max(1, int(np.clip((lv + 50.0) / 50.0, 0, 1) * HH))
        x0 = 14 + int(k / (dur * 4) * W)
        d.rectangle([x0 + 1, base_y - h, x0 + max(int(W / (dur * 4)) - 2, 2), base_y - 1], fill=(90, 150, 190))
        if k % 2 == 0:
            d.text((x0 + 1, base_y - h - 11), "%d" % round(lv), fill=(170, 190, 200))
    d.text((14, 1), "%s   %.2f 秒   最响 %.1f 分贝" % (title, dur, 20 * np.log10(float(np.abs(out).max()) + 1e-12)), fill=(220, 220, 210))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    img.save(path)
    return path


if __name__ == "__main__":
    sys.exit(draw(load(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else sys.argv[1] + ".png", os.path.basename(sys.argv[1])) and 0)

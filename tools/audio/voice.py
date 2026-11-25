#!/usr/bin/env python3
"""开场动画的旁白（可选）：台词在这里，真人录好了用这个脚本收拾干净，放进游戏。

    台词（三句是一套的："……一……，……就……"，一句两秒上下，赶在揭出标题之前说完）
        A 一灯破夜      灯一亮，夜就有了边。
        B 水墨惊雷      笔一落，山河就醒了。
        D 守夜人点灯    人一到，灯就点上了。

    旁白是人的声音，不由脚本生成：要么自己录，要么请人录。录的办法（在本机，要用到麦克风）：
        tools/audio/record_voice.sh A            录 A 那一句，录 4 秒，存到 builds/voice/voiceA_raw.wav
    录完收拾干净、放进游戏：
        python3 tools/audio/voice.py A           读 builds/voice/voiceA_raw.wav → assets/audio/opening/voiceA.wav
    放进游戏以后什么都不用改：开场一播，这句话在 NARRATION_AT 秒（见 scripts/uis/opening.gd）放出来，
    那几秒开场自己的声音会轻一截，说完回来。没有 voice<A>.wav 就不放，和现在一样。

    收拾的几步：去掉 80 赫兹以下的房间的隆隆声；把底噪压掉（按这段录音里最安静的地方估底噪有多响）；
    掐掉开头结尾的空白；两头的接缝淡一淡；轻重对到和开场里弦乐差不多（有效值 -20 分贝）。
用法（在工程根目录）: python3 tools/audio/voice.py <A|B|D> [原始录音，默认 builds/voice/voice<A>_raw.wav]
"""
import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
_spec = importlib.util.spec_from_file_location("look", os.path.join(HERE, "look.py"))
look = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(look)
synth = look.synth

LINES = {"A": "灯一亮，夜就有了边。", "B": "笔一落，山河就醒了。", "D": "人一到，灯就点上了。"}
TARGET_DB = -20.0          # 收拾完以后的有效值（分贝），和开场里的磬差不多
LONGEST = 2.3              # 一句话最长几秒：再长就压到揭出标题以后去了


def denoise(x, g=None):
    """谱减法压底噪：一小窗一小窗地看，比底噪高不多少的频率当成噪声扣掉一些"""
    n_fft, hop = 2048, 512
    win = np.hanning(n_fft)
    pad = np.concatenate([np.zeros(n_fft), x, np.zeros(n_fft)])
    frames = np.stack([pad[i:i + n_fft] * win for i in range(0, len(pad) - n_fft, hop)])
    mag = np.abs(np.fft.rfft(frames, axis=1))
    power = mag ** 2
    # 底噪：按频率取"最安静的 15% 的小窗"的平均
    floor = np.sort(power, axis=0)[: max(4, int(len(power) * 0.15))].mean(axis=0)
    floor = np.maximum(floor, np.median(floor) * 0.2)
    gain = np.clip(1.0 - 2.2 * floor / (power + 1e-12), 0.08, 1.0)
    out_frames = np.fft.irfft(np.fft.rfft(frames, axis=1) * gain, n=n_fft, axis=1)
    out = np.zeros(len(pad))
    weight = np.zeros(len(pad))
    for i, fr in enumerate(out_frames):
        out[i * hop:i * hop + n_fft] += fr * win
        weight[i * hop:i * hop + n_fft] += win * win
    weight[weight < 1e-6] = 1.0
    return (out / weight)[n_fft:n_fft + len(x)]


def clean(raw, g=None):
    x = raw.mean(axis=0) if raw.ndim == 2 else raw
    x = synth.highpass(x, 85.0, 2)
    x = denoise(x, g)
    x = synth.highpass(x, 85.0, 2)
    # 掐掉开头结尾的空白：按 20 毫秒一窗看，比最响的时候低 38 分贝以下的当成空白
    win = synth.SR // 50
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    loud = float(env.max())
    on = np.nonzero(env > loud * 10.0 ** (-38.0 / 20.0))[0]
    if len(on) == 0:
        raise SystemExit("这段录音里没听到声音")
    a, b = max(0, int(on[0]) - synth.samples(0.06)), min(len(x), int(on[-1]) + synth.samples(0.10))
    x = x[a:b]
    if len(x) > synth.samples(LONGEST):
        raise SystemExit("这句话 %.1f 秒，比 %.1f 秒长，说不完就揭出标题了。请录得紧凑一点" % (len(x) / synth.SR, LONGEST))
    rms = float(np.sqrt((x ** 2).mean()))
    x = x * (10.0 ** (TARGET_DB / 20.0) / rms)
    x = synth.fade(x, 0.015, 0.06)
    if float(np.abs(x).max()) > 0.7:
        x = x * (0.7 / float(np.abs(x).max()))       # 最响的一个采样点留着头寸
    return x


def main(argv):
    if not argv or argv[0] not in LINES:
        print(__doc__)
        return 1
    key = argv[0]
    src = argv[1] if len(argv) > 1 else os.path.join(ROOT, "builds", "voice", "voice%s_raw.wav" % key)
    if not os.path.exists(src):
        print("找不到 %s。先录：tools/audio/record_voice.sh %s" % (src, key))
        return 1
    x = clean(look.load(src))
    dst = os.path.join(ROOT, "assets", "audio", "opening", "voice%s.wav" % key)
    synth.write_wav(dst, np.stack([x, x]))            # 存成两个声道一样的立体声，和别的音频文件一致
    print("== %s「%s」→ %s（%.2f 秒，有效值 %.1f 分贝）" % (key, LINES[key], os.path.relpath(dst, ROOT), len(x) / synth.SR,
                                                         20 * np.log10(float(np.sqrt((x ** 2).mean())))))
    img = os.path.join(ROOT, "builds", "audio", "voice%s.png" % key)
    look.draw(np.stack([x, x]), img, "%s %s" % (key, LINES[key]))
    print("   画了一张图：%s" % os.path.relpath(img, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

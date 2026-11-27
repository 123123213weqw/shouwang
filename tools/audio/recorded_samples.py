"""Play and edit pinned open-licensed instrument and foley recordings."""

import argparse
from collections import defaultdict
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import urllib.request

import numpy as np


RATE = 48000
MANIFEST = Path(__file__).with_suffix(".json")
SOURCES = json.loads(MANIFEST.read_text(encoding="utf-8"))["samples"]
FAMILIES = defaultdict(list)
for source in SOURCES:
    FAMILIES[source["family"]].append(source)


def fetch(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for source in SOURCES:
        target = directory / source["file"]
        if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == source["sha256"]:
            continue
        with urllib.request.urlopen(source["url"], timeout=90) as remote:
            raw = remote.read()
        if hashlib.sha256(raw).hexdigest() != source["sha256"]:
            raise ValueError(f"Source changed: {source['url']}")
        target.write_bytes(raw)


def count(duration):
    return round(duration * RATE)


def pentatonic(note, tonic):
    scale = (0, 2, 4, 7, 9)
    return min(range(round(note) - 2, round(note) + 3),
               key=lambda option: (0 if (option - tonic) % 12 in scale else 1, abs(option - note)))


def fade(signal, attack=0.004, release=0.035):
    front = min(count(attack), len(signal) // 2)
    back = min(count(release), len(signal) // 2)
    if front:
        signal[:front] *= np.sin(np.linspace(0, np.pi / 2, front)) ** 2
    if back:
        signal[-back:] *= np.cos(np.linspace(0, np.pi / 2, back)) ** 2
    return signal


@lru_cache(maxsize=None)
def read(source_file, sha256):
    import soundfile as sf

    directory = Path(os.environ.get("SHOUWANG_SAMPLES", Path(__file__).parent / "recordings"))
    path = directory / source_file
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != sha256:
        raise ValueError(f"Unexpected recording checksum: {path}")
    signal, rate = sf.read(path, dtype="float32", always_2d=True)
    signal = np.mean(signal, axis=1)
    signal -= np.mean(signal)
    return signal, rate


@lru_cache(maxsize=None)
def take_audio(source_file, sha256, trim, start, end):
    signal, rate = read(source_file, sha256)
    signal = signal[round(rate * start):round(rate * end) if end is not None else None]
    peak = max(float(np.max(np.abs(signal))), 1e-8)
    if trim:
        onset = np.argmax(np.abs(signal) > peak * 0.035)
        signal = signal[max(0, onset - round(rate * 0.006)):]
    return signal / peak, rate


def lowpass(signal, cutoff):
    freqs = np.fft.rfftfreq(len(signal), 1 / RATE)
    response = 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(np.fft.rfft(signal) * response, n=len(signal))


def sound(family, duration, *, note=None, take=0, speed=1, gain=0.86,
          attack=0.004, release=0.042, cutoff=None, reverse=False, trim=True, offset=0.0):
    sources = FAMILIES[family]
    if note is not None:
        source = min(sources, key=lambda item: abs(item["note"] - note))
        speed *= 2 ** ((note - source["note"]) / 12)
    else:
        source = sources[int(take) % len(sources)]
    recorded, rate = take_audio(source["file"], source["sha256"], trim,
                                source.get("start", 0.0), source.get("end"))
    speed = rate * speed / RATE
    positions = offset * rate + np.arange(count(duration)) * speed
    if reverse:
        positions = positions[::-1]
    result = np.interp(positions, np.arange(len(recorded)), recorded, right=0)
    if cutoff is not None:
        result = lowpass(result, cutoff)
    return fade(result, attack, release) * gain


def texture(duration, low, high, take=0, family="shaker"):
    source = sound(family, duration, take=take, speed=0.45 if duration > 1 else 0.87,
                   attack=0.009, release=min(0.08, duration * 0.2), trim=False)
    frequencies = np.fft.rfftfreq(len(source), 1 / RATE)
    response = (frequencies / np.maximum(frequencies, low)) / (1 + (frequencies / high) ** 4) ** 0.5
    signal = np.fft.irfft(np.fft.rfft(source) * response, n=len(source))
    return fade(signal, 0.006, min(0.05, duration * 0.2))


def room(duration, depth=1, resonant=False):
    output = np.zeros((count(duration), 2), dtype=np.float32)
    crossfade = 0.58
    # Circular overlap keeps bow and drum tails continuous when a track repeats.
    chunks = max(2, round(duration / 3.4))
    interval = duration / chunks
    for chunk in range(chunks):
        start = count(chunk * interval)
        length = min(duration, interval + crossfade)
        waves = sound("ocean", length, take=chunk, speed=0.68 + 0.09 * (chunk % 3),
                      attack=crossfade, release=crossfade, cutoff=950, trim=False)
        if resonant:
            resonance = sound("glass", length, note=(47, 52, 54, 57)[chunk % 4],
                              attack=crossfade, release=crossfade, cutoff=1750, trim=False)
            waves = waves * 0.60 + resonance * 0.40
        side = 0.18 if chunk % 2 == 0 else -0.18
        stereo = waves[:, None] * np.array([0.70 + side, 0.70 - side])
        positions = (start + np.arange(len(waves))) % len(output)
        output[positions] += stereo * (0.023 * depth)
    return output


class Foley:
    def splash(self, size, duration, rng):
        return sound("water", duration, take=rng.integers(2), speed=0.91 + 0.27 * size,
                     release=min(0.095, duration * 0.4))

    def swish(self, duration, low, high, rng):
        return texture(duration, low * 0.75, max(low, high), rng.integers(3))

    def stone_step(self, rng, wet=True):
        result = sound("step", 0.245, speed=rng.uniform(0.89, 1.16), cutoff=4600)
        if wet:
            result += 0.21 * self.splash(0.26, 0.245, rng)
        return result

    def gurgle(self, duration, rng, low):
        return sound("water", duration, take=rng.integers(2), speed=0.71 + min(low, 400) / 940,
                     cutoff=2300)

    def creak(self, duration, rng, lo, hi):
        return sound("cymbal", duration, speed=rng.uniform(0.45, 0.60), cutoff=max(750, hi * 2))

    def flame(self, rng, dur):
        return texture(dur, 1450, 4500, rng.integers(3))

    def night_water(self, duration, rng, flow):
        return room(duration, depth=8 + 9 * flow).T

    def riser(self, duration, low, high, rng):
        return sound("cymbal", duration, take=1, speed=0.7, reverse=True, attack=duration * 0.47,
                     release=duration * 0.17, cutoff=high)

    def bubble(self, root, duration, rng):
        return sound("water", duration, take=rng.integers(2), speed=0.84 + root / 2350, cutoff=3100)

    def brush(self, duration, rng):
        return texture(duration, 390, 3400, rng.integers(3))

    def woodblock(self, root, duration, rng):
        return sound("block", duration, take=rng.integers(3), speed=min(1.38, root / 780))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", type=Path, required=True)
    fetch(parser.parse_args().fetch)

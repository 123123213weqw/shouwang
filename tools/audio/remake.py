#!/usr/bin/env python3
"""Synthesize the Deep Water Glow audio set and a 25-second audition.

Run: python -B remake.py --output assets/audio --preview preview.wav
Python and NumPy are the only requirements. No samples or project files are read.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import wave

import numpy as np


RATE = 48_000
TAU = 2 * np.pi
HERE = Path(__file__).resolve().parent
GAME = "GameOff_Mus_01 Loop.wav"
TITLE = "GameOff_Mus_02 MainTitle 143bpm Loop.wav"


def frames(seconds: float) -> int:
    return round(seconds * RATE)


def seconds(duration: float) -> np.ndarray:
    return np.arange(frames(duration), dtype=np.float64) / RATE


def frequency(note: float) -> float:
    return float(440 * 2 ** ((note - 69) / 12))


def phase(freq: np.ndarray) -> np.ndarray:
    return TAU * (np.cumsum(freq) - freq[0]) / RATE


def smooth(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def envelope(t: np.ndarray, attack: float, release: float) -> np.ndarray:
    return smooth(t / attack) * smooth((t[-1] - t) / release)


def sound_db(db: float) -> float:
    return 10 ** (db / 20)


def add(bus: np.ndarray, signal: np.ndarray, at: float, gain: float,
        pan: float = 0.0, wrap: bool = False) -> None:
    """Place a mono sound, optionally sending its tail to the loop beginning."""
    start = frames(at)
    if wrap:
        start %= len(bus)
    if start >= len(bus):
        return
    if bus.ndim == 2:
        angle = (pan + 1) * np.pi / 4
        signal = signal[:, None] * np.array([np.cos(angle), np.sin(angle)])
    end = min(len(bus), start + len(signal))
    copied = end - start
    bus[start:end] += gain * signal[:copied]
    if wrap and copied < len(signal):
        tail = signal[copied:]
        bus[:len(tail)] += gain * tail


def foam(duration: float, low: float, high: float,
         rng: np.random.Generator) -> np.ndarray:
    """Band-shaped noise with rounded edges, used for swells and bubbles."""
    n = frames(duration)
    hz = np.fft.rfftfreq(n, 1 / RATE)
    shape = (1 - np.exp(-(hz / low) ** 2)) * np.exp(-(hz / high) ** 2)
    tone = np.fft.irfft(np.fft.rfft(rng.normal(size=n)) * shape, n)
    return np.tanh(tone / (2.2 * (tone.std() + 1e-9)))


def bubble(duration: float, low: float, high: float,
           rng: np.random.Generator) -> np.ndarray:
    t = seconds(duration)
    pitch = high + (low - high) * np.exp(-4.1 * t / duration)
    carrier = phase(pitch)
    breath = foam(duration, 550, 4600, rng)
    decay = envelope(t, 0.0035, duration * 0.42) * np.exp(-2.5 * t / duration)
    return decay * (0.78 * np.sin(carrier) + 0.16 * np.sin(2.2 * carrier) + 0.24 * breath)


def bell(note: float, duration: float, brightness: float = 1.0) -> np.ndarray:
    """Soft sine FM with fast upper partial decay and an inharmonic ring."""
    t = seconds(duration)
    p = TAU * frequency(note) * t
    depth = brightness * (0.13 + 1.2 * np.exp(-t / 0.064))
    glass = np.sin(p + depth * np.sin(2.013 * p))
    partial = 0.20 * brightness * np.sin(2.776 * p) * np.exp(-t / 0.145)
    shimmer = 0.09 * brightness * np.sin(4.139 * p) * np.exp(-t / 0.063)
    return (glass + partial + shimmer) * np.exp(-3.4 * t / duration) * envelope(
        t, 0.005, min(0.24, duration * 0.29)
    )


def glass_lead(note: float, duration: float, color: float) -> np.ndarray:
    """Breathy submerged glass, using a short harmonic bloom above a rounded fundamental."""
    t = seconds(duration)
    p = TAU * frequency(note) * t
    bend = 0.34 * np.exp(-t / 0.073) - 0.34
    swell = 0.46 + 0.54 * np.exp(-t / 0.64)
    edge = 0.24 * color * np.sin(1.997 * p + bend + 0.55)
    shine = 0.067 * color * np.sin(3.011 * p) * np.exp(-t / 0.315)
    return (0.8 * np.sin(p + bend) + edge + shine) * swell * envelope(
        t, 0.032 + 0.013 * (1 - color), min(0.47, duration * 0.66)
    )


def pad(note: float, duration: float, attack: float, release: float,
        color: float, seed_phase: float) -> np.ndarray:
    t = seconds(duration)
    p = TAU * frequency(note) * t
    drift = 0.28 * np.sin(TAU * 0.39 * t + seed_phase)
    drift += 0.075 * np.sin(TAU * 1.13 * t + seed_phase * 2)
    tide = 0.5 + 0.5 * np.sin(TAU * 0.18 * t + seed_phase)
    core = 0.59 * np.sin(p + drift)
    overtone = np.sin(2.003 * p + 2.3 * drift + 0.5)
    choir = np.sin(3.996 * p + 0.11 * np.sin(1.995 * p) + 0.7)
    return envelope(t, attack, release) * (
        core + (0.12 + 0.15 * color) * overtone * (0.55 + 0.45 * tide)
        + 0.16 * color * choir * tide + 0.11 * np.sin(0.999 * p - drift + 1.65)
    )


def wash(duration: float, from_hz: float, to_hz: float,
         rng: np.random.Generator) -> np.ndarray:
    t = seconds(duration)
    p = phase(from_hz * (to_hz / from_hz) ** (t / duration))
    glimmer = np.sin(p + 0.42 * np.sin(p * 1.67))
    water = foam(duration, 180, 2900, rng)
    return envelope(t, duration * 0.61, duration * 0.19) * (0.53 * glimmer + 0.54 * water)


def impact(duration: float, start: float, end: float,
           rng: np.random.Generator) -> np.ndarray:
    t = seconds(duration)
    p = phase(end + (start - end) * np.exp(-t / (duration * 0.14)))
    shell = 0.67 * np.sin(p) + 0.19 * np.sin(1.73 * p)
    click = foam(duration, 400, 2900, rng) * np.exp(-t / 0.023)
    return envelope(t, 0.003, duration * 0.2) * (
        shell * np.exp(-t / (duration * 0.21)) + 0.39 * click
    )


def current(duration: float) -> np.ndarray:
    """A periodic subsurface room tone with slow counter-moving stereo currents."""
    samples = np.arange(frames(duration), dtype=np.float64)
    orbit = TAU * samples / len(samples)
    bed = np.zeros((len(samples), 2), dtype=np.float32)
    tones = ((41.0, 0.0095, 3, 0.51), (58.0, 0.0062, 5, 1.12),
             (84.0, 0.0060, 7, 2.49), (113.0, 0.0043, 4, 2.79),
             (197.0, 0.0038, 6, 1.07), (318.0, 0.0028, 9, 0.44),
             (531.0, 0.0018, 7, 4.40), (816.0, 0.0014, 11, 3.21))
    for pitch, gain, cycle, offset in tones:
        carrier = orbit * round(pitch * duration)
        for channel, direction in enumerate((-1, 1)):
            tide = orbit * cycle + direction * 0.71 + offset
            bed[:, channel] += gain * (0.53 + 0.47 * np.sin(tide)) * np.sin(
                carrier + offset + 0.35 * np.sin(tide * 2) + direction * 0.12
            )
    return bed


def space(bus: np.ndarray, wet: float, wrap: bool) -> np.ndarray:
    """Widen with several oblique reflections, wrapping only on music loops."""
    dry = bus.copy()
    taps = ((0.071, 0.32, False), (0.113, 0.36, True), (0.183, 0.27, True),
            (0.286, 0.20, False), (0.441, -0.15, True), (0.647, 0.13, False),
            (0.951, 0.075, True), (1.278, -0.04, True))
    for delay, gain, cross in taps:
        offset = frames(delay)
        src = dry[:, ::-1] if cross else dry
        if offset < len(bus):
            bus[offset:] += (wet * gain) * src[:-offset]
            if wrap:
                bus[:offset] += (wet * gain) * src[-offset:]
    return bus


# D Dorian, voiced to favor 9ths and open fifths above unpitched water.
DM9 = (38, 50, 57, 60, 64, 65)
G6 = (43, 55, 59, 62, 64, 69)
FMAJ = (41, 53, 57, 60, 64, 67)
CM9 = (36, 52, 55, 59, 62, 67)
AM7 = (45, 52, 55, 60, 64, 71)
ESUS = (40, 52, 57, 62, 67, 71)
DB = (35, 50, 57, 60, 64, 65)
GSUS = (43, 50, 55, 60, 62, 69)

# Each phrase opens with D-F-A-E or its answer B-A-G. The long rests give the
# next phrase and the game's foreground chimes a place to land.
# Triples are beat in the measure, MIDI note, and hold time in seconds.
TITLE_MOTIF = (
    ((.50, 62, 1.10), (1.14, 65, 1.17), (2.02, 69, 1.64), (3.15, 64, 1.28)),
    ((.55, 71, 1.31), (1.83, 69, 1.16), (2.74, 67, 1.76)),
    ((1.45, 65, 2.05), (2.85, 64, 1.48)),
    ((1.69, 62, 1.98),),
    ((1.24, 62, 1.36), (2.09, 65, 1.25), (3.18, 69, 1.42)),
    ((.36, 64, 1.15), (2.53, 71, 1.44)),
    ((.95, 69, 1.66), (2.43, 67, 1.60)),
    (),
    ((.41, 62, 1.16), (1.07, 65, 1.18), (1.98, 69, 1.60), (3.14, 76, 1.61)),
    ((.55, 71, 1.29), (1.73, 69, 1.28), (2.80, 67, 1.70)),
    ((.62, 65, 1.22), (1.67, 69, 1.36), (2.69, 72, 1.63)),
    ((1.49, 67, 1.32), (2.65, 64, 1.51)),
    ((.79, 69, 1.56), (2.61, 72, 1.74)),
    ((.65, 71, 1.36), (2.45, 67, 1.66)),
    ((.87, 69, 1.76), (2.53, 64, 1.48)),
    ((1.18, 62, 2.03),),
)
GAME_MOTIF = (
    ((.53, 62, .82), (1.18, 65, .87), (2.01, 69, 1.20), (3.11, 64, 1.10)),
    ((.48, 71, .83), (1.94, 69, .88), (2.88, 67, 1.34)),
    ((.76, 65, 1.28), (2.28, 60, 1.11)),
    ((2.49, 62, 1.39),),
    ((.57, 64, .98), (1.69, 69, 1.07), (2.72, 72, 1.35)),
    ((.64, 71, .87), (2.06, 69, 1.03), (3.06, 64, 1.28)),
    ((.51, 67, 1.22), (2.37, 69, 1.30)),
    (),
    ((.56, 62, .84), (1.21, 65, .88), (2.08, 69, 1.22), (3.15, 64, 1.07)),
    ((.58, 71, .93), (1.85, 69, 1.00), (2.94, 67, 1.25)),
    ((.68, 64, 1.13), (2.20, 67, 1.18)),
    ((2.55, 65, 1.25),),
    ((.70, 60, .97), (1.86, 64, 1.16), (2.85, 69, 1.36)),
    ((.51, 71, 1.12), (2.12, 69, 1.09)),
    ((1.18, 67, 1.25), (2.72, 64, 1.30)),
    (),
    ((.51, 62, .82), (1.14, 65, .87), (2.02, 69, 1.21), (3.15, 76, 1.11)),
    ((.56, 71, .83), (1.91, 69, .88), (2.83, 67, 1.22)),
    ((.64, 65, .94), (1.98, 69, 1.00), (2.90, 72, 1.19)),
    ((1.59, 67, 1.36),),
    ((.65, 64, .96), (1.79, 69, 1.15), (2.73, 72, 1.30)),
    ((.54, 71, 1.04), (1.95, 69, 1.18), (3.26, 67, 1.16)),
    ((.79, 64, 1.10), (2.28, 67, 1.16)),
    ((1.49, 62, 1.47),),
)


def music_finish(bus: np.ndarray, is_title: bool) -> np.ndarray:
    """Damp a repeating bed and start at a quiet shared stereo phase."""
    hz = np.fft.rfftfreq(len(bus), 1 / RATE)
    shelf = hz ** 2 / (hz ** 2 + 1250 ** 2)
    pressure = .76 + .24 * hz ** 2 / (hz ** 2 + 138 ** 2)
    contour = (pressure * (1 - (.31 if is_title else .36) * shelf)).astype(np.float32)
    for channel in (0, 1):
        partials = np.fft.rfft(bus[:, channel])
        partials *= contour
        partials[0] = 0
        bus[:, channel] = np.fft.irfft(partials, len(bus))

    # Keep the deep bed centered on speakers. The offset glass and wet field remain stereo.
    side = (bus[:, 0] - bus[:, 1]) * .075
    bus[:, 0] -= side
    bus[:, 1] += side
    bus = master(bus, peak_db=-4.8, rms_db=-19.6 if is_title else -20.15)

    # Rotating already-periodic samples preserves the seam. Find a nearby phase
    # that starts gently as the scene changes from silence, with little channel offset.
    entry = bus[:frames(.18)]
    excursion = np.max(np.abs(entry[1:-1]), axis=1)
    slope = np.max(np.abs(entry[2:] - entry[:-2]), axis=1)
    cut = int(np.argmin(excursion + .72 * slope)) + 1
    return np.roll(bus, -cut, axis=0)


def music(is_title: bool) -> np.ndarray:
    bpm = 72 if is_title else 80
    beat = 60 / bpm
    bar = 4 * beat
    if is_title:
        chords = (DM9, G6, FMAJ, CM9, DB, G6, CM9, ESUS,
                  DM9, G6, FMAJ, CM9, AM7, ESUS, GSUS, DM9)
    else:
        chords = (DM9, G6, FMAJ, CM9, AM7, ESUS, GSUS, DM9,
                  DB, G6, CM9, FMAJ, AM7, ESUS, G6, CM9,
                  DM9, G6, FMAJ, CM9, AM7, ESUS, GSUS, DM9)
    length = len(chords) * bar
    out = current(length)
    rng = np.random.default_rng(4030 if is_title else 4068)
    chord_pans = (0.0, -0.42, 0.43, -0.62, 0.55, -0.20)
    chord_gains = (0.112, 0.052, 0.061, 0.041, 0.040, 0.028)
    for i, chord in enumerate(chords):
        start = i * bar
        section = i // 8
        cadence = i % 4 == 3
        shade = 0.84 if cadence else 1.0
        if not is_title and section == 1:
            shade *= 0.90
        for layer, note in enumerate(chord):
            offset = rng.uniform(0.0, .06) if layer else 0
            air = (0.39 if is_title else 0.32) + 0.12 * section
            if layer == 0:
                dur, attack, release = bar * 1.20, 0.98, 1.12
            else:
                dur, attack, release = bar * 1.51, 0.76 + 0.13 * layer, 1.35
            signal = pad(note, dur, attack, release, air, rng.uniform(0, TAU))
            add(out, signal, start + offset, chord_gains[layer] * shade, chord_pans[layer], True)
            if layer in (3, 5):
                halo = pad(note + 7.0 / 100, dur, attack + .17, release, air, rng.uniform(0, TAU))
                add(out, halo, start + offset + .04, chord_gains[layer] * .34 * shade, -chord_pans[layer], True)

        if is_title:
            for j, (pos, note, duration) in enumerate(TITLE_MOTIF[i]):
                side = (-.19, .13, .25, -.09)[j]
                add(out, glass_lead(note, duration, .58 + .12 * section), start + pos * beat,
                    (.132, .117, .147, .117)[j], side, True)
                if i in (1, 5, 9, 13) and j == 1:
                    add(out, bell(note + 12, 1.6, .36), start + pos * beat + .29,
                        .029, -side, True)
            if i in (2, 5, 8, 11, 15):
                add(out, wash(1.83, 119, 378, rng), start + 2.1 * beat, .043, .34, True)
        else:
            motif_gain = (.111, .090, .127)[section]
            for j, (pos, note, duration) in enumerate(GAME_MOTIF[i]):
                drift = rng.uniform(-.009, .012)
                add(out, glass_lead(note, duration, .56 + .075 * section),
                    start + pos * beat + drift, motif_gain * (1.0, .88, 1.11, .92)[j],
                    (-.25, .16, .37, -.13)[j], True)
            # A muted 3+3+2 pulse drops away at each fourth bar.
            pulses = ((0.0, 0), (1.5, 1)) if cadence else ((0.0, 0), (1.5, 1), (3.0, 2))
            for pos, j in pulses:
                low = frequency(chord[0]) * (2 if j == 1 else 1)
                add(out, impact(.30, low * 1.38, low, rng),
                    start + pos * beat, (.061, .041, .053)[j] * shade, -.05, True)
            if i in (1, 5, 9, 13, 17, 21):
                for j, pos in enumerate((1.0, 2.62)):
                    note = chord[j + 3]
                    add(out, bell(note + 12, .45, .35), start + pos * beat,
                        (.029, .036)[j], (.58, -.50)[j], True)
            if i in (3, 7, 11, 15, 19, 23):
                add(out, wash(.91, 169, 487, rng), start + 3.15 * beat, .033, -.28, True)

        if i % 3 != 1:
            at = start + (.75 + (.41 * i) % 2.7) * beat
            add(out, bubble(.22, rng.uniform(450, 760), rng.uniform(950, 1520), rng),
                at, .025 if is_title else .020, rng.uniform(-.78, .78), True)

    space(out, .70 if is_title else .46, wrap=True)
    return music_finish(out, is_title)


def master(audio: np.ndarray, peak_db: float, rms_db: float | None = None) -> np.ndarray:
    peak = float(np.max(np.abs(audio)))
    if rms_db is None:
        return audio * (sound_db(peak_db) / max(peak, 1e-9))
    rms = float(np.sqrt(np.mean(audio ** 2)))
    audio = audio * (sound_db(rms_db) / max(rms, 1e-9))
    ceiling = sound_db(peak_db)
    # Shape high transients only. Retain body between them.
    threshold = ceiling * .61
    magnitude = np.abs(audio)
    excess = np.maximum(magnitude - threshold, 0)
    shaped = threshold + (ceiling - threshold) * np.tanh(excess / (ceiling - threshold))
    return np.where(magnitude > threshold, np.copysign(shaped, audio), audio)


FAMILIES = {
    "Button_Click": (4, -12.5),
    "Button_Hover A": (3, -19.5),
    "Button_Hover B": (3, -18.5),
    "Fish_Land": (5, -13.3),
    "Fish_Loot": (5, -7.0),
    "Fish_Spawn Layer A": (3, -14.0),
    "Jump_Land": (9, -9.0),
    "Jump_Launch": (9, -14.5),
    "Portal_Loot ST": (1, -4.1),
    "Upgrade_Loot ST": (1, -6.5),
}


def effect(name: str, take: int) -> np.ndarray:
    rng = np.random.default_rng(4187 + list(FAMILIES).index(name) * 31 + take)
    drift = rng.uniform(.91, 1.12)
    peak = FAMILIES[name][1] + rng.uniform(-.52, .38)
    if name == "Button_Click":
        out = np.zeros(frames(.105 * drift))
        add(out, impact(.052, 1010 * drift, 542 * drift, rng), 0, .71)
        add(out, bubble(.075, 1082 * drift, 1516 * drift, rng), .009, .52)
    elif name == "Button_Hover A":
        out = bubble(.064 * drift, 720 * drift, 1060 * drift, rng)
    elif name == "Button_Hover B":
        out = bubble(.084 * drift, 1090 * drift, 806 * drift, rng)
    elif name == "Fish_Land":
        out = np.zeros(frames(.275 * drift))
        add(out, bubble(.184 * drift, 228 * drift, 383 * drift, rng), 0, .74)
        add(out, bubble(.111 * drift, 603 * drift, 448 * drift, rng), .043, .28)
        add(out, bubble(.078 * drift, 894 * drift, 1192 * drift, rng), .117, .11)
    elif name == "Fish_Loot":
        out = np.zeros(frames(.52))
        first, last = ((74, 81), (76, 83), (72, 79), (77, 84), (74, 86))[take - 1]
        add(out, bubble(.138, 578 * drift, 870 * drift, rng), 0, .18)
        add(out, bell(first, .325, .86), .006, .75)
        add(out, bell(last, .403, .71), .075, .75)
        add(out, bell(last + 12, .268, .44), .103, .175)
    elif name == "Fish_Spawn Layer A":
        out = np.zeros(frames(.274 * drift))
        for j, pitch in enumerate((285, 436, 608)):
            add(out, bubble(.115 * drift, pitch * drift, 1.49 * pitch * drift, rng),
                j * .048 * drift, (.48, .71, .41)[j])
    elif name == "Jump_Land":
        out = np.zeros(frames(.195 * drift))
        add(out, impact(.135 * drift, 245 * drift, 120 * drift, rng), 0, .72)
        add(out, bubble(.103 * drift, 766 * drift, 593 * drift, rng), .016, .61)
        add(out, bubble(.093 * drift, 182 * drift, 337 * drift, rng), .033, .30)
        add(out, bubble(.065 * drift, 497 * drift, 316 * drift, rng), .073 * drift, .16)
    elif name == "Jump_Launch":
        out = np.zeros(frames(.151 * drift))
        add(out, wash(.126 * drift, 138 * drift, 802 * drift, rng), 0, .73)
        add(out, bubble(.087 * drift, 329 * drift, 682 * drift, rng), .018, .42)
    elif name == "Portal_Loot ST":
        out = np.zeros(frames(.96))
        add(out, wash(.49, 89, 438, rng), 0, .41)
        add(out, impact(.32, 131, 53, rng), 0, .43)
        strikes = ((0, 207), (.13, 242), (.25, 277), (.35, 329),
                   (.43, 367), (.50, 400), (.56, 440))
        for i, (at, pitch) in enumerate(strikes):
            add(out, impact(.100, pitch * 1.38, pitch, rng), at, .38 + .021 * i)
            add(out, bubble(.115, 686 + 48 * i, 517 + 47 * i, rng), at + .012, .35 + .017 * i)
        # A pair of glass strokes appears during the spin, before the release chime.
        add(out, bell(74, .30, .52), .117, .70)
        add(out, bell(81, .27, .55), .219, .66)
        for j, note in enumerate((62, 69, 76, 81)):
            add(out, bell(note, .36 - .014 * j, .77), .55 + .028 * j, (.58, .51, .48, .41)[j])
    else:  # Upgrade pickup. Triple chime, without the turning-wheel rhythm.
        out = np.zeros(frames(.72))
        add(out, wash(.26, 278, 1142, rng), .015, .31)
        for j, (at, note) in enumerate(((.02, 72), (.084, 77), (.198, 81))):
            add(out, bell(note, .48, .64 + .055 * j), at, (.61, .73, .66)[j])
        add(out, glass_lead(65, .423, .49), .18, .24)
    t = seconds(len(out) / RATE)
    out *= envelope(t, .0018, .021)
    return master(out, peak)


def opening(cue: str) -> np.ndarray:
    durations = {"A": 5.8, "B": 5.8, "D": 5.6}
    duration = durations[cue]
    rng = np.random.default_rng(4120 + ord(cue))
    out = current(duration) * 1.7
    add(out, pad(38, duration, .65, 1.1, .26, .6), 0, .083, -.04)

    if cue == "A":
        # Flame flickers, lamps rise, then gather and flare into the title.
        for j, at in enumerate((.20, .48, .76)):
            add(out, bubble(.14, 717 + j * 131, 1430 + 212 * j, rng),
                at, .074 + .017 * j, -.36 + .31 * j)
        for j, note in enumerate((50, 57, 60, 62, 64, 65, 69, 72, 74, 76, 81, 84)):
            at = .75 + j * .112
            side = (-1) ** j * (.55 - .025 * j)
            add(out, bubble(.17, 210 + j * 29, 457 + j * 61, rng), at, .086, side)
            add(out, bell(note, 1.35, .64), at + .023, .092 + j * .007, side)
        add(out, bell(74, 2.67, .75), 1.04, .38)
        add(out, wash(.59, 210, 1680, rng), 2.03, .32)
        add(out, impact(.65, 132, 46, rng), 2.56, .31)
        for j, note in enumerate((62, 69, 76, 81, 86)):
            add(out, bell(note, 1.9, .86), 2.60 + .019 * j, .25, -.64 + .32 * j)
        add(out, pad(74, 2.45, .27, .96, .47, 1.43), 2.95, .18, 0)
    elif cue == "B":
        # A drop spreads in dark ink. A sharp seal impact breaks its stillness.
        add(out, bubble(.22, 1440, 755, rng), .15, .29, .20)
        add(out, impact(.34, 420, 126, rng), .25, .26, -.21)
        add(out, wash(.90, 268, 93, rng), .25, .26, -.37)
        add(out, pad(46, 2.45, .42, .61, .40, 2.9), .31, .27, -.28)
        add(out, pad(57, 2.60, .62, .56, .73, .4), .66, .15, .34)
        add(out, bell(65, 2.45, .50), .95, .26, .18)
        add(out, wash(.20, 1132, 285, rng), 1.94, .23, .38)
        add(out, impact(1.08, 174, 46, rng), 2.12, .72, .15)
        add(out, impact(.33, 713, 278, rng), 2.12, .26, -.20)
        add(out, pad(38, 2.83, .087, 1.12, .38, 5.1), 2.12, .39)
        for j, note in enumerate((84, 79, 74, 69, 65)):
            add(out, bell(note, 1.22, .57), 2.55 + .082 * j, .15, .58 - .26 * j)
        add(out, wash(.73, 570, 135, rng), 2.54, .30, -.28)
        for j, note in enumerate((62, 69, 76)):
            add(out, bell(note, 2.0, .66), 3.28 + .026 * j, .23, -.28 + j * .28)
    else:
        # Five stones rise, five landings light them, and the raised lamp blooms.
        for j, note in enumerate((62, 64, 65, 69, 71)):
            pan = -.62 + .31 * j
            add(out, bubble(.27, 133 + j * 24, 346 + j * 26, rng),
                .25 + .09 * j, .25, pan)
            add(out, wash(.133, 173 + j * 24, 545 + j * 38, rng),
                .95 + .30 * j, .14, pan - .05)
            land = 1.25 + .30 * j
            add(out, impact(.20, 310 + 19 * j, 127 + 16 * j, rng), land, .24, pan)
            add(out, bell(note, 1.47, .72), land + .014, .31 + .016 * j, pan)
        add(out, wash(.26, 241, 1279, rng), 2.51, .40, .34)
        add(out, pad(69, 2.64, .27, .86, .78, 3.9), 2.55, .27, .25)
        for j, note in enumerate((62, 69, 74, 81)):
            add(out, bell(note, 1.9, .73), 2.70 + .035 * j, .25, -.46 + .30 * j)
        add(out, impact(.53, 123, 61, rng), 3.05, .30)
        for j in range(8):
            add(out, bubble(.135, 1160 + 120 * j, 2400 + 70 * j, rng),
                3.05 + .078 * j, .09 - .006 * j, rng.uniform(-.68, .68))

    space(out, .54, wrap=False)
    out *= envelope(seconds(duration), .045, .98)[:, None]
    window = RATE // 4
    power = max(float(np.sqrt(np.mean(out[i:i + window] ** 2)))
                for i in range(0, len(out) - window, window // 2))
    out *= sound_db(-14.5) / max(power, 1e-9)
    peak = float(np.max(np.abs(out)))
    if peak > sound_db(-3.5):
        out *= sound_db(-3.5) / peak
    return out


def write_wav(path: Path, data: np.ndarray) -> None:
    if not np.isfinite(data).all() or np.max(np.abs(data)) >= 1.0:
        raise ValueError(f"Invalid audio samples: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.rint(data * 32767).astype("<i2")
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1 if data.ndim == 1 else data.shape[1])
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(pcm.tobytes())


def preview(title: np.ndarray, game: np.ndarray) -> np.ndarray:
    out = np.zeros((frames(25), 2), dtype=np.float32)
    cutoff = frames(5)
    out[:cutoff] = title[:cutoff]
    out[cutoff:] = game[:len(out) - cutoff]
    overlap = frames(.19)
    fade = smooth(np.linspace(0, 1, 2 * overlap))[:, None]
    section = slice(cutoff - overlap, cutoff + overlap)
    recent = title[section]
    pre_roll = np.concatenate((game[-overlap:], game[:overlap]))
    blend = fade * np.pi / 2
    out[section] = recent * np.cos(blend) + pre_roll * np.sin(blend)
    for name, take, when, gain in (
        ("Jump_Land", 3, 9.0, 1.10),
        ("Fish_Loot", 2, 12.0, 1.00),
        ("Button_Click", 1, 15.0, 1.06),
        ("Portal_Loot ST", 1, 19.0, .98),
    ):
        add(out, effect(name, take), when, gain)
    out *= envelope(seconds(25), .08, 1.47)[:, None]
    return master(out, -2.5, -18.6)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "assets" / "audio")
    parser.add_argument("--preview", type=Path, default=HERE / "preview.wav")
    args = parser.parse_args()

    title = music(True)
    game = music(False)
    write_wav(args.output / TITLE, title)
    write_wav(args.output / GAME, game)
    for cue in "ABD":
        write_wav(args.output / "opening" / f"open{cue}.wav", opening(cue))
    for name, (takes, _) in FAMILIES.items():
        for take in range(1, takes + 1):
            stem = f"{name}_{take:03d}" if takes > 1 else name
            write_wav(args.output / "sfx" / f"{stem}.wav", effect(name, take))
    write_wav(args.preview, preview(title, game))
    print(f"Rendered 48 clips to {args.output} and audition to {args.preview}")


if __name__ == "__main__":
    main()

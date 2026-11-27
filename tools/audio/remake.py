"""Render the ordered score and cues from CC0 instrument and foley recordings."""

import argparse
from functools import lru_cache
from pathlib import Path
import wave

import numpy as np

import recorded_samples as rec


RATE = 48_000
ORIGIN = Path(__file__).resolve().parent
TITLE = "GameOff_Mus_02 MainTitle 143bpm Loop.wav"
GAME = "GameOff_Mus_01 Loop.wav"
TAU = 2 * np.pi


def frames(seconds):
    return round(seconds * RATE)


def time(duration):
    return np.arange(frames(duration)) / RATE


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def edge(t, attack, release):
    """Raised-cosine onset and release for a one-shot."""
    remaining = (len(t) - np.arange(len(t)) - 1) / RATE
    up = np.clip(t / attack, 0, 1)
    down = np.clip(remaining / release, 0, 1)
    return np.sin(np.pi * up / 2) ** 2 * np.sin(np.pi * down / 2) ** 2


def band_noise(t, rng, low, high):
    family = "ocean" if len(t) > frames(1) else "shaker"
    return rec.texture(len(t) / RATE, low, high, rng.integers(3), family) * 1.8


def swipe(duration, rng, low, high, rise=0.6):
    t = time(duration)
    motion = np.clip(t / (duration * 0.83), 0, 1)
    dry = band_noise(t, rng, low, 2 * low) * (1 - motion)
    wet = band_noise(t, rng, 0.56 * high, high) * motion
    return (dry + wet) * edge(t, duration * rise, duration * 0.25)


def strike(pitch, duration, decay=0.095, sharpness=0.5):
    family = "bassdrum" if pitch < 120 else "frame" if pitch < 320 else "block"
    return rec.sound(family, duration, take=round(pitch / 53),
                     speed=np.clip(pitch / (140 if pitch < 320 else 810), 0.69, 1.50),
                     cutoff=3500 + 2500 * sharpness)


@lru_cache(maxsize=256)
def felt(note, duration, bright=False):
    if bright:
        return rec.sound("guqin", duration, note=note, cutoff=5900, release=min(.12, duration * .3))
    piano = rec.sound("piano", duration, note=note, cutoff=3000, release=min(.14, duration * .32))
    qin = rec.sound("guqin", duration, note=note, cutoff=3400, release=min(.14, duration * .32))
    return .36 * piano + .64 * qin


@lru_cache(maxsize=96)
def bass(note, duration):
    return rec.sound("harp", duration, note=note, cutoff=1600, release=0.095)


@lru_cache(maxsize=96)
def glow(note, duration):
    return rec.sound("dizi", duration, note=note, cutoff=1980, attack=.10,
                     release=min(.23, duration * .33))


def clip_end(signal, duration=0.012):
    result = signal.copy()
    n = min(len(signal), frames(duration))
    fade = np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    result[-n:] *= fade[:, None] if signal.ndim == 2 else fade
    return result


class Score:
    def __init__(self, duration, loop=False):
        self.dry = np.zeros((frames(duration), 2), dtype=np.float32)
        self.loop = loop

    def add(self, at, signal, gain, pan=0.0):
        start = frames(at)
        size = len(self.dry)
        if self.loop:
            start %= size
        if start < 0 or start >= size:
            raise ValueError(f"Event outside mix: {at:.3f}s")
        n = min(len(signal), size - start)
        angle = (pan + 1) * np.pi / 4
        side = gain * np.array([np.cos(angle), np.sin(angle)])
        self.dry[start:start + n] += signal[:n, None] * side
        if self.loop and n < len(signal):
            self.dry[:len(signal) - n] += signal[n:, None] * side

    def render(self, depth):
        output = self.dry.copy()
        taps = ((0.039, 0.39), (0.071, 0.27), (0.111, 0.20), (0.167, 0.12), (0.243, 0.08), (0.374, 0.04))
        for i, (delay, weight) in enumerate(taps):
            channel = self.dry[:, ::-1] if i % 2 == 0 else self.dry
            shift = frames(delay)
            weight *= depth
            output[shift:] += weight * channel[:-shift]
            if self.loop:
                output[:shift] += weight * channel[-shift:]
        return output


def peak(signal, db):
    return signal * (10 ** (db / 20) / max(np.max(np.abs(signal)), 1e-8))


def programme_level(signal, rms_db, peak_db):
    target = 10 ** (rms_db / 20)
    adjusted = signal * (target / max(np.sqrt(np.mean(signal ** 2)), 1e-8))
    maximum = 10 ** (peak_db / 20)
    if np.max(np.abs(adjusted)) > maximum:
        adjusted = peak(adjusted, peak_db)
    return adjusted


# E major against suspended and sixth chords. Each voicing is root, then key notes.
TITLE_CHORDS = (
    (40, (56, 59, 66)), (47, (54, 57, 63)), (49, (56, 59, 64)), (45, (52, 59, 61)),
    (40, (56, 59, 66)), (42, (54, 57, 61)), (45, (52, 59, 66)), (47, (54, 57, 64)),
    (44, (56, 59, 64)), (45, (54, 59, 61)), (49, (56, 59, 64)), (47, (54, 59, 63)),
    (40, (56, 59, 66)), (45, (52, 56, 61)), (42, (54, 57, 61)), (47, (54, 57, 64)),
)
TITLE_MELODY = (
    ((0, 68), (0.75, 71), (1.5, 73), (2.75, 71)),
    ((0.5, 66), (1.5, 63), (2.5, 66)),
    ((0, 68), (0.75, 71), (1.5, 76), (2.75, 73)),
    ((0.5, 69), (1.5, 68), (2.25, 64)),
    ((0, 68), (0.75, 71), (1.5, 78), (2.6, 76)),
    ((0.5, 73), (1.5, 69), (2.5, 66), (3.25, 68)),
    ((0, 69), (0.75, 76), (1.5, 73), (2.5, 71), (3.5, 69)),
    ((0.5, 71), (1.5, 66), (2.5, 63), (3.25, 66)),
    ((0, 64), (1.5, 68), (2.5, 71)),
    ((0.5, 73), (1.5, 69), (2.5, 66), (3.5, 64)),
    ((0, 68), (1.0, 71), (2.0, 73), (3.0, 76)),
    ((0.5, 78), (1.5, 76), (2.5, 71), (3.25, 69)),
    ((0, 71), (0.75, 73), (1.5, 76), (2.5, 78)),
    ((0.5, 76), (1.5, 73), (2.5, 69), (3.5, 68)),
    ((0, 66), (0.75, 69), (1.5, 73), (2.75, 68)),
    ((0.5, 69), (1.5, 66), (2.5, 63), (3.5, 66)),
)
TITLE_RETURN_CHORDS = (
    (49, (52, 56, 59)), (44, (51, 56, 59)), (45, (52, 57, 61)), (40, (54, 59, 64)),
    (42, (52, 57, 61)), (49, (52, 56, 64)), (45, (52, 59, 66)), (47, (54, 57, 63)),
    (40, (56, 59, 66)), (44, (52, 59, 68)), (45, (54, 61, 64)), (47, (54, 57, 63)),
    (49, (52, 59, 64)), (45, (56, 59, 61)), (42, (54, 57, 61)), (47, (54, 57, 64)),
)
TITLE_RETURN_MELODY = (
    ((0.0, 56), (1.5, 59), (2.75, 61)),
    ((0.75, 63), (2.25, 59)),
    ((0.0, 57), (1.5, 61), (2.75, 64)),
    ((0.75, 66), (2.25, 64)),
    ((0.0, 61), (1.0, 64), (2.5, 66)),
    ((0.75, 68), (2.25, 64)),
    ((0.0, 61), (1.5, 64), (2.75, 66)),
    ((0.75, 69), (2.25, 66)),
    ((0.0, 68), (0.75, 71), (1.5, 73), (2.75, 71)),
    ((0.5, 76), (1.5, 71), (2.5, 68)),
    ((0.0, 69), (0.75, 73), (1.5, 76), (2.75, 73)),
    ((0.5, 71), (1.5, 69), (2.5, 66)),
    ((0.0, 68), (1.0, 71), (2.0, 73), (3.0, 76)),
    ((0.5, 78), (1.5, 76), (2.5, 73)),
    ((0.0, 69), (0.75, 73), (1.5, 71), (2.75, 66)),
    ((0.5, 69), (1.5, 66), (2.5, 63)),
)


def title_music():
    beat = 60 / 132
    mix = Score(128 * beat, loop=True)
    for bar in range(32):
        passage = bar // 8
        bridge = passage == 2
        turnaround = bar == 31
        chord_table = TITLE_CHORDS if passage < 2 else TITLE_RETURN_CHORDS
        melody_table = TITLE_MELODY if passage < 2 else TITLE_RETURN_MELODY
        root, chord = chord_table[bar % 16]
        start = 4 * beat * bar
        for step, note, level in ((0, root, 0.26), (1.5, root + 12, 0.16), (2.5, root + 7, 0.21), (3.5, root, 0.10)):
            if turnaround and step >= 2.5:
                continue
            if not bridge or step in (0, 2.5):
                mix.add(start + step * beat, bass(note, 0.58), level)
        for step, level in ((0.5, 0.054), (1.5, 0.076), (2.75, 0.068), (3.5, 0.054)):
            if (bridge and step in (0.5, 3.5)) or (turnaround and step >= 2.75):
                continue
            for index, note in enumerate(chord):
                mix.add(start + (step + 0.032 * index) * beat, felt(note, 0.56), level, (-0.30, 0.04, 0.29)[index])
        rhythm = ((0.0, 109, 0.071), (1.0, 725, 0.054), (2.5, 124, 0.061), (3.0, 816, 0.058))
        for index, (step, pitch, gain) in enumerate(rhythm):
            if (bridge and index in (1, 2)) or (turnaround and index >= 2):
                continue
            mix.add(start + (step + 0.03) * beat, strike(pitch, 0.19, 0.053, 0.28), gain, (-0.08, -0.24, 0.12, 0.32)[index])
        for index, (step, note) in enumerate(melody_table[bar % 16]):
            beat_accent = 0.185 if index == 0 else 0.146
            mix.add(start + step * beat, felt(note, 0.84 if bridge else 0.68, bright=not bridge), beat_accent, 0.13)
            if passage == 3 and index in (1, 3) and not turnaround:
                mix.add(start + (step + 0.24) * beat, felt(note - 12, 0.66), 0.056, -0.28)
        if passage in (1, 2):
            mix.add(start + 0.7 * beat, glow(chord[1] + 12, 1.78), 0.028, -0.40)
        if turnaround:
            # Carry the shared B into E, with the key release wrapped into bar one.
            mix.add(start + 3.18 * beat, glow(59, 1.16), 0.072, -0.18)
    return programme_level(mix.render(0.25), -20, -3.5)


# A gentler range and more breathing room on the board. The E resolves back to A.
GAME_CHORDS = (
    (45, (57, 61, 64, 71)), (40, (56, 59, 64, 66)), (42, (54, 57, 61, 64)), (38, (54, 57, 61, 64)),
    (45, (56, 61, 64, 69)), (47, (54, 57, 62, 66)), (38, (54, 57, 61, 69)), (40, (56, 59, 62, 66)),
    (42, (57, 61, 64, 69)), (37, (56, 59, 64, 68)), (38, (54, 57, 61, 64)), (45, (56, 59, 61, 64)),
    (47, (54, 57, 62, 66)), (42, (54, 57, 61, 69)), (38, (54, 57, 61, 66)), (40, (56, 59, 62, 66)),
)
GAME_MELODY = (
    ((0.0, 69), (1.5, 71), (2.75, 76)),
    ((0.5, 73), (2.0, 71)),
    ((0.0, 69), (1.5, 66), (3.0, 68)),
    ((0.5, 69), (2.25, 64)),
    ((0.0, 66), (1.25, 68), (2.0, 69)),
    ((0.75, 73), (2.5, 71)),
    ((0.0, 69), (1.5, 66), (3.0, 64)),
    ((0.5, 68), (2.5, 71)),
    ((0.0, 76), (1.5, 73)),
    ((0.5, 71), (2.5, 68)),
    ((0.0, 69), (2.25, 66), (3.25, 64)),
    ((0.5, 61), (2.0, 64)),
    ((0.0, 66), (1.25, 69), (2.5, 71)),
    ((0.5, 73), (1.75, 76), (3.0, 73)),
    ((0.0, 69), (1.5, 66), (2.75, 64)),
    ((0.5, 68), (2.5, 71)),
)
GAME_ANSWER_CHORDS = (
    (42, (54, 57, 61, 69)), (38, (54, 57, 61, 64)), (45, (56, 59, 61, 64)), (40, (56, 59, 62, 66)),
    (38, (54, 57, 61, 69)), (47, (54, 57, 62, 66)), (42, (52, 57, 61, 64)), (40, (56, 59, 62, 66)),
    (45, (57, 61, 64, 71)), (37, (56, 59, 64, 68)), (38, (54, 57, 61, 64)), (49, (52, 56, 59, 64)),
    (47, (54, 57, 62, 66)), (42, (54, 57, 61, 69)), (38, (54, 57, 61, 66)), (40, (56, 59, 62, 66)),
)
GAME_ANSWER_MELODY = (
    ((0.75, 61), (2.25, 64)), ((1.0, 66),), ((0.0, 64), (1.5, 61)), ((0.75, 59), (2.5, 56)),
    ((0.5, 57), (2.25, 61)), ((0.75, 62),), ((0.0, 64), (1.5, 66)), ((1.0, 64), (2.5, 59)),
    ((0.0, 69), (1.5, 71), (2.75, 76)), ((0.75, 73), (2.5, 68)), ((0.0, 66), (2.25, 64)), ((1.0, 68), (2.25, 64)),
    ((0.5, 66), (1.75, 69)), ((0.75, 73), (2.0, 69)), ((0.0, 66), (1.5, 64)), ((0.5, 59), (2.5, 68)),
)


def game_music():
    beat = 60 / 98
    mix = Score(128 * beat, loop=True)
    for bar in range(32):
        chord_table = GAME_CHORDS if bar < 16 else GAME_ANSWER_CHORDS
        melody_table = GAME_MELODY if bar < 16 else GAME_ANSWER_MELODY
        root, chord = chord_table[bar % 16]
        start = 4 * beat * bar
        turnaround = bar == 31
        for step, note, gain in ((0, root, 0.16), (2.0, root + 7, 0.086), (3.2, root + 12, 0.058)):
            if turnaround and step > 2:
                continue
            mix.add(start + step * beat, bass(note, 0.78), gain, -0.04)
        for index, (step, voice) in enumerate(((0.25, 0), (0.8, 1), (1.55, 2), (2.4, 1), (3.13, 3))):
            if (8 <= bar < 24 and index in (1, 3)) or (turnaround and step > 2):
                continue
            mix.add(start + step * beat, felt(chord[voice], 1.05), 0.074, (-0.24, 0.30, -0.19, 0.24, 0.11)[index])
        for index, (step, note) in enumerate(melody_table[bar % 16]):
            melody_note = note - 12 if 8 <= bar < 16 and index == 1 else note
            phrase = 0.83 if 16 <= bar < 24 else 1.0
            mix.add(start + step * beat, felt(rec.pentatonic(melody_note, 9), 1.25),
                    phrase * (0.136, 0.113, 0.096)[index], 0.12)
            if 16 <= bar < 24 and index == 0:
                mix.add(start + (step + 0.08) * beat, glow(note, 1.38), 0.028, -0.26)
        if bar % 2 == 0 or 24 <= bar < 31:
            mix.add(start + 1.5 * beat, strike(640 + 28 * (bar % 3), 0.14, 0.04, 0.22), 0.038, -0.26)
            mix.add(start + 3.0 * beat, strike(495, 0.14, 0.047, 0.17), 0.027, 0.20)
        mix.add(start, glow(chord[0], 2.80), 0.021, -0.48)
        mix.add(start + 0.16 * beat, glow(chord[2], 2.80), 0.018, 0.48)
        if turnaround:
            mix.add(start + 3.22 * beat, glow(64, 1.44), 0.063, 0.23)
    return programme_level(mix.render(0.34), -22.5, -4.5)


def one_shot(duration, events):
    output = np.zeros(frames(duration))
    for at, signal, gain in events:
        start = frames(at)
        count = min(len(signal), len(output) - start)
        output[start:start + count] += gain * signal[:count]
    return clip_end(output)


def crisp(duration, rng, low, high, tau):
    t = time(duration)
    return band_noise(t, rng, low, high) * np.exp(-t / tau) * edge(t, 0.003, 0.019)


def bubble(duration, low, high):
    return rec.sound("water", duration, take=round(low / 245), speed=np.clip(high / 720, 0.58, 1.62),
                     cutoff=3000)


def ui_sound(family, number, rng):
    pitch = (762, 804, 874, 926)[number]
    if family == "click":
        opens = ((0.00, strike(pitch, 0.081, 0.018, 0.20), 0.86),
                 (0.006, crisp(0.052, rng, 1250, 3350, 0.009), 0.15))
        return peak(one_shot(0.094 + 0.006 * number, opens), -12.2 + 0.18 * number)
    target = pitch + 118 if family == "focus" else pitch * 0.65
    sounds = ((0.0, strike(target, 0.072, 0.013, 0.11), 0.78),
              (0.009, bubble(0.058, target * 1.05, target * 1.17), 0.23))
    return peak(one_shot(0.081 + 0.004 * number, sounds), -20.2 + 0.22 * number)


def movement(family, number, rng):
    spread = 0.92 + 0.021 * number
    duration = 0.172 + (number % 3) * 0.011
    if family == "launch":
        sounds = ((0.0, swipe(0.100, rng, 520 * spread, 2810 * spread, rise=0.37), 0.60),
                  (0.0, bubble(0.096, 330 * spread, 610 * spread), 0.36),
                  (0.012, strike(210 * spread, 0.10, 0.021, 0.23), 0.21))
        return peak(one_shot(duration, sounds), -16.3 + (number % 3) * 0.45)
    water = family == "wet"
    sounds = ((0.0, rec.sound("water" if water else "step", 0.155, take=number, speed=spread, cutoff=4100), 0.89),
              (0.004, crisp(0.121, rng, 420 if water else 650, 2700 if water else 2070, 0.018), 0.31),
              (0.034 + 0.003 * (number % 4), bubble(0.10, 173 * spread, 440 * spread), 0.33 if water else 0.08))
    level = -12.3 if water else -11.4
    return peak(one_shot(duration, sounds), level - (number % 3) * 0.49)


def lantern(family, number, rng):
    key = (73, 76, 78, 81, 83)[number]
    if family == "spawn":
        sounds = ((0.0, bubble(0.155, 410 + number * 52, 1080 + 52 * number), 0.70),
                  (0.038, felt(key, 0.20, True), 0.31))
        return peak(one_shot(0.26 + 0.012 * number, sounds), -17.4 + 0.34 * number)
    interval = (7, 5, 7, 4, 5)[number]
    sounds = ((0.0, felt(key, 0.205, True), 0.65),
              (0.044, felt(key + interval, 0.22, True), 0.47),
              (0.005, crisp(0.093, rng, 1050, 3700, 0.017), 0.12))
    return peak(one_shot(0.27 + 0.009 * number, sounds), -11.1 - 0.28 * (number % 3))


def special_sound(wheel, rng):
    if wheel:
        notes = ((0.105, 57), (0.19, 64), (0.30, 69), (0.40, 73))
        events = [(0, strike(111, 0.34, 0.10, 0.33), 0.80),
                  (0.037, swipe(0.57, rng, 350, 1930, rise=0.24), 0.25),
                  (0.11, strike(160, 0.18, 0.041), 0.30),
                  (0.242, strike(139, 0.21, 0.041), 0.21),
                  (0.358, strike(173, 0.20, 0.057), 0.15),
                  (0.408, bubble(0.19, 240, 450), 0.17)]
    else:
        notes = ((0.0, 64), (0.065, 69), (0.14, 73), (0.225, 76))
        events = [(0.0, crisp(0.15, rng, 1150, 4200, 0.025), 0.15),
                  (0.17, bubble(0.17, 720, 1030), 0.13)]
    note_length = 0.40 if wheel else 0.34
    events.extend((at, felt(note, note_length, True), 0.53 - 0.25 * at) for at, note in notes)
    return peak(one_shot(0.83 if wheel else 0.59, events), -7.5 if wheel else -8.9)


def make_sfx():
    effects = {}
    groups = (
        ("Button_Click", 4, ui_sound, "click"),
        ("Button_Hover A", 3, ui_sound, "focus"),
        ("Button_Hover B", 3, ui_sound, "return"),
        ("Fish_Land", 5, movement, "wet"),
        ("Fish_Loot", 5, lantern, "loot"),
        ("Fish_Spawn Layer A", 3, lantern, "spawn"),
        ("Jump_Land", 9, movement, "step"),
        ("Jump_Launch", 9, movement, "launch"),
    )
    for group, (prefix, count, builder, voice) in enumerate(groups):
        for number in range(count):
            rng = np.random.default_rng(17924 + 83 * group + 11 * number)
            filename = f"{prefix}_{number + 1:03d}.wav"
            effects[filename] = builder(voice, number, rng)
    effects["Portal_Loot ST.wav"] = special_sound(True, np.random.default_rng(2602))
    effects["Upgrade_Loot ST.wav"] = special_sound(False, np.random.default_rng(2704))
    return effects


def opening(letter):
    duration = 5.6 if letter == "D" else 5.8
    mix = Score(duration)
    rng = np.random.default_rng(25100 + ord(letter))
    ambient = time(duration)
    for pan in (-0.56, 0.56):
        river = band_noise(ambient, rng, 170, 940)
        lap = 0.64 + 0.36 * np.sin(TAU * 0.75 * ambient + pan) ** 2
        mix.add(0.0, river * lap * edge(ambient, 0.41, 1.10), 0.016, pan)

    if letter == "A":
        for index, at in enumerate((0.20, 0.48, 0.76)):
            mix.add(at, crisp(0.12, rng, 1500, 5700, 0.023), 0.068 + 0.012 * index, -0.24 + 0.2 * index)
        for index, note in enumerate((52, 56, 59, 64, 66, 68, 71, 73)):
            at = 0.75 + index * 0.148
            mix.add(at, felt(note, 1.05, True), 0.20 + index * 0.013, -0.54 + index * 0.15)
            mix.add(at + 0.016, bubble(0.21, 210 + index * 22, 590 + index * 30), 0.081, -0.50 + index * 0.143)
        mix.add(1.04, glow(64, 1.28), 0.13, 0.0)
        mix.add(2.05, swipe(0.64, rng, 430, 6200), 0.17, 0.0)
        mix.add(2.60, strike(109, 0.44, 0.092), 0.39, 0.0)
        reveal = 2.95
        notes = (64, 68, 71, 76)
    elif letter == "B":
        mix.add(0.15, bubble(0.20, 790, 1260), 0.23, -0.09)
        mix.add(0.25, swipe(0.64, rng, 510, 1950, rise=0.21), 0.20, -0.25)
        mix.add(0.25, felt(52, 0.73), 0.24, -0.14)
        mix.add(0.95, glow(59, 1.24), 0.15, 0.06)
        mix.add(0.95, felt(64, 1.04), 0.26, 0.03)
        mix.add(1.95, swipe(0.19, rng, 450, 2600), 0.14, 0.26)
        mix.add(2.12, strike(91, 0.53, 0.11, 0.54), 0.67, 0.17)
        mix.add(2.12, crisp(0.20, rng, 440, 4650, 0.034), 0.25, 0.17)
        for index, note in enumerate((64, 59, 56, 52)):
            mix.add(2.55 + 0.11 * index, felt(note, 0.80), 0.25, 0.40 - 0.22 * index)
        reveal = 3.28
        notes = (56, 59, 64, 68)
    else:
        for index, note in enumerate((52, 56, 59, 61, 64)):
            pan = -0.54 + 0.27 * index
            mix.add(0.25 + index * 0.09, bubble(0.42, 105 + 18 * index, 238 + 39 * index), 0.22, pan)
            mix.add(0.95 + index * 0.30, swipe(0.17, rng, 590, 2200), 0.10, pan)
            mix.add(1.25 + index * 0.30, strike(166 + index * 29, 0.20, 0.055, 0.42), 0.23, pan)
            mix.add(1.25 + index * 0.30, felt(note, 1.08, True), 0.29, pan)
        mix.add(2.55, swipe(0.36, rng, 400, 5250), 0.15, 0.32)
        mix.add(3.05, crisp(0.31, rng, 2100, 7100, 0.047), 0.115, 0.16)
        for index, note in enumerate((76, 81, 80)):
            mix.add(3.05 + 0.087 * index, felt(note, 0.53, True), 0.12, -0.25 + 0.25 * index)
        reveal = 2.70
        notes = (64, 66, 68, 76)

    for index, note in enumerate(notes):
        mix.add(reveal + 0.056 * index, felt(note, 2.18 - index * 0.08, True), 0.30 - 0.031 * index, -0.39 + 0.26 * index)
    softened = clip_end(mix.render(0.39), 0.30)
    output = programme_level(softened, -21, -3.5)
    # Opening.gd raises the title bus at these reveal times. Use the original
    # animation cue hits and progressively reduce the overlapping release.
    title_return = {"A": 2.95, "B": 3.00, "D": 2.86}[letter]
    phase = np.clip((time(duration) - title_return - 0.28) / 1.07, 0, 1)
    output *= (1 - 0.64 * np.sin(np.pi * phase / 2) ** 2)[:, None]
    return output


def preview(title, game, effects):
    start = frames(4.78)
    end = frames(5.22)
    comparison = np.concatenate((title[:start].copy(), game[:frames(25) - start].copy()))
    angle = np.linspace(0, np.pi / 2, end - start)[:, None]
    comparison[start:end] = title[start:end] * np.cos(angle) + comparison[start:end] * np.sin(angle)
    events = ((9.0, "Jump_Land_003.wav", -0.14, 0.93),
              (12.0, "Fish_Loot_002.wav", 0.14, 0.92),
              (15.0, "Button_Click_002.wav", 0.0, 1.0),
              (19.0, "Portal_Loot ST.wav", 0.11, 0.86))
    for at, filename, pan, level in events:
        signal = effects[filename]
        angle = (pan + 1) * np.pi / 4
        comparison[frames(at):frames(at) + len(signal)] += signal[:, None] * level * np.array([np.cos(angle), np.sin(angle)])
    n = frames(0.035)
    comparison[:n] *= np.sin(np.linspace(0, np.pi / 2, n))[:, None] ** 2
    return clip_end(comparison, 0.66)


def write_wav(path, signal):
    if signal.ndim == 1:
        signal = signal[:, None]
    pcm = np.round(signal * 32767).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(pcm.shape[1])
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ORIGIN / "assets" / "audio")
    parser.add_argument("--preview", type=Path, default=ORIGIN / "preview.wav")
    args = parser.parse_args()
    title = title_music()
    game = game_music()
    write_wav(args.output / TITLE, title)
    write_wav(args.output / GAME, game)
    for letter in "ABD":
        write_wav(args.output / "opening" / f"open{letter}.wav", opening(letter))
    effects = make_sfx()
    for filename, audio in effects.items():
        write_wav(args.output / "sfx" / filename, audio)
    write_wav(args.preview, preview(title, game, effects))


if __name__ == "__main__":
    main()

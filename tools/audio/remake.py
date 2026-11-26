"""Render 灯市回响, an original Godot audio set, using Python and NumPy."""

import argparse
import importlib.util
from pathlib import Path
import wave

import numpy as np


RATE = 48000
TITLE = "GameOff_Mus_02 MainTitle 143bpm Loop.wav"
GAME = "GameOff_Mus_01 Loop.wav"
GROUPS = {
    "Button_Click": (4, "click"),
    "Button_Hover A": (3, "hover_a"),
    "Button_Hover B": (3, "hover_b"),
    "Jump_Launch": (9, "launch"),
    "Jump_Land": (9, "land"),
    "Fish_Spawn Layer A": (3, "spawn"),
    "Fish_Land": (5, "splash"),
    "Fish_Loot": (5, "lamp"),
}
SFX_LEVELS = {
    # Whole-file RMS and peak caps. A short hover should stay behind a click.
    "click": (-23.0, -10.0),
    "hover_a": (-32.0, -19.0),
    "hover_b": (-32.0, -19.0),
    "launch": (-25.0, -12.5),
    "land": (-21.5, -9.5),
    "spawn": (-27.0, -16.0),
    "splash": (-26.5, -14.0),
    "lamp": (-20.5, -8.5),
    "upgrade": (-21.5, -9.0),
    "portal": (-19.0, -7.5),
}


def load_foley(tools):
    spec = importlib.util.spec_from_file_location("instruments", tools / "instruments.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def frames(seconds):
    return round(seconds * RATE)


def time(seconds):
    return np.arange(frames(seconds)) / RATE


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def envelope(t, start, end, decay):
    return np.clip(t / start, 0, 1) * np.clip((t.size / RATE - t) / end, 0, 1) * np.exp(-t / decay)


def tone(note, duration, color):
    t = time(duration)
    phase = 2 * np.pi * hz(note) * t
    if color == "glass":
        # Uneven overtones reproduce the feel of a small struck instrument.
        modes = ((1, 1, 0.37), (2.006, 0.38, 0.17), (3.045, 0.16, 0.08), (4.18, 0.06, 0.04))
    elif color == "bass":
        modes = ((1, 1, 0.46), (2, 0.29, 0.23), (3, 0.13, 0.18), (5, 0.04, 0.08))
    else:
        modes = ((1, 1, 0.41), (2.001, 0.52, 0.23), (2.997, 0.22, 0.09), (5.008, 0.08, 0.04))
    signal = sum(loudness * np.sin(phase * ratio) * np.exp(-t / damping)
                 for ratio, loudness, damping in modes)
    return signal * envelope(t, 0.004 if color != "bass" else 0.009, 0.034, 4)


def puff(start, end, duration, decay):
    t = time(duration)
    frequency = end + (start - end) * np.exp(-t / 0.032)
    return np.sin(np.cumsum(frequency) * (2 * np.pi / RATE)) * envelope(t, 0.003, 0.02, decay)


def sand(rng, duration, decay):
    t = time(duration)
    source = rng.normal(size=len(t))
    return np.diff(source, prepend=0) * envelope(t, 0.003, 0.02, decay) * 0.20


def splash(foley, rng, size, duration):
    # Keep the source long enough for the water droplets before cutting the game cue.
    source_duration = max(duration, 0.23 + 0.4 * size)
    sound = foley.splash(size, source_duration, rng)[:frames(duration)]
    sound[-frames(0.035):] *= np.linspace(1, 0, frames(0.035))
    return sound


def add(destination, mono, second, gain=1.0, pan=0.0, loop=False):
    start = frames(second) % len(destination)
    left = np.cos((pan + 1) * np.pi / 4)
    right = np.sin((pan + 1) * np.pi / 4)
    count = min(len(mono), len(destination) - start)
    stereo = mono[:, None] * (gain * np.array([left, right]))
    destination[start:start + count] += stereo[:count]
    if loop and count < len(mono):
        destination[:len(mono) - count] += stereo[count:]


def scale(signal, rms_db, peak_db):
    rms = np.sqrt(np.mean(signal ** 2))
    gain = min(10 ** (rms_db / 20) / rms, 10 ** (peak_db / 20) / np.max(np.abs(signal)))
    return signal * gain


def write(path, signal):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.rint(np.clip(signal, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1 if pcm.ndim == 1 else pcm.shape[1])
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())


# Four-bar statements, responses and a quieter middle. Positions are in beats.
TITLE_PHRASES = [
    [(0.5, 74), (1.25, 78), (2.0, 81), (2.75, 83)],
    [(0.0, 81), (0.75, 78), (2.25, 73), (3.25, 76)],
    [(0.0, 79), (1.5, 78), (2.0, 76), (3.0, 74)],
    [(0.5, 76), (1.25, 78), (2.25, 81), (3.25, 76)],
    [(0.0, 78), (0.75, 78), (1.5, 76), (2.0, 74), (3.25, 69)],
    [(0.5, 73), (1.5, 76), (2.5, 78), (3.25, 81)],
    [(0.0, 83), (1.0, 78), (2.5, 76), (3.25, 74)],
    [(0.0, 76), (1.75, 69), (2.75, 73), (3.5, 74)],
    [(0.75, 71), (1.5, 74), (2.75, 78)],
    [(0.5, 74), (2.0, 71), (3.25, 69)],
    [(0.0, 66), (1.75, 69), (2.5, 71)],
    [(1.0, 76), (2.0, 73)],
]
GAME_PHRASES = [
    [(0.5, 62), (1.25, 66), (2.0, 69)],
    [(0.75, 71), (2.5, 67)],
    [(0.0, 62), (1.75, 64), (2.5, 66)],
    [(1.5, 69)],
    [(0.5, 66), (1.25, 71), (2.75, 74)],
    [(0.5, 71), (2.25, 66)],
    [(0.75, 67), (1.75, 69), (3.0, 66)],
    [(0.25, 64), (1.75, 61)],
    [(1.0, 62), (2.75, 67)],
    [(0.5, 66)],
    [(1.5, 64), (2.75, 66)],
    [],
]


def music(title, rng):
    beat = 60 / (132 if title else 84)
    bar_count = 28 if title else 32
    track = np.zeros((frames(beat * 4 * bar_count), 2), np.float32)
    echoes = np.zeros_like(track)
    if title:
        home = [(50, 62, 66, 69), (47, 61, 66, 69), (43, 62, 67, 71), (45, 61, 64, 69)]
        bridge = [(52, 62, 67, 71), (43, 59, 64, 67), (47, 62, 66, 69), (45, 55, 61, 64)]
        phrases = TITLE_PHRASES
        section_order = (0, 1, 0, 2, 2, 1, 0)
        phrase_gain = (0.92, 1.00, 0.86, 0.76, 0.70, 1.03, 0.88)
    else:
        home = [(47, 61, 66, 69), (43, 62, 66, 71), (50, 62, 64, 69), (45, 61, 64, 69)]
        bridge = [(52, 59, 62, 67), (47, 57, 62, 66), (43, 59, 64, 67), (45, 57, 64, 69)]
        phrases = GAME_PHRASES
        section_order = (0, 1, 0, 2, 2, 1, 0, 2)
        phrase_gain = (0.82, 0.97, 0.77, 0.69, 0.80, 0.96, 0.82, 0.64)

    for bar in range(bar_count):
        group, chord_index = divmod(bar, 4)
        section = section_order[group]
        quiet = section == 2
        harmony = bridge if quiet else home
        root, *voicing = harmony[chord_index]
        bar_start = 4 * beat * bar
        if quiet:
            bass_steps = ((0, 0), (2.5, 7))
        elif title:
            bass_steps = ((0, 0), (1.5, 12), (2.0, 0), (3.25, 7))
        else:
            bass_steps = ((0, 0), (2.25, 0), (3.25, 7))
        for position, interval in bass_steps:
            bass = tone(root + interval, (1.38 if interval == 0 else 0.45) * beat, "bass")
            add(track, bass, bar_start + position * beat, 0.21 if interval == 0 else 0.10, loop=True)
        backing = (0.75, 2.5) if quiet else (0.5, 1.5, 2.75, 3.5) if title else (0.75, 1.75, 3.0)
        for step, position in enumerate(backing):
            note = voicing[(step + group) % len(voicing)]
            pluck = tone(note, 0.64, "string")
            add(track, pluck, bar_start + position * beat, 0.078 if title else 0.064,
                -0.24 if step % 2 == 0 else 0.25, loop=True)
        phrase = phrases[section * 4 + chord_index]
        for position, note in phrase:
            voice = "glass" if title and not quiet else "string"
            lead = tone(note, 0.80 if title else 1.0, voice)
            when = bar_start + position * beat
            add(track, lead, when, 0.19 * phrase_gain[group], 0.06, loop=True)
            add(echoes, lead, when, 0.045 * phrase_gain[group], -0.38, loop=True)
        for position in (0.0,) if quiet else (0.0, 2.0 if title else 2.5):
            add(track, puff(130, 63, 0.18, 0.045), bar_start + position * beat,
                0.164 if title else 0.092, loop=True)
        for position in (3.0,) if quiet or not title else (1.0, 3.0):
            wood = puff(790 + 100 * position, 640, 0.10, 0.016)
            add(track, wood, bar_start + position * beat, 0.095 if title else 0.055, 0.22, loop=True)
        for position in () if quiet else (0.5, 1.5, 2.5, 3.5) if title else (1.25,):
            add(track, sand(rng, 0.09, 0.028), bar_start + position * beat,
                0.11 if title else 0.075, -0.29, loop=True)

    # Circular echoes preserve the last bar's short tails at the loop boundary.
    track += np.roll(echoes, frames(beat * 0.75), axis=0)
    track += np.roll(echoes[:, ::-1], frames(beat * 1.5), axis=0) * 0.45
    # Apply the same soft high shelf through the boundary, without fading downbeat attacks.
    if not title:
        softened = (2 * track + np.roll(track, 3, axis=0) + np.roll(track, -3, axis=0)) * 0.25
        track = 0.52 * track + 0.48 * softened
    track -= track.mean(axis=0)
    return scale(track, -20.5 if title else -23.2, -4.8)


def sfx(cue, index, foley, rng):
    root = [74, 76, 78, 81, 83][index % 5]
    variation = 1 + 0.055 * (index - 2)
    if cue == "click":
        signal = puff(1540 * variation, 970 * variation, 0.115, 0.027)
        signal += puff(660 * variation, 552, 0.115, 0.035) * 0.37
        signal += sand(rng, 0.115, 0.010) * 0.22
    elif cue == "hover_a":
        signal = puff(980 * variation, 810, 0.086, 0.017)
        signal += sand(rng, 0.086, 0.012) * 0.12
    elif cue == "hover_b":
        signal = puff(760 * variation, 1120 * variation, 0.091, 0.017)
        signal += sand(rng, 0.091, 0.019) * 0.19
    elif cue == "launch":
        duration = 0.116 + index * 0.003
        signal = foley.swish(duration, 1050 * variation, 3680 * variation, rng) * 0.74
        signal += puff(505, 820 * variation, duration, 0.035) * 0.29
        signal += sand(rng, duration, 0.019) * 0.20
    elif cue == "land":
        duration = 0.139 + index * 0.003
        signal = foley.stone_step(rng, wet=index % 3 != 0)[:frames(duration)] * 0.60
        signal += puff(690 * variation, 298 * variation, duration, 0.039) * 0.41
        signal += puff(2220 * variation, 1530 * variation, duration, 0.016) * 0.23
        signal[-frames(0.024):] *= np.linspace(1, 0, frames(0.024))
    elif cue == "spawn":
        duration = 0.33 + index * 0.03
        signal = foley.gurgle(duration, rng, 155 * variation) * 0.54
        signal += puff(330, 550 * variation, duration, 0.10) * 0.31
    elif cue == "splash":
        duration = 0.25 + index * 0.025
        signal = splash(foley, rng, 0.26 + 0.055 * index, duration)
        signal += puff(460 * variation, 270, duration, 0.059) * 0.30
    else:
        duration, notes = {
            "lamp": (0.36, (root, root + (5 if index % 2 else 7))),
            "upgrade": (0.55, (69, 74, 78, 81)),
            "portal": (0.82, (57, 66, 69, 74)),
        }[cue]
        signal = np.zeros(frames(duration))
        for part, note in enumerate(notes):
            offset = frames(part * (0.09 if cue == "portal" else 0.065))
            tone_duration = (len(signal) - offset) / RATE
            signal[offset:] += tone(note, tone_duration, "glass" if part else "string") * (0.8 + part * 0.08)
        if cue == "portal":
            signal += splash(foley, rng, 0.62, duration) * 0.51
            signal += foley.creak(duration, rng, lo=242, hi=428) * 0.31
            signal += puff(740, 230, duration, 0.142) * 0.58
        elif cue == "lamp":
            signal += foley.flame(rng, duration) * 0.10
    return scale(signal, *SFX_LEVELS[cue])


def opening(letter, foley, rng):
    duration = 5.6 if letter == "D" else 5.8
    track = np.zeros((frames(duration), 2), np.float32)
    water = foley.night_water(duration, rng, flow=0.07).T
    track += water * 0.034
    if letter == "A":
        add(track, foley.flame(rng, 0.54), 0.20, 0.15, -0.07)
        for index, note in enumerate((62, 64, 66, 69, 73, 74, 78, 81)):
            at = 0.75 + index * 0.11
            add(track, tone(note, 0.72, "glass"), at, 0.22, (index - 3.5) / 8)
            add(track, splash(foley, rng, 0.2, 0.25), at, 0.065, (index - 3.5) / 8)
        add(track, foley.riser(0.55, 420, 5400, rng), 2.04, 0.22)
        add(track, puff(152, 48, 0.59, 0.13), 2.60, 0.32)
        reveal = 2.95
    elif letter == "B":
        add(track, foley.bubble(704, 0.07, rng), 0.15, 0.26)
        add(track, foley.brush(0.75, rng), 0.25, 0.19, -0.17)
        for index, note in enumerate((62, 69, 73)):
            add(track, tone(note, 1.25, "string"), 0.95 + index * 0.15, 0.24, index * 0.17 - 0.17)
        add(track, foley.swish(0.19, 2300, 570, rng), 1.95, 0.15, 0.25)
        add(track, puff(170, 52, 0.74, 0.155), 2.12, 0.55, 0.10)
        add(track, foley.woodblock(830, 0.38, rng), 2.12, 0.24, 0.18)
        add(track, foley.swish(0.52, 3500, 620, rng), 2.55, 0.16)
        reveal = 3.28
    else:
        for index, note in enumerate((62, 66, 69, 73, 74)):
            pan = (index - 2) * 0.24
            add(track, sfx("spawn", index % 3, foley, rng), 0.25 + 0.09 * index, 0.46, pan)
            at = 1.25 + 0.30 * index
            add(track, sfx("land", index, foley, rng), at, 0.70, pan)
            add(track, tone(note, 0.64, "string"), at + 0.018, 0.25, pan)
        add(track, foley.flame(rng, 0.42), 2.55, 0.19, 0.2)
        add(track, foley.swish(0.51, 850, 3800, rng), 2.80, 0.16)
        add(track, puff(195, 64, 0.43, 0.09), 3.05, 0.19)
        reveal = 2.72

    for index, note in enumerate((62, 66, 69, 74)):
        add(track, tone(note, 1.50, "glass"), reveal + index * 0.075, 0.23 - 0.017 * index,
            (index - 1.5) * 0.19)
    track += np.roll(track[:, ::-1], frames(0.17), axis=0) * 0.09
    track[:frames(0.07)] *= np.linspace(0, 1, frames(0.07))[:, None]
    # Clear the ambience as the title returns instead of leaving a late tail to be cut by the scene.
    handoff = {"A": 4.50, "B": 4.40, "D": 4.36}[letter]
    fade_start = frames(handoff - 0.72)
    fade_end = frames(handoff - 0.08)
    track[fade_start:fade_end] *= np.cos(np.linspace(0, np.pi / 2, fade_end - fade_start))[:, None] ** 2
    track[fade_end:] = 0
    return scale(track, -21.5, -3.8)


def preview(title, game, sounds):
    track = title[:frames(25)].copy()
    start = frames(4.65)
    blend = frames(0.70)
    size = len(track) - start
    blend_angle = np.linspace(0, np.pi / 2, blend)[:, None]
    track[start:start + blend] = track[start:start + blend] * np.cos(blend_angle) + game[:blend] * np.sin(blend_angle)
    track[start + blend:] = game[blend:size]
    for at, name in [(9, "land"), (12, "lamp"), (15, "click"), (19, "portal")]:
        add(track, sounds[name], at, 1.16)
    track[:frames(0.06)] *= np.linspace(0, 1, frames(0.06))[:, None]
    track[-frames(0.9):] *= np.linspace(1, 0, frames(0.9))[:, None]
    return scale(track, -19.5, -2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="destination assets/audio directory")
    parser.add_argument("--preview", type=Path, help="optional 25 second comparison WAV")
    parser.add_argument("--tools", type=Path, default=Path(__file__).resolve().parent,
                        help="directory with the project's instruments.py and synth.py")
    args = parser.parse_args()
    foley = load_foley(args.tools)
    music_rng = np.random.default_rng(34817)
    sfx_rng = np.random.default_rng(60419)
    opening_rng = np.random.default_rng(83911)
    title = music(True, music_rng)
    game = music(False, music_rng)
    write(args.output / TITLE, title)
    write(args.output / GAME, game)
    samples = {}
    for base, (count, cue) in GROUPS.items():
        for index in range(count):
            sound = sfx(cue, index, foley, sfx_rng)
            write(args.output / "sfx" / f"{base}_{index + 1:03}.wav", sound)
            if index == 0:
                samples[cue] = sound
    for cue, filename in (("portal", "Portal_Loot ST.wav"), ("upgrade", "Upgrade_Loot ST.wav")):
        samples[cue] = sfx(cue, 0, foley, sfx_rng)
        write(args.output / "sfx" / filename, samples[cue])
    for letter in ("A", "B", "D"):
        write(args.output / "opening" / f"open{letter}.wav", opening(letter, foley, opening_rng))
    if args.preview:
        write(args.preview, preview(title, game, samples))


if __name__ == "__main__":
    main()

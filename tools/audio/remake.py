"""城门更鼓. Synthesize every audio source for 守望 with NumPy.

    python -B remake.py --output path/to/assets/audio --preview path/to/preview.wav

When omitted, paths are relative to this script. No samples, plug-ins or
network resources are used.
"""
import argparse
from pathlib import Path
import wave

import numpy as np


SR = 48_000
SEED = 22031
RNG = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parent
TITLE_NAME = "GameOff_Mus_02 MainTitle 143bpm Loop.wav"
GAME_NAME = "GameOff_Mus_01 Loop.wav"


def clock(seconds):
    return np.arange(round(seconds * SR), dtype=np.float64) / SR


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def taper(t, attack, release):
    front = np.sin(np.pi / 2 * np.clip(t / attack, 0, 1)) ** 2
    back = np.sin(np.pi / 2 * np.clip((t[-1] - t) / release, 0, 1)) ** 2
    return front * back


def noise(t, center, width):
    frequency = np.fft.rfftfreq(t.size, 1 / SR)
    weight = np.exp(-0.5 * ((frequency - center) / width) ** 2)
    weight *= np.minimum(frequency / 120, 1)
    spectrum = np.fft.rfft(RNG.standard_normal(t.size))
    out = np.fft.irfft(spectrum * weight, n=t.size)
    return out / max(np.std(out), 1e-6)


def modes(t, partials):
    out = np.zeros_like(t)
    for frequency, gain, delay in partials:
        phase = RNG.uniform(-np.pi, np.pi)
        out += gain * np.sin(2 * np.pi * frequency * t + phase) * np.exp(-t / delay)
    return out


def drum(root, seconds=.90):
    t = clock(seconds)
    phase = 2 * np.pi * (root * t + 26 * .051 * (1 - np.exp(-t / .051)))
    skin = modes(t, ((root * 1.81, .23, .13), (root * 2.57, .13, .09), (root * 3.88, .072, .051)))
    strike = .055 * noise(t, 460, 360) * np.exp(-t / .027)
    return (.73 * np.sin(phase) * np.exp(-t / .22) + skin + strike) * taper(t, .006, .12)


def clapper(root, seconds=.23):
    t = clock(seconds)
    wood = modes(t, ((root, .56, .047), (root * 1.72, .24, .033),
                     (root * 2.74, .13, .022), (root * 3.83, .061, .016)))
    strike = .088 * noise(t, 1320, 820) * np.exp(-t / .012)
    return (wood + strike) * taper(t, .0027, .045)


def pluck(note, seconds, dark=1.0):
    t = clock(seconds)
    root = hz(note)
    weights = (.75, .33, .20, .12, .077, .049, .030, .017, .009)
    string = modes(t, tuple(
        (root * n * (1 + n * n * .000075), gain * dark ** (n - 1), .73 / n ** .66)
        for n, gain in enumerate(weights, 1)
    ))
    finger = .046 * noise(t, 1300, 780) * np.exp(-t / .022)
    return (string + finger) * taper(t, .004, .118)


def flute(note, seconds, down=False):
    t = clock(seconds)
    root = hz(note)
    bend = 1 + (.020 if down else -.028) * np.exp(-t / .078)
    vibrato = 1 + .0049 * np.sin(2 * np.pi * 5.4 * t) * (1 - np.exp(-t / .28))
    phase = 2 * np.pi * np.cumsum(root * bend * vibrato) / SR
    wind = noise(t, 1350, 820)
    voice = .66 * np.sin(phase) + .18 * np.sin(phase * 2) + .077 * np.sin(phase * 3)
    pressure = .86 + .14 * np.sin(np.pi * t / seconds)
    return (voice * pressure + .064 * wind) * taper(t, .080, min(.19, seconds / 3))


def bronze(note, seconds=.44):
    t = clock(seconds)
    root = hz(note)
    ring = modes(t, ((root, .61, .15), (root * 2.008, .25, .105),
                     (root * 2.846, .09, .052), (root * 4.06, .05, .024)))
    return ring * taper(t, .0046, .078)


def water(seconds, center, rise=.028):
    t = clock(seconds)
    flow = noise(t, center, center * .54)
    skin = modes(t, ((center * .24, .16, .069), (center * .5, .08, .099)))
    return (.44 * flow * np.exp(-t / (seconds * .26)) + skin) * taper(t, rise, .055)


def sweep(seconds, low, high, reverse=False):
    t = clock(seconds)
    u = t / seconds
    if reverse:
        u = 1 - u
    ripple = noise(t, low, low * .62) * (1 - u) + noise(t, high, high * .53) * u
    return .44 * ripple * taper(t, seconds * .36, seconds * .24)


def buffer(seconds, stereo=True):
    shape = (round(seconds * SR), 2) if stereo else (round(seconds * SR),)
    return np.zeros(shape, dtype=np.float64)


def add(track, at, sound, gain=1.0, pan=0.0, loop=False):
    start = round(at * SR)
    if track.ndim == 2:
        angle = (pan + 1) * np.pi / 4
        signal = gain * sound[:, None] * np.array((np.cos(angle), np.sin(angle)))
    else:
        signal = gain * sound
    if loop:
        start %= len(track)
    take = min(len(signal), len(track) - start)
    if take <= 0:
        return
    track[start:start + take] += signal[:take]
    if loop and take < len(signal):
        track[:len(signal) - take] += signal[take:]


def court(track, at, sound, gain, pan=0.0, loop=False):
    add(track, at, sound, gain, pan, loop)
    # Low-passed reflections of stone, wood and the far shore.
    reflection = .54 * sound
    for lag in (9, 21, 34):
        reflection[lag:] += .153 * sound[:-lag]
    for delay, weight, position in (
        (.046, .22, -.66), (.082, .18, .62), (.137, .14, -.41),
        (.211, .102, .47), (.308, .065, -.73), (.431, .036, .70),
        (.567, .019, -.47),
    ):
        add(track, at + delay, reflection, gain * weight, position, loop)


def level(track, peak_db=-4.5, rms_db=None):
    peak = max(float(np.max(np.abs(track))), 1e-12)
    gain = 10 ** (peak_db / 20) / peak
    if rms_db is not None:
        rms = max(float(np.sqrt(np.mean(track ** 2))), 1e-12)
        gain = min(gain, 10 ** (rms_db / 20) / rms)
    return track * gain


def periodic_air(track, duration, richness):
    t = clock(duration)

    def oscillator(frequency, phase=0):
        # Integral cycles make phase and modulation periodic at the exact WAV boundary.
        return np.sin(2 * np.pi * round(frequency * duration) * t / duration + phase)

    def sustained(frequency, wobble):
        # Carrier crests line up with the seam, allowing a slow change between samples.
        return oscillator(frequency, np.pi / 2 + wobble - wobble[0])

    drift = oscillator(7 / duration, .21)
    drone = .0095 * sustained(hz(38), .18 * drift)
    drone += .0060 * sustained(hz(45), .27 * drift)
    drone += .0034 * sustained(hz(50), .41 * drift)
    drone *= .86 + .14 * oscillator(4 / duration, .86)
    air = .0016 * sustained(136, oscillator(14 / duration))
    air += .0011 * sustained(249, oscillator(9 / duration, 1.01))
    air *= .6 + .4 * oscillator(11 / duration, .49)
    add(track, 0, drone * richness + air, 1, -.12)
    add(track, 0, air, .58, .67)
    # A quiet D/A resonance ties the cadence over the wrap into the next count.
    distance = np.minimum(t, duration - t)
    wrap = .5 + .5 * np.cos(np.pi * np.clip(distance / .94, 0, 1))
    tie = .024 * oscillator(hz(50), np.pi / 2) + .010 * oscillator(hz(57), np.pi / 2)
    add(track, 0, wrap * tie, richness, -.16)


def music(title):
    beat = .75
    bars = 18 if title else 28
    duration = bars * 4 * beat
    track = buffer(duration)
    progression = (
        (50, 57, 60, 65), (48, 55, 60, 64), (53, 60, 65, 69), (55, 62, 67, 70),
        (50, 57, 62, 65), (55, 62, 65, 69), (48, 55, 60, 67), (45, 52, 57, 64),
    )
    title_calls = (
        ((.91, 69, .62), (1.94, 72, .64), (3.00, 74, .83)),
        ((.39, 77, .43), (1.18, 74, .71), (2.49, 69, 1.33)),
        ((.45, 67, .83), (2.06, 65, .62), (3.09, 62, .78)),
        ((.63, 69, .73), (2.59, 72, 1.22)),
        ((.79, 77, .56), (1.72, 79, .74), (3.03, 74, 1.16)),
        ((.59, 72, .74), (2.07, 69, 1.11)),
    )
    game_calls = (
        ((1.53, 69, .60), (2.94, 67, .55)),
        ((2.48, 65, .71),),
        ((1.23, 72, .64),), ((.49, 74, .51), (2.45, 69, .66)),
        ((2.67, 62, .74),),
        ((1.95, 67, .72), (3.01, 65, .48)),
        ((2.05, 69, .78),),
    )
    periodic_air(track, duration, 1.0 if title else .72)

    for bar in range(bars):
        start = bar * 4 * beat
        phase = bar % 8
        passage = bar // 8
        root, fifth, upper, top = progression[phase]
        if passage % 2 and phase in (1, 6):
            root, fifth, upper, top = progression[2 if phase == 1 else 3]
        if bar == bars - 2:
            root, fifth, upper, top = progression[-1]
        elif bar == bars - 1:
            root, fifth, upper, top = progression[4]

        if title:
            drums = ((.31, .117), (2.50, .045)) if phase in (0, 3, 4) else ((.39, .063),)
            blocks = ((1.00, .064), (1.44, .041), (3.29, .040))
            bass = ((.60, root, .097), (1.72, fifth, .061), (2.87, upper, .070))
        else:
            movement, measure = divmod(bar, 7)
            # Four patrol passages trade active signals with open space for play sounds.
            drum_measures = ((0, 2, 4), (0, 1, 3, 5), (1, 5), (0, 2, 5))[movement]
            drums = ((.25, .080 - .007 * (movement == 2)),) if measure in drum_measures else ()
            if movement == 1 and measure in (1, 5):
                drums += ((2.86, .035),)
            if measure in (0, 3):
                blocks = ((1.18, .044), (1.62, .026))
            elif measure in (2, 5) and movement != 2:
                blocks = ((3.00, .032),)
            else:
                blocks = ()
            bass = ((.62, root, .082), (2.08, fifth, .052))
            if (measure + movement) % 3 != 1:
                bass += ((3.29, upper, .040 if movement == 2 else .052),)
        if bar == bars - 1:
            # Resolve before the cut. Only the room and the tied fifth reach the next bar.
            drums = ((.38, .049),) if title else ()
            blocks = ((.94, .029),) if title else ()
            bass = ((.50, root, .073), (1.70, fifth, .051))
        for pulse, velocity in drums:
            court(track, start + pulse * beat, drum(65 + phase * .75), velocity, -.12, True)
        for pulse, velocity in blocks:
            pan = .28 if phase % 2 == 0 else .12
            court(track, start + pulse * beat, clapper(595 + 92 * (pulse % 1)), velocity, pan, True)
        for pulse, note, velocity in bass:
            note_length = 1.16 if bar == bars - 1 else 1.45
            court(track, start + pulse * beat, pluck(note, note_length, .87), velocity, -.32, True)
        if bar < bars - 2 and ((title and phase in (2, 4, 6)) or
                               (not title and passage == 2 and phase % 2)):
            court(track, start + 2.47 * beat, pluck(top, 1.65, .81), .053, .48, True)

        if title:
            calls = title_calls[(bar + 2 * passage) % len(title_calls)] if phase not in (3, 7) else ()
        elif measure in ((0, 2, 4, 5), (0, 1, 3, 6), (1, 4), (0, 2, 4, 6))[movement]:
            calls = game_calls[(measure + 2 * movement) % len(game_calls)]
        else:
            calls = ()
        if bar == bars - 2:
            calls = ((1.21, 69, .72), (2.26, 67, .62)) if title else ((2.34, 65, .68),)
        elif bar == bars - 1:
            calls = ((1.37, 62, .97),)
        for pulse, note, seconds in calls:
            gain = (.078 if title else .054) * (1.07 if passage == 1 else 1)
            if bar >= bars - 2:
                gain *= .74
            octave = 12 if title and bar == 9 and note <= 69 else 0
            court(track, start + pulse * beat, flute(note + octave, seconds, passage % 2 == 1),
                  gain, .32, True)
    return level(track, peak_db=-6.2, rms_db=-22.0 if title else -25.0)


def effects():
    entries = {}

    def save(name, sound, peak, rms=None):
        entries[name + ".wav"] = level(sound, peak, rms)

    for i in range(1, 5):
        track = buffer(.145 + .007 * i, False)
        add(track, 0, clapper(995 + 67 * i), .77)
        add(track, .020 + .003 * i, clapper(735 + 31 * i), .41)
        t = clock(len(track) / SR)
        save(f"Button_Click_{i:03}", track * taper(t, .002, .026), -9.1)
    for group, root in (("A", 970), ("B", 715)):
        for i in range(1, 4):
            t = clock(.158 + .012 * i)
            brush = noise(t, 1800 + 135 * i, 820) * np.exp(-t / .035)
            wood = clapper(root + 59 * i, t.size / SR)
            save(f"Button_Hover {group}_{i:03}", (wood + .14 * brush) * taper(t, .004, .046), -21.0)

    for i in range(1, 10):
        t = clock(.125 + .004 * (i % 4))
        grip = modes(t, ((166 + 7 * i, .31, .041), (330 + 12 * i, .14, .026)))
        fabric = noise(t, 810 + 71 * i, 470) * np.exp(-t / .028)
        lift = sweep(len(t) / SR, 510, 1850 + 29 * i)
        save(f"Jump_Launch_{i:03}", (grip + .15 * fabric + .17 * lift) * taper(t, .006, .025), -14.6)
        t = clock(.196 + .006 * (i % 4))
        # Stone contact sits above the watch drum, followed by a short wet scuff.
        stone = modes(t, ((140 + 4.8 * i, .29, .045), (289 + 12 * i, .31, .052),
                          (575 + 19 * i, .23, .035), (966 + 23 * i, .15, .028)))
        wet = water(len(t) / SR, 1730 + 81 * i, .011)
        save(f"Jump_Land_{i:03}", (stone + .38 * wet) * taper(t, .0038, .047), -8.9)

    for i in range(1, 4):
        t = clock(.31 + .025 * i)
        lift = sweep(len(t) / SR, 330 + 44 * i, 1470 + 103 * i)
        bubble = modes(t, ((220 + 17 * i, .31, .080), (485 + 30 * i, .14, .044)))
        save(f"Fish_Spawn Layer A_{i:03}", (lift + bubble) * taper(t, .023, .072), -22.5)
    for i in range(1, 6):
        t = clock(.265 + .016 * i)
        bead = modes(t, ((370 + 34 * i, .29, .049), (770 + 27 * i, .16, .069)))
        splash = water(t.size / SR, 1180 + 83 * i, .008)
        save(f"Fish_Land_{i:03}", (bead + splash) * taper(t, .004, .059), -20.2)

    for i, note in enumerate((74, 77, 76, 79, 81), 1):
        track = buffer(.46 + .023 * i, False)
        add(track, 0, bronze(note + 2, .37 + .009 * i), .78)
        add(track, .050 + .004 * i, bronze(note + (7 if i % 2 == 0 else 9), .35), .58)
        add(track, .022, water(.17, 2000 + 70 * i, .011), .10)
        save(f"Fish_Loot_{i:03}", track * taper(clock(len(track) / SR), .003, .051), -8.5)

    upgrade = buffer(.69, False)
    add(upgrade, 0, clapper(572), .38)
    add(upgrade, .033, pluck(65, .57, .81), .60)
    add(upgrade, .13, bronze(74, .51), .61)
    add(upgrade, .236, bronze(77, .39), .39)
    save("Upgrade_Loot ST", upgrade * taper(clock(.69), .004, .082), -9.6)

    portal = buffer(.89, False)
    add(portal, 0, clapper(514), .58)
    add(portal, .072, clapper(668), .50)
    add(portal, .092, drum(91, .66), .43)
    add(portal, .120, water(.59, 1460, .049), .47)
    add(portal, .213, bronze(69, .56), .47)
    add(portal, .285, bronze(74, .51), .37)
    save("Portal_Loot ST", portal * taper(clock(.89), .004, .093), -7.5)
    return entries


def opening_a(track):
    # Flicker, ascending lanterns, converging lamp light and opening title.
    for i in range(3):
        court(track, .20 + i * .28, clapper(1320 + 170 * i, .19), .055, -.20 + .23 * i)
    for i, note in enumerate((50, 53, 55, 57, 60, 62, 65, 67, 69, 72, 74)):
        at = .75 + i * .118
        pan = (.52 if i % 2 else -.52) * (1 - i / 15)
        court(track, at, pluck(note, .86 + .035 * i, .86), .087 + .006 * i, pan)
        court(track, at + .018, water(.20, 1050 + 44 * i), .033, pan)
    court(track, 1.04, flute(69, .89), .124, .04)
    court(track, 2.05, sweep(.55, 420, 2350), .111, .12)
    court(track, 2.58, drum(69), .45, -.09)
    court(track, 2.60, bronze(74, 1.25), .27, -.17)
    court(track, 2.63, bronze(81, 1.12), .18, .27)
    court(track, 2.95, flute(74, 1.31), .203, .09)


def opening_b(track):
    # Ink falls, the seal lands squarely, the ink recedes.
    court(track, .15, bronze(77, .37), .20, .19)
    court(track, .25, sweep(.87, 400, 1620, reverse=True), .109, -.07)
    court(track, .95, flute(65, 1.02, down=True), .174, -.18)
    court(track, 1.06, pluck(50, 1.36, .79), .14, .34)
    court(track, 1.95, sweep(.17, 2100, 430, reverse=True), .096, -.17)
    court(track, 2.12, drum(55, 1.30), .59, -.09)
    court(track, 2.122, clapper(410), .29, .11)
    for i, note in enumerate((38, 45, 50, 57)):
        court(track, 2.12 + i * .022, pluck(note, 1.45, .84), .265 - i * .032, -.35 + i * .19)
    court(track, 2.55, sweep(.76, 450, 1800, reverse=True), .129, -.22)
    court(track, 3.28, flute(62, 1.23), .189, .22)
    court(track, 3.35, bronze(69, .77), .112, -.17)


def opening_d(track):
    # Five stepping stones, lantern raised, the sparks answer.
    notes = (50, 53, 55, 57, 60)
    for i, note in enumerate(notes):
        pan = -.52 + .26 * i
        court(track, .25 + i * .09, water(.40, 660 + 92 * i, .019), .114, pan)
        court(track, .95 + i * .30, clapper(686 + 46 * i, .18), .059, pan)
        court(track, 1.25 + i * .30, clapper(412 + 22 * i), .142, pan)
        court(track, 1.27 + i * .30, pluck(note, 1.17, .84), .235 + .011 * i, pan)
    court(track, 2.55, sweep(.46, 350, 2460), .088, .27)
    court(track, 2.55, flute(74, 1.26), .211, .25)
    court(track, 2.70, drum(74), .300, -.21)
    court(track, 2.72, pluck(62, 1.36, .85), .205, -.19)
    for i, note in enumerate((74, 77, 81, 79, 86, 81)):
        court(track, 3.05 + .063 * i, bronze(note, .56), .124 - .012 * i,
              RNG.uniform(-.55, .55))


def openings():
    for letter, duration, arrange in (
        ("A", 5.8, opening_a), ("B", 5.8, opening_b), ("D", 5.6, opening_d),
    ):
        track = buffer(duration)
        t = clock(duration)
        bed = .06 * np.sin(2 * np.pi * hz(38) * t)
        bed += .035 * np.sin(2 * np.pi * hz(45) * t + .7)
        bed += .024 * noise(t, 425, 230)
        add(track, 0, bed * taper(t, .66, 1.64), .20)
        arrange(track)
        yield f"open{letter}.wav", level(track * taper(t, .027, .58)[:, None], -4.7, -21)


def preview(title, game, sfx):
    demo = buffer(25.0)
    mark = SR * 5
    half_overlap = round(.16 * SR)
    angle = np.linspace(0, np.pi / 2, 2 * half_overlap)
    title_excerpt = title[:mark + half_overlap].copy()
    title_excerpt *= taper(clock(len(title_excerpt) / SR), .048, .001)[:, None]
    title_excerpt[-2 * half_overlap:] *= np.cos(angle)[:, None]
    demo[:len(title_excerpt)] += title_excerpt

    gameplay = np.concatenate((game[-half_overlap:], game[:SR * 20]))
    gameplay *= taper(clock(len(gameplay) / SR), .001, .90)[:, None]
    gameplay[:2 * half_overlap] *= np.sin(angle)[:, None]
    gameplay_t = (np.arange(len(gameplay)) - half_overlap) / SR
    cues = (
        (9.0, "Jump_Land_004.wav", -.13, 1.13, .30),
        (12.0, "Fish_Loot_003.wav", .15, 1.00, .23),
        (15.0, "Button_Click_003.wav", 0.0, 1.00, .23),
        (19.0, "Portal_Loot ST.wav", -.04, 1.00, .21),
    )
    for at, filename, pan, gain, depth in cues:
        duck = 1 - depth * np.exp(-0.5 * ((gameplay_t - at + 5 - .075) / .17) ** 2)
        gameplay *= duck[:, None]
        add(demo, at, sfx[filename], gain, pan)
    demo[mark - half_overlap:] += gameplay
    return level(demo, -6.0)


def write_wav(path, track):
    path.parent.mkdir(parents=True, exist_ok=True)
    channels = 1 if track.ndim == 1 else track.shape[1]
    pcm = np.rint(np.clip(track, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setparams((channels, 2, SR, 0, "NONE", "not compressed"))
        wav.writeframes(pcm.tobytes())


def main():
    global RNG
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "assets" / "audio")
    parser.add_argument("--preview", type=Path, default=ROOT / "preview.wav")
    options = parser.parse_args()
    # Independent score, effects and opening streams keep changes in one from
    # changing random phases in the others when the project is rebuilt.
    RNG = np.random.default_rng(SEED)
    title = music(title=True)
    write_wav(options.output / TITLE_NAME, title)
    RNG = np.random.default_rng(SEED + 1)
    game = music(title=False)
    write_wav(options.output / GAME_NAME, game)
    RNG = np.random.default_rng(SEED + 2)
    sfx = effects()
    for name, track in sfx.items():
        write_wav(options.output / "sfx" / name, track)
    RNG = np.random.default_rng(SEED + 3)
    for name, track in openings():
        write_wav(options.output / "opening" / name, track)
    write_wav(options.preview, preview(title, game, sfx))
    print(f"Created {len(sfx) + 5} WAVs and a 25-second preview.")
    for name, track in ((TITLE_NAME, title), (GAME_NAME, game)):
        jump = np.max(np.abs(track[0] - track[-1]))
        rms = np.sqrt(np.mean(track ** 2))
        print(f"{name}: {len(track) / SR:g}s, rms={20 * np.log10(rms):.1f} dBFS, "
              f"boundary step={20 * np.log10(max(jump, 1e-12)):.1f} dBFS")


if __name__ == "__main__":
    main()

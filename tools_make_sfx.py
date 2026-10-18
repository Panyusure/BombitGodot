# -*- coding: utf-8 -*-
"""程序化合成 BombIt 音效（对应 HTML 版 sfx.js 的振荡器 + 噪声设计）。"""
import math
import os
import random
import struct
import wave

SR = 44100
DST = r"E:\BombitGodot\assets\audio\sfx"


def env(t, dur, attack=0.005, release=0.2):
    if t < attack:
        return t / attack
    r = (dur - t) / max(0.0001, release)
    return max(0.0, min(1.0, r))


def tone(freq_start, freq_end, dur, vol=0.5, wave_type="sine", attack=0.005, release=0.2, vibrato=0.0):
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq_start + (freq_end - freq_start) * (t / dur)
        if vibrato:
            f *= 1.0 + math.sin(2 * math.pi * 7 * t) * vibrato
        phase += 2 * math.pi * f / SR
        if wave_type == "sine":
            s = math.sin(phase)
        elif wave_type == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        elif wave_type == "saw":
            s = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        elif wave_type == "tri":
            s = 2.0 * abs(2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0) - 1.0
        else:
            s = math.sin(phase)
        out.append(s * vol * env(t, dur, attack, release))
    return out


def noise(dur, vol=0.5, lowpass=0.15, attack=0.002, release=0.3):
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        s = random.uniform(-1, 1)
        prev = prev + (s - prev) * lowpass
        out.append(prev * vol * env(t, dur, attack, release))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for tr in tracks:
        for i, s in enumerate(tr):
            out[i] += s
    peak = max(1e-6, max(abs(s) for s in out))
    if peak > 0.95:
        out = [s * 0.95 / peak for s in out]
    return out


def silence(dur):
    return [0.0] * int(SR * dur)


def arp(freqs, step, vol=0.4, wave_type="tri", tail=0.12):
    parts = []
    for i, f in enumerate(freqs):
        parts.append(tone(f, f, step + tail, vol, wave_type))
    out = []
    for i, p in enumerate(parts):
        start = int(i * step * SR)
        need = start + len(p)
        if len(out) < need:
            out += [0.0] * (need - len(out))
        for j, s in enumerate(p):
            out[start + j] += s
    return out


def save(name, samples):
    os.makedirs(DST, exist_ok=True)
    path = os.path.join(DST, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        w.writeframes(frames)
    print(name, round(len(samples) / SR, 2), "s")


def build():
    random.seed(7)
    save("ui_move", mix(tone(660, 820, 0.05, 0.25, "square", release=0.03)))
    save("ui_click", mix(tone(520, 880, 0.07, 0.3, "square", release=0.05),
                         tone(1040, 1200, 0.05, 0.12, "sine")))
    save("bomb_place", mix(tone(260, 120, 0.14, 0.5, "sine", release=0.1),
                           noise(0.06, 0.18, 0.5, release=0.05)))
    save("explode", mix(noise(0.75, 0.55, 0.08, release=0.6),
                        tone(90, 38, 0.65, 0.55, "sine", release=0.55),
                        noise(0.25, 0.25, 0.6, release=0.2)))
    save("item_pickup", mix(arp([784, 988, 1319], 0.055, 0.3, "tri"), tone(1568, 1568, 0.18, 0.12, "sine", release=0.18)))
    save("powerup", mix(arp([523, 659, 784, 1047], 0.06, 0.32, "tri"), tone(1319, 1568, 0.3, 0.15, "sine", release=0.25)))
    save("hurt", mix(tone(330, 90, 0.26, 0.45, "saw", release=0.22),
                     noise(0.12, 0.18, 0.4, release=0.1)))
    save("death", mix(tone(520, 55, 0.85, 0.45, "saw", release=0.7),
                      noise(0.5, 0.22, 0.25, release=0.45)))
    save("shield", mix(tone(1180, 1180, 0.3, 0.3, "sine", release=0.28),
                       tone(1770, 1770, 0.26, 0.18, "sine", release=0.24)))
    save("shield_break", mix(noise(0.3, 0.35, 0.45, release=0.25),
                             tone(900, 300, 0.3, 0.25, "square", release=0.25)))
    save("skill", mix(tone(380, 1500, 0.45, 0.32, "tri", release=0.35, vibrato=0.03),
                      tone(760, 3000, 0.35, 0.12, "sine", release=0.3)))
    save("boss_phase", mix(tone(60, 40, 0.9, 0.5, "sine", release=0.8),
                           tone(120, 300, 0.8, 0.22, "saw", release=0.7),
                           noise(0.7, 0.2, 0.1, release=0.6)))
    save("poison", mix(noise(0.4, 0.25, 0.35, release=0.35),
                       tone(240, 160, 0.4, 0.18, "sine", release=0.35)))
    save("sudden_death", mix(tone(440, 660, 0.18, 0.35, "square", release=0.1),
                             silence(0.06), tone(440, 660, 0.18, 0.35, "square", release=0.1)))
    save("level_clear", mix(arp([523, 659, 784, 1047], 0.12, 0.35, "tri", 0.18)))
    save("win", mix(arp([523, 659, 784, 1047, 1319], 0.13, 0.38, "tri", 0.2),
                    tone(1047, 1047, 0.9, 0.18, "sine", release=0.8)))
    save("lose", mix(tone(392, 196, 0.9, 0.4, "tri", release=0.8),
                     tone(196, 98, 0.9, 0.25, "sine", release=0.8)))
    save("carousel", mix(tone(1047, 1047, 0.25, 0.25, "sine", release=0.22),
                         tone(1568, 1568, 0.3, 0.18, "sine", release=0.28)))
    save("fruit", mix(arp([659, 880], 0.06, 0.3, "tri"), tone(1175, 1175, 0.2, 0.15, "sine", release=0.18)))


if __name__ == "__main__":
    build()

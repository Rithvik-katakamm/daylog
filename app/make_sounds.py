#!/usr/bin/env python3
"""Synthesize daylog's own sounds (no samples, stdlib only).

A mechanical watch "tick" is a tiny impact: a sharp click that rings for a few
milliseconds at a high pitch, then dies. We model it as a short noise burst (the
impact) plus two damped sine partials (the metal ringing), with an exponential decay.
"tock" is the same thing a little lower, so alternating them sounds like an escapement.

Run:  python3 app/make_sounds.py   (writes app/Resources/tick.wav, tock.wav)
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).parent / "Resources"


def click(freq: float, length_ms: float = 25, decay_ms: float = 4.5, seed: int = 7) -> list[float]:
    rng = random.Random(seed)
    n = int(RATE * length_ms / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / (decay_ms / 1000))              # fast exponential decay
        impact = rng.uniform(-1, 1) * math.exp(-t / 0.0008)  # sub-millisecond noise "hit"
        ring = (0.65 * math.sin(2 * math.pi * freq * t)
                + 0.35 * math.sin(2 * math.pi * freq * 2.7 * t))  # inharmonic partial = metal
        out.append(env * (0.55 * ring + 0.45 * impact))
    peak = max(abs(x) for x in out)
    return [x / peak * 0.9 for x in out]


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


if __name__ == "__main__":
    write("tick.wav", click(3400, seed=7))
    write("tock.wav", click(2700, seed=11))
    print("wrote", sorted(p.name for p in OUT.glob("*.wav")))

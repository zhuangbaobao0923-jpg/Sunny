#!/usr/bin/env python3
"""把腾讯云男声样音做降调（音高下移 + 语速同步放慢），模拟 App 内 AVAudioUnitTimePitch 效果。"""
import os, subprocess, wave, array, math, sys

SRC = os.path.join(os.path.dirname(__file__), "out")
OUT = os.path.join(SRC, "shifted")
os.makedirs(OUT, exist_ok=True)

# 源文件 → 输出标签 → 频率系数（<1 = 更低更慢）
JOBS = [
    ("智刚_101011.mp3", "智刚_降3半音", 0.8409),
    ("智刚_101011.mp3", "智刚_降4半音", 0.7937),
    ("智辉_101013.mp3", "智辉_降3半音", 0.8409),
    ("智靖_101010.mp3", "智靖_降3半音", 0.8409),
]


def to_wav(mp3: str, wav: str) -> bool:
    r = subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", mp3, wav],
        capture_output=True)
    return r.returncode == 0 and os.path.exists(wav)


def shift(wav_in: str, wav_out: str, factor: float):
    with wave.open(wav_in, "rb") as w:
        params = w.getparams()
        frames = w.readframes(w.getnframes())
    src = array.array("h")
    src.frombytes(frames)
    n = len(src)
    out_len = int(n / factor)
    out = array.array("h", bytes(2 * out_len))
    for i in range(out_len):
        pos = i * factor
        i0 = int(pos)
        i1 = min(i0 + 1, n - 1)
        frac = pos - i0
        out[i] = int(src[i0] * (1 - frac) + src[i1] * frac)
    with wave.open(wav_out, "wb") as w:
        w.setparams(params)
        w.writeframes(out.tobytes())


for src_name, label, factor in JOBS:
    mp3 = os.path.join(SRC, src_name)
    if not os.path.exists(mp3):
        print("skip", src_name); continue
    tmp_in = os.path.join(OUT, "_tmp_in.wav")
    tmp_out = os.path.join(OUT, "_tmp_out.wav")
    if not to_wav(mp3, tmp_in):
        print("afconvert failed", src_name); continue
    shift(tmp_in, tmp_out, factor)
    final = os.path.join(OUT, label + ".m4a")
    r = subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", tmp_out, final],
                       capture_output=True)
    if r.returncode != 0:
        final = os.path.join(OUT, label + ".wav")
        os.replace(tmp_out, final)
    print("OK", label, "->", final)
    for f in (tmp_in, tmp_out):
        if os.path.exists(f):
            os.remove(f)

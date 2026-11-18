#!/usr/bin/env python3
"""全量探测腾讯云精品音色：哪些可用 / 真实性别（F0 基频分析）/ 输出样音。
基础音色免费额度可用；大模型音色需额外资源包（当前 PkgExhausted）。"""
import base64, json, os, struct, subprocess, sys, wave
import voice_probe as vp

OUT = os.path.join(os.path.dirname(__file__), "out", "catalog")
os.makedirs(OUT, exist_ok=True)

# 精品音色编号池（文档 101001-101056）
IDS = [101001, 101002, 101003, 101004, 101005, 101006, 101007, 101008, 101009,
       101010, 101011, 101012, 101013, 101014, 101015, 101016, 101017, 101018,
       101020, 101021, 101022, 101023, 101024, 101025, 101026, 101027, 101028,
       101029, 101030, 101031, 101032, 101033, 101034, 101035, 101054]


def synth_16k(vt: int) -> bytes | None:
    """基础音色只支持 8k/16k，用 16k。"""
    ts = __import__("time").time()
    import hashlib, hmac, datetime, urllib.request, urllib.error
    date = datetime.datetime.utcfromtimestamp(int(ts)).strftime("%Y-%m-%d")
    payload = {
        "Text": "夜深了，有些话只想说给你一个人听。", "SessionId": "cat-" + os.urandom(6).hex(),
        "VoiceType": vt, "Codec": "mp3", "SampleRate": 16000,
        "Speed": 0, "Volume": 0, "ProjectId": 0, "ModelType": 1,
        "PrimaryLanguage": 1, "EnableSubtitle": False,
    }
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    ct = "application/json; charset=utf-8"
    ch = vp.sha256_hex(body.encode())
    canonical = "POST\n/\n\ncontent-type:%s\nhost:%s\n\ncontent-type;host\n%s" % (ct, vp.HOST, ch)
    scope = "%s/%s/tc3_request" % (date, vp.SERVICE)
    to_sign = "TC3-HMAC-SHA256\n%d\n%s\n%s" % (int(ts), scope, vp.sha256_hex(canonical.encode()))
    k = vp.hmac_sha256(("TC3" + vp.SECRET_KEY).encode(), date)
    k = vp.hmac_sha256(k, vp.SERVICE); k = vp.hmac_sha256(k, "tc3_request")
    sig = hmac.new(k, to_sign.encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request("https://" + vp.HOST, data=body.encode(), method="POST")
    req.add_header("Content-Type", ct)
    req.add_header("Authorization", "TC3-HMAC-SHA256 Credential=%s/%s, SignedHeaders=content-type;host, Signature=%s"
                   % (vp.SECRET_ID, scope, sig))
    req.add_header("X-TC-Timestamp", str(int(ts)))
    req.add_header("X-TC-Version", vp.VERSION)
    req.add_header("X-TC-Region", vp.REGION)
    req.add_header("X-TC-Action", "TextToVoice")
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            r = json.loads(resp.read()).get("Response", {})
    except Exception as e:
        return None
    if "Error" in r:
        return None
    a = r.get("Audio", "")
    return base64.b64decode(a) if a else None


def mp3_to_wav(mp3_path: str, wav_path: str) -> bool:
    try:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                        mp3_path, wav_path], check=True, capture_output=True)
        return os.path.exists(wav_path)
    except Exception:
        return False


def median_f0(wav_path: str) -> float | None:
    """自相关法估基频中位数（Hz）。男声 ~85-160，女声 ~180-300。"""
    try:
        with wave.open(wav_path, "rb") as w:
            n = w.getnframes(); sr = w.getframerate()
            raw = w.readframes(n)
    except Exception:
        return None
    data = struct.unpack("<%dh" % (len(raw) // 2), raw)
    frame, hop = int(sr * 0.04), int(sr * 0.01)
    lo, hi = int(sr / 400), int(sr / 70)   # 70~400Hz 搜索
    f0s = []
    for start in range(0, max(1, len(data) - frame), hop):
        seg = data[start:start + frame]
        energy = sum(x * x for x in seg) / frame
        if energy < 3_000_000:            # 静音跳过
            continue
        best_lag, best_val = 0, 0.0
        for lag in range(lo, min(hi, frame - 2)):
            s = 0
            for i in range(0, frame - lag, 3):   # 抽样 1/3 加速
                s += seg[i] * seg[i + lag]
            if s > best_val:
                best_val, best_lag = s, lag
        if best_lag:
            f0s.append(sr / best_lag)
    if len(f0s) < 8:
        return None
    f0s.sort()
    return f0s[len(f0s) // 2]


if __name__ == "__main__":
    rows = []
    for vt in IDS:
        mp3 = os.path.join(OUT, "%d.mp3" % vt)
        wav = os.path.join(OUT, "%d.wav" % vt)
        if not os.path.exists(mp3):
            data = synth_16k(vt)
            if not data:
                print("%6d  UNAVAILABLE" % vt)
                continue
            open(mp3, "wb").write(data)
        if not os.path.exists(wav):
            mp3_to_wav(mp3, wav)
        f0 = median_f0(wav) if os.path.exists(wav) else None
        gender = "?" if f0 is None else ("男" if f0 < 170 else "女")
        rows.append((vt, f0, gender))
        print("%6d  F0=%-6s %s  %6d bytes" % (vt, ("%.0f" % f0) if f0 else "-", gender,
                                             os.path.getsize(mp3)))
    boys = [r for r in rows if r[2] == "男"]
    print("\n男声候选：", ", ".join("%d(%.0fHz)" % (vt, f0) for vt, f0, g in boys if f0))

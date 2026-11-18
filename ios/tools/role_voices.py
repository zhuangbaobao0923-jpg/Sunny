#!/usr/bin/env python3
"""按新映射生成三个角色的真实台词样音（16k，无端上变调，仅语速调整）。"""
import base64, json, os, time, datetime, urllib.request
import voice_probe as vp

OUT = os.path.join(os.path.dirname(__file__), "out", "roles")
os.makedirs(OUT, exist_ok=True)

# (角色, VoiceType, 音色备注, Speed, 台词)
ROLES = [
    ("沈惊寒_智瑞105Hz", 101021, -1, "夜深了。这宫里的人都在睡，只有我醒着——等你。"),
    ("沈惊寒_智辉116Hz", 101013, -1, "夜深了。这宫里的人都在睡，只有我醒着——等你。"),
    ("谢无咎_智瑞105Hz", 101021, -1, "雨这么大还赶路？要么进屋喝酒，要么滚回雨里，选一个。"),
    ("谢无咎_智柯140Hz", 101030, -1, "雨这么大还赶路？要么进屋喝酒，要么滚回雨里，选一个。"),
    ("裴经年_智柯140Hz", 101030, -1, "这门课不及格的人，我不会替他求情。但你要是真想学，我留下来。"),
    ("裴经年_智华123Hz", 101010, 0, "这门课不及格的人，我不会替他求情。但你要是真想学，我留下来。"),
]


def synth(vt: int, text: str, speed: int) -> bytes | None:
    import hashlib, hmac
    ts = int(time.time())
    date = datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")
    payload = {
        "Text": text, "SessionId": "role-" + os.urandom(6).hex(),
        "VoiceType": vt, "Codec": "mp3", "SampleRate": 16000,
        "Speed": speed, "Volume": 0, "ProjectId": 0, "ModelType": 1,
        "PrimaryLanguage": 1, "EnableSubtitle": False,
    }
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    ct = "application/json; charset=utf-8"
    canonical = "POST\n/\n\ncontent-type:%s\nhost:%s\n\ncontent-type;host\n%s" % (
        ct, vp.HOST, vp.sha256_hex(body.encode()))
    scope = "%s/%s/tc3_request" % (date, vp.SERVICE)
    to_sign = "TC3-HMAC-SHA256\n%d\n%s\n%s" % (ts, scope, vp.sha256_hex(canonical.encode()))
    k = vp.hmac_sha256(("TC3" + vp.SECRET_KEY).encode(), date)
    k = vp.hmac_sha256(k, vp.SERVICE); k = vp.hmac_sha256(k, "tc3_request")
    sig = hmac.new(k, to_sign.encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request("https://" + vp.HOST, data=body.encode(), method="POST")
    req.add_header("Content-Type", ct)
    req.add_header("Authorization", "TC3-HMAC-SHA256 Credential=%s/%s, SignedHeaders=content-type;host, Signature=%s"
                   % (vp.SECRET_ID, scope, sig))
    req.add_header("X-TC-Timestamp", str(ts))
    req.add_header("X-TC-Version", vp.VERSION)
    req.add_header("X-TC-Region", vp.REGION)
    req.add_header("X-TC-Action", "TextToVoice")
    with urllib.request.urlopen(req, timeout=40) as resp:
        r = json.loads(resp.read()).get("Response", {})
    if "Error" in r:
        print("  ERR", r["Error"].get("Code"), str(r["Error"].get("Message"))[:60])
        return None
    a = r.get("Audio", "")
    return base64.b64decode(a) if a else None


if __name__ == "__main__":
    for name, vt, speed, text in ROLES:
        data = synth(vt, text, speed)
        if data:
            path = os.path.join(OUT, "%s.mp3" % name)
            open(path, "wb").write(data)
            print("OK %-22s %6d bytes" % (name, len(data)))
        else:
            print("FAIL", name)

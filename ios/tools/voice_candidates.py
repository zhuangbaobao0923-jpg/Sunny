#!/usr/bin/env python3
"""直接调用腾讯云 TextToVoice，为沈惊寒生成多个候选男声样音（TC3-HMAC-SHA256）。"""
import hashlib, hmac, json, os, time, datetime, urllib.request

# 密钥只从环境变量读，不写进仓库：
#   export TENCENT_SECRET_ID=... TENCENT_SECRET_KEY=...
SECRET_ID = os.environ.get("TENCENT_SECRET_ID", "").strip()
SECRET_KEY = os.environ.get("TENCENT_SECRET_KEY", "").strip()
if not SECRET_ID or not SECRET_KEY:
    raise SystemExit("缺少腾讯云凭据：请先 export TENCENT_SECRET_ID / TENCENT_SECRET_KEY")
HOST = "tts.tencentcloudapi.com"
SERVICE, VERSION, REGION = "tts", "2019-08-23", "ap-guangzhou"

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

# 候选男声：智刚(沉稳厚重) / 智靖(低沉成熟) / 智辉(磁性低音) / 智杰(清冷少年，当前在用)
CANDIDATES = [
    (101011, "智刚", -1),
    (101010, "智靖", -1),
    (101013, "智辉", -2),
    (101012, "智杰(当前)", -1),
]
TEXT = "夜深了。这宫里的人都在睡，只有我醒着——等你。"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hmac_sha256(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def synthesize(voice_type: int, speed: int) -> bytes:
    ts = int(time.time())
    date = datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")
    payload = {
        "Text": TEXT, "SessionId": "diag-" + os.urandom(8).hex(),
        "VoiceType": voice_type, "Codec": "mp3", "SampleRate": 16000,
        "Speed": speed, "Volume": 0, "ProjectId": 0, "ModelType": 1,
        "PrimaryLanguage": 1, "EnableSubtitle": False,
    }
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    ct = "application/json; charset=utf-8"
    canonical = "POST\n/\n\ncontent-type:%s\nhost:%s\n\ncontent-type;host\n%s" % (
        ct, HOST, sha256_hex(body.encode("utf-8")))
    scope = "%s/%s/tc3_request" % (date, SERVICE)
    to_sign = "TC3-HMAC-SHA256\n%d\n%s\n%s" % (ts, scope, sha256_hex(canonical.encode("utf-8")))
    k = hmac_sha256(("TC3" + SECRET_KEY).encode("utf-8"), date)
    k = hmac_sha256(k, SERVICE)
    k = hmac_sha256(k, "tc3_request")
    sig = hmac.new(k, to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    req = urllib.request.Request("https://" + HOST, data=body.encode("utf-8"), method="POST")
    req.add_header("Content-Type", ct)
    req.add_header("Authorization",
                   "TC3-HMAC-SHA256 Credential=%s/%s, SignedHeaders=content-type;host, Signature=%s"
                   % (SECRET_ID, scope, sig))
    req.add_header("X-TC-Timestamp", str(ts))
    req.add_header("X-TC-Version", VERSION)
    req.add_header("X-TC-Region", REGION)
    req.add_header("X-TC-Action", "TextToVoice")
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    if "Error" in data.get("Response", {}):
        raise RuntimeError(data["Response"]["Error"])
    import base64
    return base64.b64decode(data["Response"]["Audio"])


for vt, name, speed in CANDIDATES:
    try:
        audio = synthesize(vt, speed)
        path = os.path.join(OUT, "%s_%d.mp3" % (name.split("(")[0], vt))
        with open(path, "wb") as f:
            f.write(audio)
        print("OK  %-10s VoiceType=%d  %d bytes -> %s" % (name, vt, len(audio), path))
    except Exception as e:
        print("ERR %-10s VoiceType=%d  %s" % (name, vt, e))

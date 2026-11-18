#!/usr/bin/env python3
"""探测腾讯云大模型/超自然大模型音色：哪些可用、ModelType 该填几。"""
import hashlib, hmac, json, os, time, datetime, urllib.request, urllib.error

# 密钥只从环境变量读，不写进仓库：
#   export TENCENT_SECRET_ID=... TENCENT_SECRET_KEY=...
SECRET_ID = os.environ.get("TENCENT_SECRET_ID", "").strip()
SECRET_KEY = os.environ.get("TENCENT_SECRET_KEY", "").strip()
if not SECRET_ID or not SECRET_KEY:
    raise SystemExit("缺少腾讯云凭据：请先 export TENCENT_SECRET_ID / TENCENT_SECRET_KEY")
HOST = "tts.tencentcloudapi.com"
SERVICE, VERSION, REGION = "tts", "2019-08-23", "ap-guangzhou"

OUT = os.path.join(os.path.dirname(__file__), "out", "bigmodel")
os.makedirs(OUT, exist_ok=True)

# 男声候选（超自然大模型 / 大模型 / 超自然2.0）
CANDIDATES = [
    (603006, "沉稳青叔", "超自然"),
    (603005, "知心大林", "超自然"),
    (603003, "随和老李", "超自然"),
    (602004, "暖心阿灿", "超自然"),
    (603000, "懂事少年", "超自然"),
    (502006, "智小悟", "超自然"),
    (402002, "云大围", "超自然2.0"),
    (403009, "云嘉尔", "超自然2.0"),
    (403010, "云嘉和", "超自然2.0"),
    (501005, "飞镜", "大模型"),
    (501006, "千嶂", "大模型"),
    (501003, "智宇", "大模型"),
    (601008, "爱小豪", "大模型"),
]
TEXT = "夜深了。这宫里的人都在睡，只有我醒着——等你。"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hmac_sha256(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def call(voice_type: int, model_type: int, speed: int = 0, sample_rate: int = 24000):
    ts = int(time.time())
    date = datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")
    payload = {
        "Text": TEXT, "SessionId": "probe-" + os.urandom(8).hex(),
        "VoiceType": voice_type, "Codec": "mp3", "SampleRate": sample_rate,
        "Speed": speed, "Volume": 0, "ProjectId": 0, "ModelType": model_type,
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
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"Response": {"Error": {"Code": "HTTP%d" % e.code,
                                       "Message": e.read().decode("utf-8", "ignore")[:200]}}}
    except Exception as e:
        return {"Response": {"Error": {"Code": "NET", "Message": str(e)[:200]}}}


if __name__ == "__main__":
    for vt, name, tier in CANDIDATES:
        ok = False
        last_err = ""
        for mt in (1, 2, 3):
            res = call(vt, mt)
            r = res.get("Response", {})
            if "Error" in r:
                last_err = "%s: %s" % (r["Error"].get("Code"), r["Error"].get("Message", "")[:60])
                continue
            audio = r.get("Audio", "")
            if not audio:
                last_err = "no audio"
                continue
            import base64
            data = base64.b64decode(audio)
            fn = os.path.join(OUT, "%s_%d_MT%d.mp3" % (name, vt, mt))
            open(fn, "wb").write(data)
            print("OK   %-8s %6d MT=%d %-6s %6d bytes" % (name, vt, mt, tier, len(data)))
            ok = True
            break
        if not ok:
            print("FAIL %-8s %6d %-6s -> %s" % (name, vt, tier, last_err))

#!/usr/bin/env python3
"""BreezeBlue 单点验收脚本：只验证"能不能生成音频"，不碰 AstrBot / QQ。

用法（在能访问外网的机器上）：
  export BREEZE_API_KEY='...'          # 只放环境变量，别写进命令历史/聊天
  python3 tools/test_api.py --voices   # 查 Voice ID 是否存在
  python3 tools/test_api.py            # 合成测试句
  python3 tools/test_api.py --text "另一句话" --voice voc_xxx

输出只包含状态码、音频大小、时长、Voice 元数据；不会打印 Key。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

try:
    import httpx
except ModuleNotFoundError:
    print("缺少依赖 httpx：pip install httpx", file=sys.stderr)
    sys.exit(2)

BASE_URL = os.environ.get("BREEZE_BASE_URL", "https://api.breeze.blue").rstrip("/")
DEFAULT_VOICE = os.environ.get("BREEZE_VOICE_ID", "voc_8yud7hz7c9q2")
DEFAULT_TEXT = "呜哇，被你发现啦! 我在认真思考呢，才没有摸鱼。"


def _key() -> str:
    key = os.environ.get("BREEZE_API_KEY", "").strip()
    if not key:
        print("缺少环境变量 BREEZE_API_KEY（不要在这里直接粘贴密钥）", file=sys.stderr)
        sys.exit(2)
    return key


def list_voices(key: str, voice_id: str) -> None:
    with httpx.Client(timeout=20) as c:
        r = c.get(
            f"{BASE_URL}/v1/voices",
            params={"search": voice_id, "voice_type": "all", "page_size": 20},
            headers={"xi-api-key": key},
        )
    print(f"GET /v1/voices -> HTTP {r.status_code}")
    if r.status_code != 200:
        print(r.text[:300])
        return
    data = r.json()
    voices = data.get("voices") or []
    hit = next((v for v in voices if v.get("voice_id") == voice_id), None)
    if not hit:
        print(f"未在返回结果中找到 {voice_id}（total={data.get('total')}）。")
        print("可能原因：Key 不属于该 Voice、Voice 已删除、或需要传 voice_type=personal。")
        return
    fields = ["voice_id", "name", "language_code", "gender", "age", "origin", "voice_type", "tone", "description"]
    print(json.dumps({k: hit.get(k) for k in fields}, ensure_ascii=False, indent=2))
    if hit.get("preview_url"):
        print("preview_url:", hit["preview_url"])


def synth(key: str, voice_id: str, text: str, out: str) -> None:
    payload = {"text": text, "model_id": os.environ.get("BREEZE_MODEL_ID", "breeze-tts-2"), "language_code": "zh"}
    with httpx.Client(timeout=60) as c:
        r = c.post(
            f"{BASE_URL}/v1/text-to-speech/{voice_id}",
            params={"output_format": "wav_24000", "delivery": "sync"},
            json=payload,
            headers={"xi-api-key": key, "Content-Type": "application/json"},
        )
    print(f"POST /v1/text-to-speech/{voice_id} -> HTTP {r.status_code}")
    if r.status_code != 200 or not r.content:
        print("失败：", (r.text or "")[:300])
        sys.exit(1)
    with open(out, "wb") as f:
        f.write(r.content)
    print(f"已保存 {out}  {len(r.content)} bytes  content-type={r.headers.get('content-type')}")
    print(f"字符数 {len(text)}")
    if subprocess.call(["which", "ffprobe"], stdout=subprocess.DEVNULL) == 0:
        subprocess.call(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate", "-of", "default=nw=1", out]
        )
        subprocess.call(["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", out])


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--voices", action="store_true", help="查询 Voice 元数据")
    p.add_argument("--text", default=DEFAULT_TEXT)
    p.add_argument("--voice", default=DEFAULT_VOICE)
    p.add_argument("--out", default="breeze_test.wav")
    a = p.parse_args()
    key = _key()
    if a.voices:
        list_voices(key, a.voice)
    else:
        synth(key, a.voice, a.text, a.out)


if __name__ == "__main__":
    main()

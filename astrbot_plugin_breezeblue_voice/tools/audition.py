#!/usr/bin/env python3
"""音色试听器：先免费听 preview，再用同一句话做付费对比。

  export BREEZE_API_KEY='...'
  python3 tools/audition.py --list --gender female --age young
  python3 tools/audition.py --preview 5 --tone warm --tone gentle --gender female
  python3 tools/audition.py --pick 5 --tone playful --age young --gender female
  python3 tools/audition.py --voice voc_xxx,voc_yyy --pick

--preview 只下载官方试听样本，不消耗合成字符；--pick 会用统一测试句合成，按字符计费。
输出目录 audition/，文件名带序号和 voice_id，方便对比。不会打印 Key。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    import httpx
except ModuleNotFoundError:  # 系统 python 里常缺，AstrBot 环境自带
    print("缺少依赖 httpx：pip install httpx", file=sys.stderr)
    raise SystemExit(2)

BASE_URL = os.environ.get("BREEZE_BASE_URL", "https://api.breeze.blue").rstrip("/")
TEST_SENTENCE = "呜哇，被你发现啦! 我在认真思考呢，才没有摸鱼。"
MODEL_ID = os.environ.get("BREEZE_MODEL_ID", "breeze-tts-2")


def key() -> str:
    k = os.environ.get("BREEZE_API_KEY", "").strip()
    if not k:
        print("缺少 BREEZE_API_KEY", file=sys.stderr)
        sys.exit(2)
    return k


def safe(name: str) -> str:
    return re.sub(r"[^\w\u4e00-\u9fa5-]+", "_", name)[:28] or "voice"


def fetch_voices(k: str, a) -> list[dict]:
    if a.voice:
        out = []
        with httpx.Client(timeout=20) as c:
            for vid in [v.strip() for v in a.voice.split(",") if v.strip()]:
                r = c.get(f"{BASE_URL}/v1/voices/{vid}", headers={"xi-api-key": k})
                if r.status_code == 200:
                    out.append(r.json())
                else:
                    print(f"{vid}: HTTP {r.status_code}")
        return out

    params: list[tuple[str, str]] = [
        ("language_code", "zh"),
        ("voice_type", "default"),
        ("sort", "trend"),
        ("page_size", "50"),
    ]
    if a.category:
        params.append(("primary_category_code", a.category))
    for g in a.gender or []:
        params.append(("gender", g))
    for ag in a.age or []:
        params.append(("age", ag))
    for t in a.tone or []:
        params.append(("tone", t))
    if a.accent:
        params.append(("accent", a.accent))
    with httpx.Client(timeout=20) as c:
        r = c.get(f"{BASE_URL}/v1/voices", params=params, headers={"xi-api-key": k})
    if r.status_code != 200:
        print(f"HTTP {r.status_code}: {r.text[:200]}")
        sys.exit(1)
    return (r.json().get("voices") or [])[: a.limit]


def show(voices: list[dict]) -> None:
    print(f"共 {len(voices)} 个候选\n")
    print(f"{'#':<3}{'voice_id':<22}{'名称':<14}{'性别':<8}{'年龄':<12}{'tone':<26}accent")
    for i, v in enumerate(voices, 1):
        print(
            f"{i:<3}{v.get('voice_id',''):<22}{str(v.get('name',''))[:12]:<14}"
            f"{str(v.get('gender','')):<8}{str(v.get('age','')):<12}"
            f"{','.join(v.get('tone') or [])[:24]:<26}{v.get('accent') or '-'}"
        )


def download_previews(k: str, voices: list[dict], out: Path) -> None:
    with httpx.Client(timeout=30, follow_redirects=True) as c:
        for i, v in enumerate(voices, 1):
            url = v.get("preview_url")
            if not url:
                print(f"{i}. {v.get('voice_id')} 无 preview_url，跳过")
                continue
            r = c.get(url)
            if r.status_code != 200 or not r.content:
                print(f"{i}. {v.get('voice_id')} 下载失败 HTTP {r.status_code}")
                continue
            p = out / f"{i:02d}_{safe(str(v.get('name','')))[:12]}_{v['voice_id']}.mp3"
            p.write_bytes(r.content)
            print(f"{i}. {v.get('name')} -> {p.name} ({len(r.content)//1024} KB)")


def synth(k: str, voices: list[dict], out: Path, text: str) -> None:
    print(f"\n统一测试句（{len(text)} 字符）：{text}")
    print(f"预计消耗 {len(text) * len(voices)} 字符 / {len(voices)} 次请求\n")
    with httpx.Client(timeout=60) as c:
        for i, v in enumerate(voices, 1):
            vid = v["voice_id"]
            r = c.post(
                f"{BASE_URL}/v1/text-to-speech/{vid}",
                params={"output_format": "wav_24000", "delivery": "sync"},
                json={"text": text, "model_id": MODEL_ID, "language_code": "zh"},
                headers={"xi-api-key": k, "Content-Type": "application/json"},
            )
            if r.status_code != 200 or not r.content:
                print(f"{i}. {vid} 失败 HTTP {r.status_code}: {(r.text or '')[:120]}")
                continue
            p = out / f"{i:02d}_{safe(str(v.get('name','')))[:12]}_{vid}.wav"
            p.write_bytes(r.content)
            print(f"{i}. {v.get('name')} ({vid}) -> {p.name} ({len(r.content)//1024} KB)")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--list", action="store_true")
    p.add_argument("--preview", type=int, metavar="N", help="下载前 N 个官方试听样本（不计费）")
    p.add_argument("--pick", type=int, nargs="?", const=5, metavar="N", help="用测试句合成前 N 个对比")
    p.add_argument("--voice", help="指定 voice_id，逗号分隔（跳过筛选）")
    p.add_argument("--gender", action="append")
    p.add_argument("--age", action="append")
    p.add_argument("--tone", action="append")
    p.add_argument("--category", help="roleplay / podcast / narration ...")
    p.add_argument("--accent", help="mandarin_beijing / mandarin_sichuan / cantonese ...")
    p.add_argument("--text", default=TEST_SENTENCE)
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--out", default="audition")
    a = p.parse_args()

    k = key()
    voices = fetch_voices(k, a)
    if not voices:
        print("没有候选；放宽筛选条件或检查 Key 的语言/分类过滤。")
        return
    show(voices)

    out = Path(a.out)
    out.mkdir(exist_ok=True)
    if a.preview:
        print()
        download_previews(k, voices[: a.preview], out)
    if a.pick is not None:
        synth(k, voices[: a.pick], out, a.text)
    if not a.preview and a.pick is None:
        print("\n加 --preview N 免费试听，或 --pick N 用同一句话对比。")


if __name__ == "__main__":
    main()

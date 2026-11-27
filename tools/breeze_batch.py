#!/usr/bin/env python3
"""夜谈 × BreezeBlue 批量试音：把固定台词用多只音色各生成一遍。

用法（不要在任何命令里明文写 Key）：
  printf '%s' 'brz_...' > ~/.breeze_key && chmod 600 ~/.breeze_key
  python3 tools/breeze_batch.py --dry-run          # 只算用量，不调接口
  python3 tools/breeze_batch.py --lines 1,3,4      # 生成指定几句
  python3 tools/breeze_batch.py --voice voc_rn489h83rcvs --lines 1

Key 读取顺序：BREEZE_API_KEY 环境变量 → ~/.breeze_key 文件。
脚本只打印状态码/字节数/计费，不打印 Key。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "https://api.breeze.blue"
OUT_DIR = Path(__file__).resolve().parents[1] / "docs" / "audio" / "final"

VOICES = [
    ("idol", "大肥鱼 · 偶像版", "女声主推 / 年轻成年女性", "voc_rn489h83rcvs"),
    ("commander", "星舰指挥官", "男声 / 霸总 · 领袖感", "voc_q8d8a99gxa7f"),
    ("instructor", "铁血教头", "男声 / 霸总 · 强硬派", "voc_mvdhh8xj9e7k"),
    ("deep-whisperer", "深海低语者", "男声 / 低音炮 · 压迫感", "voc_mtb2gb2f565z"),
    ("deep-bass", "幽巷引路人", "男声 / 低音炮 · 深夜感", "voc_gbaz4j9uyq97"),
    ("monologue", "幕后独白者", "男声 / 成熟 · 戏剧张力", "voc_k7tz43q2yxc2"),
    ("craftsman", "醇厚匠心师", "男声 / 成熟 · 温柔年上", "voc_aa4s73p25jt2"),
]

LINES = [
    ("01_test", "被测句", "呜哇，被你发现啦！我在认真思考呢，才没有摸鱼。"),
    ("02_late", "埋怨", "你今天怎么这么晚才回来，我等你好久了。"),
    ("03_sleepy", "困倦", "别闹了……我困了，你抱着我说会儿话好不好。"),
    ("04_jealous", "吃醋", "哼，我才没有吃醋，你爱跟谁聊跟谁聊。"),
    ("05_comfort", "安慰", "没事的，慢慢来，我一直在这儿。"),
    ("06_laugh", "笑骂", "[轻笑]你这个笨蛋，连这个都记不住。"),
]

INSTRUCTIONS = ""


def billable_units(text: str) -> int:
    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    return cjk * 2 + (len(text) - cjk)


def get_key() -> str:
    key = os.environ.get("BREEZE_API_KEY", "").strip()
    if key:
        return key
    p = Path.home() / ".breeze_key"
    if p.exists():
        key = p.read_text("utf-8").strip()
    if not key:
        print("缺少 Key：设置 BREEZE_API_KEY，或写入 ~/.breeze_key", file=sys.stderr)
        sys.exit(2)
    return key


def select_voices(arg: str) -> list[tuple[str, str, str, str]]:
    if not arg:
        return VOICES
    wanted = {x.strip() for x in arg.split(",") if x.strip()}
    picked = [v for v in VOICES if v[0] in wanted or v[3] in wanted]
    if not picked:
        print(f"未找到音色：{arg}", file=sys.stderr)
        sys.exit(2)
    return picked


def select_lines(arg: str) -> list[tuple[str, str, str]]:
    if not arg:
        return LINES
    idx = set()
    for part in arg.split(","):
        part = part.strip()
        if not part:
            continue
        if part.isdigit():
            idx.add(int(part) - 1)
        else:
            idx |= {i for i, (slug, _, _) in enumerate(LINES) if slug == part}
    picked = [LINES[i] for i in sorted(idx) if 0 <= i < len(LINES)]
    if not picked:
        print(f"未找到台词：{arg}", file=sys.stderr)
        sys.exit(2)
    return picked


def synthesize(key: str, voice_id: str, text: str, out: Path, fmt: str) -> bool:
    payload = {"text": text, "language_code": "zh"}
    if INSTRUCTIONS:
        payload["instructions"] = INSTRUCTIONS
    url = f"{BASE_URL}/v1/text-to-speech/{voice_id}?output_format={fmt}&delivery=sync"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"xi-api-key": key, "Content-Type": "application/json"},
        method="POST",
    )
    for attempt in range(2):
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                body = resp.read()
                ctype = resp.headers.get("content-type", "")
            if body and "audio" in ctype:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(body)
                print(f"  [ok] {out.name}  {len(body)} bytes")
                return True
            print(f"  [fail] 非音频响应 content-type={ctype}")
            return False
        except urllib.error.HTTPError as e:
            detail = e.read()[:200].decode("utf-8", "ignore")
            print(f"  [fail] HTTP {e.code}: {detail}")
            if e.code in (401, 403, 402, 404, 422, 429):
                return False
            if attempt == 1:
                return False
        except Exception as e:  # 超时/网络
            print(f"  [fail] {type(e).__name__}")
            if attempt == 1:
                return False
        time.sleep(1.5)
    return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice", default="", help="逗号分隔的 slug 或 voice_id，默认全部")
    ap.add_argument("--lines", default="", help="逗号分隔的序号或 slug，默认全部 6 句")
    ap.add_argument("--format", default="mp3_24000_128")
    ap.add_argument("--dry-run", action="store_true", help="只算用量，不调接口")
    args = ap.parse_args()

    voices = select_voices(args.voice)
    lines = select_lines(args.lines)
    total = sum(billable_units(t) for _, _, t in lines) * len(voices)
    print(f"音色 {len(voices)} 只 × 台词 {len(lines)} 句 = {len(voices) * len(lines)} 条")
    print(f"预计计费 {total} units = {total / 10:.1f} credits")
    for slug, name, _, vid in voices:
        print(f"  - {name:8} {vid}")
    if args.dry_run:
        print("\n[dry-run] 未调用接口，未消耗 credits。")
        return

    key = get_key()
    ok = fail = 0
    for slug, name, _, vid in voices:
        print(f"\n{name} ({vid})")
        for line_slug, line_name, text in lines:
            out = OUT_DIR / slug / f"{line_slug}.mp3"
            if out.exists() and out.stat().st_size > 1024:
                print(f"  [skip] {out.name} 已存在")
                ok += 1
                continue
            if synthesize(key, vid, text, out, args.format):
                ok += 1
            else:
                fail += 1
    print(f"\n完成：{ok} 成功，{fail} 失败。输出目录 {OUT_DIR}")
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    main()

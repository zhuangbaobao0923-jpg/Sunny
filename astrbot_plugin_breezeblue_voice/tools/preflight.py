#!/usr/bin/env python3
"""在 AstrBot 所在机器/容器里跑：只读体检，不改配置、不打印任何密钥。

  python3 preflight.py [/AstrBot]
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/AstrBot")


def run(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def find_key(node, key: str):
    """在配置里递归找一个键，找不到返回 None。"""
    if isinstance(node, dict):
        if key in node:
            return node[key]
        for v in node.values():
            hit = find_key(v, key)
            if hit is not None:
                return hit
    elif isinstance(node, list):
        for v in node:
            hit = find_key(v, key)
            if hit is not None:
                return hit
    return None


def main() -> None:
    print("== 运行环境 ==")
    print("python:", sys.version.split()[0])
    print("cwd:", os.getcwd())
    print("ffmpeg:", shutil.which("ffmpeg") or "未找到")
    print("astrbot 根目录存在:", ROOT.exists())

    print("\n== 框架版本 ==")
    ver = run([sys.executable, "-c", "import astrbot;print(getattr(astrbot,'__version__',''))"])
    print("astrbot.__version__:", ver or "读取失败")
    for cand in ("astrbot/core/__init__.py", "astrbot/__init__.py"):
        f = ROOT / cand
        if f.exists():
            for line in f.read_text("utf-8", "ignore").splitlines():
                if "__version__" in line:
                    print(f"{cand}: {line.strip()}")
                    break
    if (ROOT / ".git").exists():
        print("git describe:", run(["git", "-C", str(ROOT), "describe", "--tags", "--always"]))

    print("\n== 平台适配器（只打印类型，不打印 token）==")
    cfg_dir = ROOT / "data" / "config"
    for f in sorted(cfg_dir.glob("*.json")) if cfg_dir.exists() else []:
        try:
            data = json.loads(f.read_text("utf-8", "ignore"))
        except Exception:
            continue
        platforms = data.get("platform") or data.get("platforms") or []
        if isinstance(platforms, list):
            for p in platforms:
                if isinstance(p, dict):
                    print(f"{f.name}: type={p.get('type')} enable={p.get('enable')}")

    print("\n== 已装插件（找语音/TTS 相关）==")
    pdir = ROOT / "data" / "plugins"
    if pdir.exists():
        for d in sorted(p for p in pdir.iterdir() if p.is_dir()):
            meta = d / "metadata.yaml"
            name = d.name
            desc = ""
            version = ""
            if meta.exists():
                for line in meta.read_text("utf-8", "ignore").splitlines():
                    if line.startswith("desc:"):
                        desc = line[5:].strip()
                    elif line.startswith("version:"):
                        version = line[8:].strip()
            flag = ""
            low = (name + desc).lower()
            if any(k in low for k in ("tts", "voice", "语音", "audio")):
                flag += " <== 语音相关"
            if "clonetts" in low:
                flag += " [会与本插件抢同一钩子]"
            print(f"- {name} v{version or '?'}{flag}")

    print("\n== 全局 TTS / 分段 / 流式（决定会不会重复合成）==")
    for f in sorted(cfg_dir.glob("*.json")) if cfg_dir.exists() else []:
        try:
            data = json.loads(f.read_text("utf-8", "ignore"))
        except Exception:
            continue
        tts = data.get("provider_tts_settings")
        if isinstance(tts, dict):
            print(
                f"{f.name}: 内置TTS enable={tts.get('enable')} "
                f"概率={tts.get('trigger_probability')} "
                f"dual_output={tts.get('dual_output')} "
                f"use_file_service={tts.get('use_file_service')}"
            )
        seg = (data.get("platform_settings") or {}).get("segmented_reply")
        if isinstance(seg, dict):
            print(f"{f.name}: 分段回复 enable={seg.get('enable')} only_llm_result={seg.get('only_llm_result')}")
        stream = find_key(data, "streaming_response")
        if stream is not None:
            print(f"{f.name}: 流式输出 streaming_response={stream}")
        cb = data.get("callback_api_base")
        if cb:
            print(f"{f.name}: callback_api_base 已配置 = {bool(cb)}")

    print("\n== 数据目录可写性 ==")
    target = ROOT / "data" / "plugin_data"
    print("plugin_data 存在:", target.exists(), "可写:", os.access(target if target.exists() else ROOT, os.W_OK))


if __name__ == "__main__":
    main()

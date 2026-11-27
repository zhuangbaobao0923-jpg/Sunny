"""BreezeBlue 按需语音回复插件（AstrBot v4 / aiocqhttp）。

设计目标
- 不改动原有聊天模型、人设、记忆与 QQ 连接：只在"发送前"这一步把文字消息换成语音。
- 默认 70% 文字 / 30% 语音随机；用户明确说"发语音"时 100% 语音。
- 长回复保留文字；合成失败静默回退文字（不追发第二条，避免重复消息）。
- 每日用量上限 + 会话冷却；密钥只从插件配置或环境变量读取，绝不写入日志。

注意
- on_decorating_result 内不能 yield，只能原地修改 event.get_result().chain。
- Comp.Record 在 aiocqhttp 上最稳；官方 QQ 机器人适配器对 record 的支持随版本变化，需实测。
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import random
import re
import shutil
import time
from datetime import date
from pathlib import Path

import httpx

import astrbot.api.message_components as Comp
from astrbot.api import AstrBotConfig, logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.star import Context, Star

PLUGIN_NAME = "astrbot_plugin_breezeblue_voice"
DEFAULT_VOICE_ID = "voc_8yud7hz7c9q2"
DEFAULT_BASE_URL = "https://api.breeze.blue"
TEST_SENTENCE = "呜哇，被你发现啦! 我在认真思考呢，才没有摸鱼。"

# ---------------------------------------------------------------- 文本清洗

_CODE_BLOCK_RE = re.compile(r"```.*?```", re.S)
_INLINE_CODE_RE = re.compile(r"`([^`]*)`")
_URL_RE = re.compile(r"https?://\S+")
_MD_CHARS_RE = re.compile(r"[*_#>~\[\](){}|\\]+")
_EMOJI_RE = re.compile(
    "[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF"
    "\u2190-\u21FF\u2B00-\u2BFF\uFE0F\u200D]+"
)
_ZERO_WIDTH_RE = re.compile("[\u200b\u200c\u200d\ufeff]")
_WS_RE = re.compile(r"[ \t\u3000]+")
_MULTI_NL_RE = re.compile(r"\n{2,}")
_ELLIPSIS_RE = re.compile(r"…+|\.{3,}")


def sanitize_for_tts(text: str) -> str:
    """把 Markdown / 表情 / 链接 / 代码清掉，避免 TTS 把符号念出来。"""
    t = _CODE_BLOCK_RE.sub("，", text or "")
    t = _INLINE_CODE_RE.sub(r"\1", t)
    t = _URL_RE.sub("", t)
    t = _EMOJI_RE.sub("", t)
    t = _ZERO_WIDTH_RE.sub("", t)
    t = _MD_CHARS_RE.sub("", t)
    t = _ELLIPSIS_RE.sub("，", t)
    t = _WS_RE.sub(" ", t)
    t = _MULTI_NL_RE.sub("\n", t)
    t = re.sub(r"[，,]{2,}", "，", t)
    return t.strip(" ，,\n\t")


class BreezeBlueVoicePlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig):
        super().__init__(context)
        self.config = config
        self.data_dir = self._resolve_data_dir()
        self.audio_dir = self.data_dir / "audio"
        self.audio_dir.mkdir(parents=True, exist_ok=True)
        self.usage_file = self.data_dir / "usage.json"
        self._lock = asyncio.Lock()
        self._last_voice_at: dict[str, float] = {}
        self._warned_no_key = False
        self._clean_cache()

    # ------------------------------------------------------------ 基础工具

    @staticmethod
    def _resolve_data_dir() -> Path:
        try:  # 官方推荐位置：<AstrBot>/data/plugin_data/<plugin>
            from astrbot.core.utils.astrbot_path import get_astrbot_data_path

            return Path(get_astrbot_data_path()) / "plugin_data" / PLUGIN_NAME
        except Exception:
            # 兜底：data/plugins/<plugin>/main.py -> data/plugin_data/<plugin>
            return Path(__file__).resolve().parents[2] / "plugin_data" / PLUGIN_NAME

    def _cfg(self, key: str, default):
        value = self.config.get(key, default) if hasattr(self.config, "get") else default
        if value is None or (isinstance(value, str) and value.strip() == ""):
            return default
        return value

    def _api_key(self) -> str:
        # 优先插件配置（WebUI 已做遮罩），其次服务端环境变量。
        key = str(self._cfg("api_key", "")).strip()
        if key:
            return key
        return os.environ.get("BREEZE_API_KEY", "").strip()

    def _clean_cache(self) -> None:
        days = int(self._cfg("cache_days", 7))
        cutoff = time.time() - days * 86400
        for f in self.audio_dir.glob("*"):
            try:
                if f.is_file() and f.stat().st_mtime < cutoff:
                    f.unlink()
            except OSError:
                pass

    # ------------------------------------------------------------ 用量统计

    def _load_usage(self) -> dict:
        today = date.today().isoformat()
        try:
            data = json.loads(self.usage_file.read_text("utf-8"))
            if not isinstance(data, dict):
                raise ValueError("bad usage file")
        except Exception:
            data = {}
        if data.get("date") != today:
            data = {"date": today, "total": 0, "sessions": {}}
        data.setdefault("sessions", {})
        return data

    def _save_usage(self, data: dict) -> None:
        tmp = self.usage_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), "utf-8")
        tmp.replace(self.usage_file)

    async def _reserve_quota(self, umo: str) -> bool:
        """先占额度再合成，失败时退还，避免超额调用付费接口。"""
        limit_total = int(self._cfg("daily_limit_global", 30))
        limit_session = int(self._cfg("daily_limit_session", 10))
        async with self._lock:
            data = self._load_usage()
            if data["total"] >= limit_total:
                return False
            if data["sessions"].get(umo, 0) >= limit_session:
                return False
            data["total"] += 1
            data["sessions"][umo] = data["sessions"].get(umo, 0) + 1
            self._save_usage(data)
            return True

    async def _refund_quota(self, umo: str) -> None:
        async with self._lock:
            data = self._load_usage()
            data["total"] = max(0, data["total"] - 1)
            if umo in data["sessions"]:
                data["sessions"][umo] = max(0, data["sessions"][umo] - 1)
            self._save_usage(data)

    # ------------------------------------------------------------ 合成语音

    async def _synthesize(self, text: str) -> Path | None:
        api_key = self._api_key()
        if not api_key:
            if not self._warned_no_key:
                self._warned_no_key = True
                logger.warning(
                    "[breezeblue] 未配置 API Key（插件配置 api_key 或环境变量 BREEZE_API_KEY），语音将跳过。"
                )
            return None

        voice_id = str(self._cfg("voice_id", DEFAULT_VOICE_ID)).strip()
        base_url = str(self._cfg("base_url", DEFAULT_BASE_URL)).rstrip("/")
        model_id = str(self._cfg("model_id", "breeze-tts-2")).strip()
        lang = str(self._cfg("language_code", "zh")).strip()
        instructions = str(self._cfg("instructions", "")).strip()
        out_fmt = str(self._cfg("output_format", "wav_24000")).strip()
        timeout = float(self._cfg("timeout_seconds", 20))
        retries = int(self._cfg("max_retries", 1))
        speed = float(self._cfg("speed", 1.0))
        guidance = float(self._cfg("guidance_scale", 1.0))
        speaker_boost = bool(self._cfg("use_speaker_boost", False))

        digest = hashlib.sha256(
            f"{voice_id}|{model_id}|{out_fmt}|{instructions}|{speed}|{guidance}|{speaker_boost}|{text}".encode(
                "utf-8"
            )
        ).hexdigest()[:32]
        cached = self.audio_dir / f"{digest}.wav"
        if cached.exists() and cached.stat().st_size > 1024:
            os.utime(cached, None)
            return cached

        payload: dict = {"text": text}
        if model_id:
            payload["model_id"] = model_id
        if lang:
            payload["language_code"] = lang
        if instructions:
            payload["instructions"] = instructions
        voice_settings: dict = {}
        if speed != 1.0:
            voice_settings["speed"] = max(0.5, min(speed, 2.0))
        if guidance != 1.0:
            voice_settings["guidance_scale"] = max(1.0, min(guidance, 10.0))
        if speaker_boost:
            voice_settings["use_speaker_boost"] = True
        if voice_settings:
            payload["voice_settings"] = voice_settings

        url = f"{base_url}/v1/text-to-speech/{voice_id}"
        headers = {"xi-api-key": api_key, "Content-Type": "application/json"}

        for attempt in range(retries + 1):
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    resp = await client.post(
                        url,
                        params={"output_format": out_fmt, "delivery": "sync"},
                        json=payload,
                        headers=headers,
                    )
            except httpx.TimeoutException:
                logger.warning(f"[breezeblue] 合成超时（第 {attempt + 1} 次）")
                continue
            except Exception as e:  # 网络/DNS 等
                logger.warning(f"[breezeblue] 合成请求异常：{type(e).__name__}")
                continue

            if resp.status_code == 200 and resp.content:
                ctype = resp.headers.get("content-type", "")
                raw_path = cached.with_suffix(".mp3" if "mpeg" in ctype else ".raw")
                raw_path.write_bytes(resp.content)
                if "mpeg" in ctype or out_fmt.startswith("mp3"):
                    if not self._to_wav(raw_path, cached):
                        logger.warning("[breezeblue] mp3 转 wav 失败（缺少 ffmpeg），回退文字")
                        return None
                    raw_path.unlink(missing_ok=True)
                    return cached
                if "wav" in ctype or out_fmt.startswith("wav"):
                    raw_path.replace(cached)
                    return cached
                # 其他编码（pcm/flac/opus）一律交给 ffmpeg
                if self._to_wav(raw_path, cached):
                    raw_path.unlink(missing_ok=True)
                    return cached
                return None

            if resp.status_code in (401, 403):
                logger.error(f"[breezeblue] 鉴权失败（HTTP {resp.status_code}），请检查 API Key / 权限")
                return None
            if resp.status_code == 429:
                logger.warning("[breezeblue] 触发限流（HTTP 429），本次回退文字")
                return None
            if resp.status_code == 202:
                logger.warning("[breezeblue] 服务端返回异步任务（202），当前插件只支持同步，回退文字")
                return None

            snippet = (resp.text or "")[:180].replace("\n", " ")
            logger.warning(f"[breezeblue] 合成失败 HTTP {resp.status_code}: {snippet}")
            if resp.status_code < 500:
                return None
        return None

    def _to_wav(self, src: Path, dst: Path) -> bool:
        ffmpeg = str(self._cfg("ffmpeg_path", "")).strip() or shutil.which("ffmpeg")
        if not ffmpeg:
            return False
        try:
            import subprocess

            subprocess.run(
                [ffmpeg, "-y", "-loglevel", "error", "-i", str(src), "-ar", "24000", "-ac", "1", str(dst)],
                check=True,
                timeout=30,
            )
            return dst.exists() and dst.stat().st_size > 1024
        except Exception as e:
            logger.warning(f"[breezeblue] ffmpeg 转换失败：{type(e).__name__}")
            return False

    # ------------------------------------------------------------ 触发判定

    def _platform_name(self, event: AstrMessageEvent) -> str:
        name = ""
        try:
            name = event.get_platform_name() or ""
        except Exception:
            pass
        if not name:
            meta = getattr(event, "platform_meta", None)
            name = getattr(meta, "name", "") or ""
        return name.lower()

    def _is_explicit(self, event: AstrMessageEvent) -> bool:
        keywords = self._cfg(
            "explicit_keywords",
            ["发语音", "语音说", "用语音", "说给我听", "念给我听", "voice"],
        )
        msg = (getattr(event, "message_str", "") or "").lower()
        return any(str(k).lower() in msg for k in keywords)

    # ------------------------------------------------------------ 送音频

    async def _record_component(self, path: Path) -> Comp.Record:
        """把本地音频变成 QQ 能取的 Record。

        AstrBot 与 NapCat/LLOneBot 不在同一容器时，本地路径对方读不到，
        必须走 AstrBot 的文件服务换成 HTTP URL（对应内置 TTS 的 use_file_service）。
        text 留空串：Record 自带 text 时会被别的 TTS 插件当成正文再合成一遍。
        """
        url = ""
        if bool(self._cfg("use_file_service", False)):
            try:
                from astrbot.core import file_token_service

                token = await file_token_service.register_file(str(path))
                base = ""
                try:
                    base = str(self.context.get_config().get("callback_api_base", "") or "")
                except Exception:
                    base = ""
                if base:
                    url = f"{base.rstrip('/')}/api/file/{token}"
            except Exception as e:
                logger.warning(f"[breezeblue] 文件服务注册失败，改用本地路径：{type(e).__name__}")
        target = url or str(path)
        return Comp.Record(file=target, url=target, text="")

    # ------------------------------------------------------------ 状态与测试指令

    def _usage_snapshot(self, umo: str) -> dict:
        data = self._load_usage()
        return {
            "total": int(data.get("total", 0)),
            "session": int(data.get("sessions", {}).get(umo, 0)),
        }

    @filter.command("bbvoice")
    async def bbvoice(self, event: AstrMessageEvent):
        """管理员测试入口：/bbvoice test 发测试句，/bbvoice status 看用量。"""
        if not bool(self._cfg("test_command_enabled", True)):
            return
        if not event.is_admin():
            yield event.plain_result("仅管理员可用。")
            return

        raw = (event.message_str or "").strip()
        arg = raw[len("/bbvoice") :].strip().lower() if raw.startswith("/bbvoice") else ""
        arg = arg.split()[0] if arg else "status"

        if arg == "status":
            data = self._usage_snapshot(event.unified_msg_origin)
            ratio = float(self._cfg("voice_ratio", 0.3))
            mode = "仅明确索要" if self._only_explicit() else f"随机 {ratio:.0%} 语音"
            has_key = "已配置" if self._api_key() else "未配置"
            yield event.plain_result(
                f"BreezeBlue：{'开' if bool(self._cfg('enabled', True)) else '关'}｜{mode}\n"
                f"音色 {self._cfg('voice_id', DEFAULT_VOICE_ID)}｜Key {has_key}\n"
                f"今日已用 {data['total']}/{int(self._cfg('daily_limit_global', 30))} 条"
                f"（单会话上限 {int(self._cfg('daily_limit_session', 10))}）"
            )
            return

        if arg != "test":
            yield event.plain_result("用法：/bbvoice test 或 /bbvoice status")
            return

        allowed = [str(g) for g in self._cfg("allowed_groups", [])]
        gid = ""
        try:
            gid = str(event.get_group_id() or "")
        except Exception:
            gid = ""
        if allowed and gid not in allowed:
            yield event.plain_result("当前会话不在 allowed_groups 里，测试已拦截。")
            return

        umo = event.unified_msg_origin
        if not await self._reserve_quota(umo):
            yield event.plain_result("今日语音额度已用完，测试未发送。")
            return
        audio = await self._synthesize(sanitize_for_tts(TEST_SENTENCE))
        if audio is None:
            await self._refund_quota(umo)
            yield event.plain_result("合成失败，未发送语音（详情见服务端日志，不会打印密钥）。")
            return
        yield event.chain_result([await self._record_component(audio)])

    # ------------------------------------------------------------ 主钩子

    @filter.on_decorating_result(priority=100)
    async def on_decorating_result(self, event: AstrMessageEvent):
        try:
            await self._maybe_replace_with_voice(event)
        except Exception as e:  # 永不因为本插件让消息发不出去
            logger.warning(f"[breezeblue] 处理失败，保持文字：{type(e).__name__}: {e}")

    def _only_explicit(self) -> bool:
        mode = str(self._cfg("trigger_mode", "ratio")).strip().lower()
        return bool(self._cfg("only_explicit", False)) or mode == "explicit"

    async def _maybe_replace_with_voice(self, event: AstrMessageEvent) -> None:
        if not bool(self._cfg("enabled", True)):
            return
        if event.get_extra("bbv_done"):
            return

        result = event.get_result()
        if result is None or not result.chain:
            return
        # 只处理模型回复；指令回执、工具结果、错误提示一律保持文字
        try:
            if not result.is_llm_result():
                return
        except Exception:
            pass
        chain = result.chain
        if any(isinstance(c, Comp.Record) for c in chain):
            return  # 已有语音（或别的 TTS 插件已处理），不重复

        platforms = [str(p).lower() for p in self._cfg("platforms", ["aiocqhttp"])]
        if platforms and self._platform_name(event) not in platforms:
            return

        allowed_groups = [str(g) for g in self._cfg("allowed_groups", [])]
        if allowed_groups:
            gid = ""
            try:
                gid = str(event.get_group_id() or "")
            except Exception:
                gid = ""
            if gid not in allowed_groups:
                return

        if str(getattr(event, "message_str", "") or "").lstrip().startswith("/"):
            return  # 指令回执不发语音

        text = "".join(
            getattr(c, "text", "") for c in chain if isinstance(c, Comp.Plain)
        ).strip()
        if not text:
            return

        if bool(self._cfg("skip_if_media", True)) and any(
            isinstance(c, (Comp.Image, Comp.Video, Comp.File)) for c in chain
        ):
            return

        clean = sanitize_for_tts(text)
        if len(clean) < int(self._cfg("min_chars", 2)):
            return
        if len(clean) > int(self._cfg("max_chars", 60)):
            return  # 长回复保留文字
        if clean.count("\n") > int(self._cfg("max_lines", 3)):
            return

        explicit = self._is_explicit(event)
        if explicit:
            pass  # 明确要求语音：跳过概率与冷却，但仍受长度/额度限制
        else:
            if self._only_explicit():
                return
            ratio = float(self._cfg("voice_ratio", 0.3))
            if random.random() >= ratio:
                return
            cooldown = int(self._cfg("cooldown_seconds", 90))
            umo_key = event.unified_msg_origin
            last = self._last_voice_at.get(umo_key, 0)
            if cooldown > 0 and time.time() - last < cooldown:
                return

        umo = event.unified_msg_origin
        if not await self._reserve_quota(umo):
            return

        audio = await self._synthesize(clean)
        if audio is None:
            await self._refund_quota(umo)
            return  # 静默回退文字

        event.set_extra("bbv_done", True)
        self._last_voice_at[umo] = time.time()

        kept = [c for c in chain if not isinstance(c, Comp.Plain)]
        kept.append(await self._record_component(audio))
        chain[:] = kept

        logger.info(
            f"[breezeblue] 已发送语音 voice={self._cfg('voice_id', DEFAULT_VOICE_ID)} "
            f"chars={len(clean)} explicit={explicit}"
        )

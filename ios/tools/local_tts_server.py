#!/usr/bin/env python3
"""
本地 TTS 服务（完全免费，无任何云端计费路径）
- 引擎：edge-tts（微软神经音色，无需 API Key、免费）
- 监听：0.0.0.0:9880 —— 模拟器走 127.0.0.1，真机走 Mac 局域网 IP（同一 Wi-Fi）
- Bonjour：注册 _edgetts._tcp，iPhone App 自动发现本服务，无需手输 IP
- 接口：
    GET  /health -> {"status":"ok",...}
    POST /tts    {"text":"...","voice":"zh-CN-YunxiNeural","rate":"+0%","pitch":"+0Hz"} -> audio/mpeg
启动：bash ios/tools/start-tts.sh
"""
import asyncio
import json
import os
import socket
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import edge_tts

HOST = "0.0.0.0"
PORT = 9880
DEFAULT_VOICE = "zh-CN-YunxiNeural"


def lan_ip() -> str:
    """取真实局域网 IP：优先 Wi-Fi 网卡（en0/en1），避免 VPN/代理 TUN 虚拟网卡的假 IP（如 198.18.0.1）"""
    import subprocess
    for ifname in ("en0", "en1", "en2"):
        try:
            ip = subprocess.run(
                ["ipconfig", "getifaddr", ifname],
                capture_output=True, text=True, timeout=3
            ).stdout.strip()
            if ip:
                return ip
        except Exception:
            pass
    # 兜底：路由探测（可能拿到 TUN 假 IP，仅当物理网卡都失败时使用）
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def register_bonjour():
    """注册 Bonjour 服务，iPhone 端 NWBrowser 自动发现。失败不影响 HTTP 服务。"""
    try:
        from zeroconf import ServiceInfo, Zeroconf
    except ImportError:
        print("[bonjour] 未安装 zeroconf（pip install zeroconf），App 将需要手输 IP")
        return None
    ip = lan_ip()
    info = ServiceInfo(
        "_edgetts._tcp.local.",
        f"Yetan TTS @{socket.gethostname()}._edgetts._tcp.local.",
        addresses=[socket.inet_aton(ip)],
        port=PORT,
        properties={"engine": "edge-tts", "path": "/tts"},
        server=f"{socket.gethostname().replace(' ', '-')}.local.",
    )
    zc = Zeroconf()
    zc.register_service(info)
    print(f"[bonjour] 已注册 _edgetts._tcp（{ip}:{PORT}），iPhone 打开 App 即自动发现")
    return zc


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 安静日志
        print("[tts]", fmt % args)

    # ---------- helpers ----------
    def _send_json(self, obj, status=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_mp3(self, path):
        size = os.path.getsize(path)
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(path, "rb") as f:
            while chunk := f.read(64 * 1024):
                self.wfile.write(chunk)
    # ---------- routes ----------
    def do_GET(self):
        if self.path in ("/health", "/"):
            self._send_json({"status": "ok", "engine": "edge-tts (local, free)"})
        else:
            self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path != "/tts":
            self._send_json({"error": "not found"}, 404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception as exc:
            self._send_json({"error": f"bad json: {exc}"}, 400)
            return

        text = (body.get("text") or "").strip()
        if not text:
            self._send_json({"error": "text is empty"}, 400)
            return
        voice = body.get("voice") or DEFAULT_VOICE
        rate = body.get("rate") or "+0%"
        pitch = body.get("pitch") or "+0Hz"

        async def synth(out_path):
            com = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
            await com.save(out_path)

        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(suffix=".mp3")
            os.close(fd)
            asyncio.run(synth(tmp))
            if os.path.getsize(tmp) == 0:
                raise RuntimeError("empty audio")
            self._send_mp3(tmp)
        except (BrokenPipeError, ConnectionResetError):
            # 客户端中途取消（用户切到别的音色）：正常现象，静默忽略
            self.close_connection = True
        except Exception as exc:
            try:
                self._send_json({"error": str(exc)}, 500)
            except (BrokenPipeError, ConnectionResetError):
                pass
        finally:
            if tmp:
                try:
                    os.remove(tmp)
                except OSError:
                    pass


if __name__ == "__main__":
    ip = lan_ip()
    zc = register_bonjour()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("=" * 60)
    print(f"[local-tts] edge-tts 服务已启动（免费、无 Key、无云端请求）")
    print(f"  模拟器 App 地址 : http://127.0.0.1:{PORT}")
    print(f"  真机 App 地址   : http://{ip}:{PORT}   ← 同一 Wi-Fi")
    print(f"  真机一般无需手输：Bonjour 会自动发现")
    print("=" * 60)
    try:
        server.serve_forever()
    finally:
        if zc:
            zc.unregister_service(zc.service if hasattr(zc, 'service') else None) if False else zc.close()

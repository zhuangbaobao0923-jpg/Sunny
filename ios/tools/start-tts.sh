#!/bin/bash
# 启动本地 TTS 服务（0.0.0.0:9880，完全免费、无 API Key）
# 模拟器走 127.0.0.1:9880；真机走 Mac 局域网 IP:9880（Bonjour 自动发现，一般无需手输）
cd "$(dirname "$0")"
python3 -c "import edge_tts" 2>/dev/null || python3 -m pip install --quiet --user edge-tts
python3 -c "import zeroconf" 2>/dev/null || python3 -m pip install --quiet --user zeroconf
exec python3 local_tts_server.py

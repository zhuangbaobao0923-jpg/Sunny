# BreezeBlue 语音回复插件（AstrBot v4）

在 **发送前** 把文字回复按概率换成 BreezeBlue 云端 TTS 语音条。不改模型、不设人设、不动记忆和 QQ 连接。

> v0.2.0：钩子 priority 提到 100（避免与 clonetts 同一句合成两次）、Record.text 置空、只处理 LLM 结果、新增 use_file_service、voice_settings、`/bbvoice` 管理员测试指令。

## 0. 先说清楚：哪些已核实，哪些没核实

| 项 | 状态 |
|---|---|
| BreezeBlue 接口路径/鉴权/参数 | 已按官方 openapi.json 核实：`POST https://api.breeze.blue/v1/text-to-speech/{voice_id}`，请求头 `xi-api-key`，`delivery=sync|async` |
| 输出格式 | 已核实：`wav_24000` = 24 kHz / 16-bit / 单声道，`mp3` 默认 128 kbps |
| 单次文本上限 | 已核实：默认 1000 字符，申请后可到 2000；本插件默认只转 ≤60 字 |
| 计费 | 已核实：10 units = 1 credit；中日韩字符每字 2 units；$3 / 万 credits |
| `voc_8yud7hz7c9q2` 属于你的账号 | **未核实**，需要带 Key 调 `GET /v1/voices` 才能确认 |
| 你的 AstrBot 版本 / 适配器 / 已有 TTS 插件 | **未核实**，本机没有部署、没有 Docker、没有远程入口 |
| aiocqhttp 能否发 `wav_24000` 语音条 | **未核实**，需按第 4 节实测 |
| 手机 / 电脑播放效果 | **未核实** |

> 本插件**无法**通过"把本地 TTS 的地址和 Key 换掉"来接入。原因：AstrBot 内置 TTS 走的是 OpenAI 风格 `/audio/speech` 或各家专用 Provider，BreezeBlue 是 `xi-api-key` + `voice_settings` + 路径带 voice_id 的另一套协议；内置 Provider 不会因为改 base_url 就兼容。所以这里用插件在 `on_decorating_result` 阶段直接换成 `Comp.Record`，绕开 TTS Provider 抽象。

## 1. 安装

```bash
# 在 AstrBot 机器上（Docker 则 docker cp 进容器）
scp -r astrbot_plugin_breezeblue_voice <user>@<host>:/path/to/AstrBot/data/plugins/
# Docker:
docker cp astrbot_plugin_breezeblue_voice astrbot:/AstrBot/data/plugins/
```

然后在 WebUI → 插件 → 刷新/重载，看到 `BreezeBlue 语音回复` 即加载成功。

依赖：`httpx`（AstrBot 自带，若缺则 `pip install -r requirements.txt`）。

## 2. 配置（密钥只进这里）

WebUI → 插件 → BreezeBlue 语音回复 → 配置：

| 键 | 建议值 | 说明 |
|---|---|---|
| `api_key` | 你的 Key | 界面已遮罩；也可改用环境变量 `BREEZE_API_KEY`，二者取其一 |
| `voice_id` | `voc_8yud7hz7c9q2` | 默认已填 |
| `voice_ratio` | `0.3` | 30% 语音 / 70% 文字 |
| `only_explicit` | `false` | 设 `true` 就回到"只在明确索要时发" |
| `explicit_keywords` | 默认 | 命中即 100% 语音，不需要 `/语音` 指令 |
| `max_chars` | `60` | 超过就保留文字 |
| `daily_limit_global` | `30` | 全局每日上限 |
| `daily_limit_session` | `10` | 单会话每日上限 |
| `cooldown_seconds` | `90` | 同会话两条语音的最小间隔；群聊想接近 30% 建议 45 |
| `allowed_groups` | 测试群号 | **首测必填**，只让一个群生效 |
| `use_file_service` | `true` | AstrBot 与 NapCat 分容器时必开，否则对方读不到本地音频 |
| `speed` | `1.0` | 变调不变音；夜谈语气建议 `0.95` |
| `guidance_scale` | `1.0` | 表现力强度，填了 `instructions` 可试 `2–4` |

Docker 用环境变量的写法（不要把 Key 写进 compose 文件后提交仓库）：

```bash
docker run ... -e BREEZE_API_KEY="$(cat /etc/astrbot/breeze.key)" ...
```

改完保存即生效，无需重启（插件每轮读取配置）。

## 3. 先算测试用量

测试句：`呜哇，被你发现啦! 我在认真思考呢，才没有摸鱼。`

- 清洗后 **24 字符**（双空格合并），1 次同步请求
- 计费：19 个汉字 ×2 + 5 个非汉字 = **43 units = 4.3 credits**，约 1 分钱
- 预期音频 4–6 秒，`wav_24000` 约 200–300 KB
- 重试上限 1 次 ⇒ 最坏 2 次请求、86 units
- 当日配额默认 30 条，本次只占 1 条

官方计价：10 units = 1 credit，$3 / 10,000 credits（折合 $30 / 100 万字符，中日韩字符按双倍计）。

## 4. 三步验收

### A. 只验音频生成（不碰 QQ）

```bash
export BREEZE_API_KEY='...'   # 不要写进命令历史；用 read -s
python3 tools/test_api.py --voices   # 确认 Voice ID 存在 + 看名字/语言/性别
python3 tools/test_api.py            # 生成 breeze_test.wav
ffprobe -v error -show_entries format=duration -of default=nw=1 breeze_test.wav
```

通过标准：HTTP 200、`content-type: audio/wav`、时长 > 1s、人声是普通话女声（以实际 Voice 为准）。

### B. 只验 QQ 送达

1. 配置 `allowed_groups: ["<测试群号>"]`、`daily_limit_global: 1`、`use_file_service` 按部署形态设置
2. 管理员在测试群发 `/bbvoice test`
3. 预期：群里收到 **1 条语音**，内容就是测试句，没有重复文字

> 没有管理员权限时，退回概率法：`voice_ratio: 1.0` + 额度 1，在群里说一句"在吗"，让回复被转成语音。

群号获取：在该群发 `/sid`，返回的 `default:GroupMessage:xxxx` 里 `xxxx` 就是群号。

### C. 手机 + 电脑播放

- 手机 QQ：点语音条能播、有波形、时长正确、无杂音/变速
- 电脑 QQ：同上
- 两端都通过才算"完整播放"；只有一端通过按未通过记

### D. 恢复常态

`voice_ratio: 0.3`、`allowed_groups: []`（或保留测试群先观察）、`daily_limit_global: 30`。

## 5. 启用 / 停用 / 回退

**启用**：插件配置 `enabled: true` + 填 Key。

**临时停用（推荐，秒级）**：`enabled: false`。插件仍在，只是不再替换，文字照发。

**彻底停用**：WebUI 插件页 → 停用（或卸载）。

**回退到改动前**：

```bash
# 备份（改动前做一次）
cd /path/to/AstrBot
tar czf ~/astrbot-backup-$(date +%F-%H%M).tgz \
  data/config/astrbot_plugin_breezeblue_voice_config.json \
  data/plugin_data/astrbot_plugin_breezeblue_voice 2>/dev/null

# 回退
rm -rf data/plugins/astrbot_plugin_breezeblue_voice
rm -f  data/config/astrbot_plugin_breezeblue_voice_config.json
docker restart astrbot     # 或 WebUI 重载插件
```

原有 `data/config/*` 的模型/人设/平台配置本插件**只读不写**，回退不需要动它们。

## 6. 行为细节

- **只替换，不追加**：文字组件被移除后放 `Comp.Record`，不会"先文字后语音"发两条
- **不与别的 TTS 抢**：钩子 priority=100 先执行；链里已有 `Record` 直接跳过；`Record.text` 为空串，避免 clonetts 二次合成
- **只念模型回复**：`result.is_llm_result()` 为假时不动，指令回执/工具结果保持文字
- **失败静默回退**：401/403/429/5xx/超时/ffmpeg 缺失 → 原文字照发，不提示、不重发
- **管理指令**：`/bbvoice test` 精确发一条测试句，`/bbvoice status` 看今日用量；仅管理员，受 `allowed_groups` 与额度约束
- **缓存**：同文本命中本地缓存不重复计费，默认留 7 天
- **额度**：先占额度再合成，失败退还

## 7. 音色不对怎么换

先分层定位，别直接换 voice：

1. **同一句话，本地播 wav vs QQ 里播语音条**。QQ 里明显更闷/更金属 → 是 NapCat 把 24 kHz WAV 转成低码率 AMR/SILK，换音色没用，先调转码或改用 `mp3_24000_160`。
2. 本地也难听 → 先调语气：`instructions` 填「中文，年轻女声，轻快亲近，像跟朋友聊天，不要播音腔」。念得平常常被误判成音色差。
3. 仍然不行 → 换音色。用试听器，先免费听 preview，再用同一句话付费对比：

```bash
export BREEZE_API_KEY='...'
python3 tools/audition.py --list --gender female --age young
python3 tools/audition.py --preview 5 --tone warm --tone gentle --gender female
python3 tools/audition.py --pick 5 --tone playful --age young --gender female
```

`--preview` 不计费，`--pick` 按字符计费（5 个候选 × 24 字符 = 120 字符）。

4. 选定后只改 WebUI 的 `voice_id`，不用动代码。

## 8. 仍然未验证的环节

1. `voc_8yud7hz7c9q2` 是否属于该 Key（`--voices` 可证）
2. 你的 AstrBot 具体版本是否 ≥4.16、`on_decorating_result` 是否被别的插件抢先
3. aiocqhttp/NapCat 对 24 kHz WAV 的转码与时长显示
4. 官方 QQ 机器人适配器是否支持 `record`（文档矩阵有冲突）
5. 群内是否触发风控/限流
6. 手机、电脑两端实际听感
7. 真实计费单价与税（官方标价 $3/万 credits）
8. 服务器时区是否为中国时区（跨日额度按 `date.today()` 计算）
9. 流式输出开启时，钩子可能拿不到完整消息链（AstrBot 源码会 warning）
10. 是否还装着 clonetts / voice_input 等概率型 TTS 插件（preflight 会标出来）
11. 分容器部署下 `use_file_service` 是否可用（取决于 `callback_api_base` 配置）

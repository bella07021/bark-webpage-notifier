# Bark Webpage Notifier Skill

<p align="center">
  <a href="#中文"><strong>中文</strong></a>
  ·
  <a href="#english"><strong>English</strong></a>
</p>

## 中文

一个 Codex skill，用来把网页、搜索页、资讯列表里的新消息标题推送到 Bark iOS 通知，并支持 Bark 分组、去重和定时轮询。

## 功能

- 从 `.env` 读取 Bark key，避免把 key 写进脚本
- 支持 Bark 通知分组
- 提取消息标题，并清理网页高亮 HTML
- 只推送新增消息，避免重复通知
- 用本地 `seen_*.json` 记录已推送消息
- 支持先发测试推送，再正式开启监控

## 安装

把这个目录复制到 Codex skills 目录：

```bash
mkdir -p ~/.codex/skills
cp -R bark-webpage-notifier ~/.codex/skills/
```

之后新的 Codex 会话就可以使用 `bark-webpage-notifier` 这个 skill。

## 配置 Bark

在运行监控脚本的工作目录里创建 `.env`：

```bash
BARK_KEY=你的默认BarkKey
```

如果你有多个推送分组，建议使用主题专属变量：

```bash
BARK_KEY_BINANCE_ALPHA=你的BarkKey
BARK_GROUP_BINANCE_ALPHA=币安 alpha
CHAINCATCHER_KEYWORDS_BINANCE_ALPHA=币安 alpha

BARK_KEY_BINANCE_CONTRACT=你的BarkKey
BARK_GROUP_BINANCE_CONTRACT=币安合约
CHAINCATCHER_KEYWORDS_BINANCE_CONTRACT=币安合约将上线
```

可以填纯 Bark key，也可以直接粘 Bark App 里的完整测试 URL：

```text
https://api.day.app/your_key/测试消息
```

脚本会自动提取其中的 `your_key`。

## 使用方法

以下命令都在包含 `.env` 的工作目录里运行。

发送测试推送：

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --test-title "币安合约将上线测试消息"
```

初始化当前搜索结果为“已见过”，避免第一次运行时把旧消息全部推送：

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --init-seen
```

单次检查并推送新增标题：

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --once
```

## 通知格式

默认通知很清爽，只推标题：

```json
{
  "title": "币安合约",
  "body": "币安合约将上线某某代币",
  "group": "币安合约"
}
```

默认不带链接、不带副标题、不带摘要。如果需要这些字段，可以自行改脚本。

## 定时运行

确认测试推送成功，并执行过 `--init-seen` 后，可以用 cron、launchd 或其他定时器定期运行 `--once`。

cron 示例：每 3 分钟检查一次。

```cron
*/3 * * * * cd /path/to/workspace && python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py --topic binance-contract --once
```

## 注意事项

- 不要提交 `.env`
- 不要提交 `seen_*.json`
- 如果网页有验证码、人机验证或 Cloudflare challenge，优先寻找公开 API、RSS 或备用来源；浏览器自动化也许能跑，但长期定时监控稳定性会差很多

---

## English

A Codex skill for turning webpage/search-page updates into clean Bark iOS push notifications.

It is designed for pages where a stable API, SSR HTML, RSS feed, or embedded JSON can expose repeated message items. The default bundled helper script supports ChainCatcher search pages and sends title-only Bark notifications grouped by topic.

## What It Does

- Reads Bark keys from `.env`
- Supports Bark notification groups
- Extracts message titles and strips highlight HTML
- Pushes only new items
- Stores local seen-state to avoid duplicate pushes
- Supports a test push before live monitoring

## Install

Copy this folder into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
cp -R bark-webpage-notifier ~/.codex/skills/
```

After that, future Codex sessions can use the `bark-webpage-notifier` skill.

## Configure Bark

Create a `.env` file in the workspace where you run the monitor:

```bash
BARK_KEY=your_default_bark_key
```

For multiple notification groups, use topic-specific variables:

```bash
BARK_KEY_BINANCE_ALPHA=your_bark_key
BARK_GROUP_BINANCE_ALPHA=币安 alpha
CHAINCATCHER_KEYWORDS_BINANCE_ALPHA=币安 alpha

BARK_KEY_BINANCE_CONTRACT=your_bark_key
BARK_GROUP_BINANCE_CONTRACT=币安合约
CHAINCATCHER_KEYWORDS_BINANCE_CONTRACT=币安合约将上线
```

You can paste either a pure Bark key or a full Bark App URL such as:

```text
https://api.day.app/your_key/测试消息
```

The helper script will normalize it to `your_key`.

## Usage

Run commands from the workspace that contains your `.env`.

Send a test push:

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --test-title "币安合约将上线测试消息"
```

Initialize current search results as already seen, without pushing old items:

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --init-seen
```

Push new titles once:

```bash
python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py \
  --topic binance-contract \
  --once
```

## Notification Format

The default notification is intentionally clean:

```json
{
  "title": "币安合约",
  "body": "币安合约将上线某某代币",
  "group": "币安合约"
}
```

No URL, subtitle, or summary is included unless you customize the script.

## Scheduling

After the test push works and `--init-seen` has been run, schedule `--once` with your preferred scheduler.

Example cron entry for every 3 minutes:

```cron
*/3 * * * * cd /path/to/workspace && python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py --topic binance-contract --once
```

## Notes

- Do not commit `.env`.
- Do not commit `seen_*.json` state files.
- If a site is blocked by captcha or human verification, prefer finding a public API, RSS feed, or alternate source. Browser automation can work, but it is less stable for recurring monitors.

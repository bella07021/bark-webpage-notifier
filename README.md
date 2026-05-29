# Bark Webpage Notifier Skill

<p align="center">
  <a href="#中文"><strong>中文</strong></a>
  ·
  <a href="#english"><strong>English</strong></a>
</p>

## 中文

一个 Codex skill，用来把网页、搜索页、资讯列表里的新消息标题推送到 Bark iOS 通知，并支持 Bark 分组、去重和定时轮询。

## 一键开始

### 只安装 Skill

在终端运行：

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/install_skill.sh | bash
```

然后重开 Codex，就可以直接说：

```text
用 bark-webpage-notifier 帮我监控这个网页，并推送到 Bark
```

### 让它在 GitHub Actions 云端运行

如果你希望关电脑后也继续轮询：

1. Fork 或 clone 这个仓库。
2. 确认已安装并登录 GitHub CLI：`gh auth login`。
3. 在仓库目录运行：

```bash
scripts/setup_github_actions.sh
```

4. 打开 GitHub：

```text
Actions -> Bark Webpage Watch -> Run workflow
```

脚本会帮你复制 workflow、写入 Bark key 到 GitHub Secrets，并在可以时自动 commit/push。workflow 默认每 5 分钟检查一次；第一次运行只记录旧消息，后面才推送新增标题。

## 功能

- 从 `.env` 读取 Bark key，避免把 key 写进脚本
- 支持 Bark 通知分组
- 提取消息标题，并清理网页高亮 HTML
- 只推送新增消息，避免重复通知
- 用本地 `seen_*.json` 记录已推送消息
- 支持用 GitHub Actions 云端定时运行
- 支持先发测试推送，再正式开启监控

## 手动安装

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

## 手动配置 GitHub Actions

如果希望电脑关机后也能继续推送，可以把脚本放在 GitHub 仓库里，用 GitHub Actions 定时运行。几分钟级别的监控很适合这种方式。

更省事的方式是直接运行：

```bash
scripts/setup_github_actions.sh
```

### 1. 添加 Bark key 到 Secrets

进入你的 GitHub 仓库：

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

添加：

```text
Name: BARK_KEY_BINANCE_CONTRACT
Secret: 你的 Bark key
```

如果还要监控币安 alpha，再添加：

```text
Name: BARK_KEY_BINANCE_ALPHA
Secret: 你的 Bark key
```

### 2. 复制 workflow 示例

把示例文件复制到仓库的 workflow 目录：

```bash
mkdir -p .github/workflows
cp examples/github-actions/chaincatcher-bark.yml .github/workflows/bark-web-watch.yml
```

示例 workflow 每 5 分钟运行一次，也支持手动触发：

```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: "*/5 * * * *"
```

### 3. 第一次运行

推送 workflow 到 GitHub 后，进入：

```text
Actions -> Bark Webpage Watch -> Run workflow
```

第一次运行会建立 `.bark-state` 缓存，只记录当前标题，不推送旧消息。之后定时任务只会推送新增标题。

### 4. 修改监控主题

如果要改成别的主题，修改 workflow 里的环境变量：

```yaml
env:
  BARK_KEY_BINANCE_CONTRACT: ${{ secrets.BARK_KEY_BINANCE_CONTRACT }}
  BARK_GROUP_BINANCE_CONTRACT: 币安合约
  CHAINCATCHER_KEYWORDS_BINANCE_CONTRACT: 币安合约将上线
  STATE_PATH_BINANCE_CONTRACT: .bark-state/seen_binance_contract.json
```

GitHub Actions 的 `schedule` 不是秒级实时任务，可能有几分钟延迟，这是正常的。

## 注意事项

- 不要提交 `.env`
- 不要提交 `seen_*.json`
- 如果网页有验证码、人机验证或 Cloudflare challenge，优先寻找公开 API、RSS 或备用来源；浏览器自动化也许能跑，但长期定时监控稳定性会差很多

---

## English

A Codex skill for turning webpage/search-page updates into clean Bark iOS push notifications.

It is designed for pages where a stable API, SSR HTML, RSS feed, or embedded JSON can expose repeated message items. The default bundled helper script supports ChainCatcher search pages and sends title-only Bark notifications grouped by topic.

## Quick Start

### Install The Skill

Run this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/install_skill.sh | bash
```

Restart Codex, then ask:

```text
Use bark-webpage-notifier to monitor this page and push new titles to Bark.
```

### Run It In GitHub Actions

If you want polling to continue while your computer is off:

1. Fork or clone this repository.
2. Make sure GitHub CLI is installed and logged in: `gh auth login`.
3. Run this from the repository directory:

```bash
scripts/setup_github_actions.sh
```

4. Open GitHub:

```text
Actions -> Bark Webpage Watch -> Run workflow
```

The script copies the workflow, saves Bark keys as GitHub Secrets, and commits/pushes the workflow when possible. The workflow checks every 5 minutes; the first run records old titles, and later runs push only new titles.

## What It Does

- Reads Bark keys from `.env`
- Supports Bark notification groups
- Extracts message titles and strips highlight HTML
- Pushes only new items
- Stores local seen-state to avoid duplicate pushes
- Supports GitHub Actions scheduled cloud runs
- Supports a test push before live monitoring

## Manual Install

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

## Manual GitHub Actions Setup

If you want the monitor to keep running after your computer is off, run it on GitHub Actions. This is a good fit for checks every few minutes.

The easiest path is:

```bash
scripts/setup_github_actions.sh
```

### 1. Add Your Bark Key As A Secret

Open your GitHub repository:

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

Add:

```text
Name: BARK_KEY_BINANCE_CONTRACT
Secret: your Bark key
```

To also monitor Binance alpha, add:

```text
Name: BARK_KEY_BINANCE_ALPHA
Secret: your Bark key
```

### 2. Copy The Workflow Example

Copy the bundled example into your workflow directory:

```bash
mkdir -p .github/workflows
cp examples/github-actions/chaincatcher-bark.yml .github/workflows/bark-web-watch.yml
```

The example runs every 5 minutes and also supports manual runs:

```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: "*/5 * * * *"
```

### 3. First Run

After pushing the workflow, open:

```text
Actions -> Bark Webpage Watch -> Run workflow
```

The first run creates a `.bark-state` cache and records current titles without pushing old items. Later scheduled runs only push new titles.

### 4. Change The Topic

Edit the workflow env block for a different topic:

```yaml
env:
  BARK_KEY_BINANCE_CONTRACT: ${{ secrets.BARK_KEY_BINANCE_CONTRACT }}
  BARK_GROUP_BINANCE_CONTRACT: 币安合约
  CHAINCATCHER_KEYWORDS_BINANCE_CONTRACT: 币安合约将上线
  STATE_PATH_BINANCE_CONTRACT: .bark-state/seen_binance_contract.json
```

GitHub Actions schedules are not real-time; delays of a few minutes are normal.

## Notes

- Do not commit `.env`.
- Do not commit `seen_*.json` state files.
- If a site is blocked by captcha or human verification, prefer finding a public API, RSS feed, or alternate source. Browser automation can work, but it is less stable for recurring monitors.

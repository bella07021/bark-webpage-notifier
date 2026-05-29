# Bark Webpage Notifier

<p align="center">
  <a href="#中文"><strong>中文</strong></a>
  ·
  <a href="#english"><strong>English</strong></a>
</p>

## 中文

把网页、搜索页、资讯列表里的新消息标题推送到 Bark iOS 通知，并支持 Bark 分组、去重和 GitHub Actions 云端定时轮询。

## 一键开始

默认推荐用 GitHub Actions 云端运行。这样电脑关机后也能继续推送，不需要一直打开 Codex。

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
```

脚本会带你完成：

- 创建或更新一个 GitHub 仓库
- 添加 Bark key 到 GitHub Secrets
- 推送 GitHub Actions workflow
- 启动第一次 workflow

运行前只需要准备好：

- GitHub 账号
- GitHub CLI，并已登录：`gh auth login`
- Bark App 里的 key，或者完整 Bark 测试 URL

第一次 workflow 只记录当前旧消息，不会推送历史标题；之后默认每 5 分钟检查一次，只推送新增标题。

## Codex Skill 是可选的

这个项目有两层：

- GitHub Actions workflow：真正负责云端定时轮询和推送，普通用户默认只需要这个
- Codex skill：给 Codex 用的辅助能力，方便你以后让 Codex 添加新网页、改关键词、改通知格式

如果只想让推送跑起来，不需要安装 skill，也不需要一直打开 Codex。

如果你想把这个能力安装到 Codex 里，再运行：

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/install_skill.sh | bash
```

然后重开 Codex，就可以说：

```text
用 bark-webpage-notifier 帮我监控这个网页，并推送到 Bark
```

## 功能

- 从 `.env` 读取 Bark key，避免把 key 写进脚本
- 支持 Bark 通知分组
- 提取消息标题，并清理网页高亮 HTML
- 只推送新增消息，避免重复通知
- 用本地 `seen_*.json` 记录已推送消息
- 支持用 GitHub Actions 云端定时运行
- 支持先发测试推送，再正式开启监控

## 本地手动安装 Skill

把这个目录复制到 Codex skills 目录：

```bash
mkdir -p ~/.codex/skills
cp -R bark-webpage-notifier ~/.codex/skills/
```

之后新的 Codex 会话就可以使用 `bark-webpage-notifier` 这个 skill。

## 本地运行（可选）

下面这些命令只适合想在自己电脑上调试或本地定时运行的人。普通用户使用上面的 GitHub Actions 一键脚本即可。

### 配置 Bark

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

### 使用方法

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

### 定时运行

确认测试推送成功，并执行过 `--init-seen` 后，可以用 cron、launchd 或其他定时器定期运行 `--once`。

cron 示例：每 3 分钟检查一次。

```cron
*/3 * * * * cd /path/to/workspace && python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py --topic binance-contract --once
```

## 手动配置 GitHub Actions

如果希望电脑关机后也能继续推送，可以把脚本放在 GitHub 仓库里，用 GitHub Actions 定时运行。几分钟级别的监控很适合这种方式。

从零开始最省事的方式是：

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
```

如果你已经 clone 或 fork 了这个仓库，也可以在仓库目录运行：

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

A GitHub Actions based Bark notifier for turning webpage/search-page updates into clean iOS push notifications.

It is designed for pages where a stable API, SSR HTML, RSS feed, or embedded JSON can expose repeated message items. The default helper script supports ChainCatcher search pages and sends title-only Bark notifications grouped by topic. The optional Codex skill helps customize monitors later.

## Quick Start

The default setup runs in GitHub Actions, so polling continues even when your computer and Codex are closed.

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
```

The script guides you through:

- creating or updating a GitHub repository
- saving Bark keys as GitHub Secrets
- pushing the GitHub Actions workflow
- starting the first workflow run

Before running it, prepare:

- a GitHub account
- GitHub CLI, logged in with `gh auth login`
- your Bark key, or the full Bark test URL from the Bark app

The first workflow run records current old titles without pushing them. Later runs check every 5 minutes by default and push only new titles.

## The Codex Skill Is Optional

This project has two layers:

- GitHub Actions workflow: does the actual cloud polling and Bark pushing
- Codex skill: helps Codex add pages, change keywords, or adjust notification behavior later

You do not need to install the skill or keep Codex open if you only want cloud notifications.

To install the optional Codex skill:

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/install_skill.sh | bash
```

Restart Codex, then ask:

```text
Use bark-webpage-notifier to monitor this page and push new titles to Bark.
```

## What It Does

- Reads Bark keys from `.env`
- Supports Bark notification groups
- Extracts message titles and strips highlight HTML
- Pushes only new items
- Stores local seen-state to avoid duplicate pushes
- Supports GitHub Actions scheduled cloud runs
- Supports a test push before live monitoring

## Manual Skill Install

Copy this folder into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
cp -R bark-webpage-notifier ~/.codex/skills/
```

After that, future Codex sessions can use the `bark-webpage-notifier` skill.

## Local Run Optional

These commands are for local debugging or local scheduling. Most users can use the GitHub Actions quick start above.

### Configure Bark

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

### Usage

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

### Scheduling

After the test push works and `--init-seen` has been run, schedule `--once` with your preferred scheduler.

Example cron entry for every 3 minutes:

```cron
*/3 * * * * cd /path/to/workspace && python3 ~/.codex/skills/bark-webpage-notifier/scripts/bark_web_watch.py --topic binance-contract --once
```

## Manual GitHub Actions Setup

If you want the monitor to keep running after your computer is off, run it on GitHub Actions. This is a good fit for checks every few minutes.

From zero, the easiest path is:

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
```

If you already cloned or forked this repository, run this from the repository directory:

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

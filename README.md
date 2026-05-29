# Bark Webpage Notifier Skill

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

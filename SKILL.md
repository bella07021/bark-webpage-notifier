---
name: bark-webpage-notifier
description: Use when a user wants to monitor a webpage, search page, news list, RSS-like feed, or JSON API and push new message titles to Bark/iOS, especially with Bark notification groups, environment-variable keys, de-duplication, test pushes, or scheduled polling.
---

# Bark Webpage Notifier

## Overview

Create small local monitors that poll a webpage or API, extract new message titles, and push title-only Bark notifications into the requested group. Keep keys in `.env`, keep state in a local seen-file, and verify with a harmless test push before scheduling.

## Workflow

1. Confirm the exact source URL, search keywords, Bark group name, and whether the user wants title-only or richer notifications. Default to title-only: `{"title": group, "body": item_title, "group": group}` with no `url`.
2. Inspect the page before coding. Prefer a stable JSON/API endpoint over DOM parsing. For Nuxt pages, search `window.__NUXT__`, bundled JS, and network-like endpoints such as `/search/list`.
3. Create or update a local script that:
   - reads `BARK_KEY` or a topic-specific key from `.env`
   - normalizes a full Bark URL into just the key
   - fetches the source
   - strips HTML/highlight spans from titles
   - stores seen item IDs in a topic-specific state file
   - pushes only unseen items
4. Add `.env.example` entries and `.gitignore` entries for `.env` and state files. Never print or commit Bark keys.
5. Test in this order:
   - parser/unit tests
   - `.env` variable presence without printing values
   - Bark `--test-title`
   - `--init-seen` to mark current historical items as seen before live polling
   - `--once` to verify no old-message flood
6. Only after the user confirms the test push, set up a recurring run with the app automation tool, launchd, cron, or another scheduler the user prefers.

## Recommended Files

For a workspace monitor, use:

```text
.env
.env.example
.gitignore
watcher.py
test_watcher.py
seen_<topic>.json
```

Use topic-specific env vars when multiple Bark groups exist:

```bash
BARK_KEY=default_key
BARK_KEY_BINANCE_CONTRACT=optional_topic_key
BARK_GROUP_BINANCE_CONTRACT=币安合约
CHAINCATCHER_KEYWORDS_BINANCE_CONTRACT=币安合约将上线
```

If the topic key is missing, it is usually okay to fall back to `BARK_KEY` and still use the topic-specific group.

## ChainCatcher Pattern

For ChainCatcher search pages like:

```text
https://www.chaincatcher.com/search?search=<encoded keywords>
```

Prefer the API:

```text
POST https://www.api.chaincatcher.com/pc/search/list
{"keywords":"币安 alpha","pageNumber":1,"pageSize":10}
```

Use `data.items[].id` for de-duplication and `data.items[].title` for the notification body. Titles can contain nested highlight HTML; strip all tags and collapse whitespace before pushing.

## Bark Payload

For clean grouped notifications, send only:

```json
{
  "title": "币安 alpha",
  "body": "币安 Alpha 将于 5 月 26 日上线 Citrea(CTR)",
  "group": "币安 alpha"
}
```

Do not include `url`, `subtitle`, or page excerpts unless the user explicitly asks.

## Commands

Use the bundled script as a starting point when the source fits ChainCatcher-style search:

```bash
python3 scripts/bark_web_watch.py --topic alpha --init-seen
python3 scripts/bark_web_watch.py --topic alpha --test-title "测试标题"
python3 scripts/bark_web_watch.py --topic alpha --once
```

For a new topic, prefer explicit variables:

```bash
BARK_KEY_MY_TOPIC=...
BARK_GROUP_MY_TOPIC=...
CHAINCATCHER_KEYWORDS_MY_TOPIC=...
```

Then run:

```bash
python3 scripts/bark_web_watch.py --topic my-topic --init-seen
python3 scripts/bark_web_watch.py --topic my-topic --once
```

## Common Mistakes

- Do not `source .env` blindly when values contain spaces or non-ASCII text. Parse key/value lines or use a dotenv parser.
- Do not log full command lines that include Bark keys. Catch curl errors and print sanitized messages.
- Do not run live polling before `--init-seen`; otherwise the first run can push old search results.
- Do not infer the page title from meta tags. Extract the repeated result item title from the API or rendered list.

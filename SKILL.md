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
   - also reads GitHub Actions environment variables/Secrets when no `.env` exists
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
   - `--init-if-empty` for GitHub Actions so the first cloud run records current items without pushing old messages
   - `--once` to verify no old-message flood
6. Only after the user confirms the test push, set up a recurring run with GitHub Actions, the app automation tool, launchd, cron, or another scheduler the user prefers. For GitHub Actions, store Bark keys in repository Secrets and persist `seen_*.json` with `actions/cache`.

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
SOURCE_BINANCE_CONTRACT=odaily-newsflash
KEYWORDS_BINANCE_CONTRACT=币安合约将上线
```

If the topic key is missing, it is usually okay to fall back to `BARK_KEY` and still use the topic-specific group.

## Built-In Sources

Use a built-in source whenever possible so ordinary users can configure monitoring without writing parser code:

```text
chaincatcher-search
odaily-newsflash
panews-rss
coindesk-rss
```

`chaincatcher-search`, `odaily-newsflash`, and `panews-rss` are suitable for Chinese crypto news keywords. `coindesk-rss` is suitable for English keywords. For RSS/newsflash sources, the script fetches the latest list and filters titles/descriptions locally with `KEYWORDS_<TOPIC>`.

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

For one-command skill installation from GitHub, use:

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/install_skill.sh | bash
```

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
SOURCE_MY_TOPIC=odaily-newsflash
KEYWORDS_MY_TOPIC=...
```

Then run:

```bash
python3 scripts/bark_web_watch.py --topic my-topic --init-seen
python3 scripts/bark_web_watch.py --topic my-topic --once
```

## GitHub Actions

Use GitHub Actions when the monitor must keep running after the user's computer shuts down. Add a workflow under `.github/workflows/` rather than relying on local cron.

For public end-user onboarding, default to the guided cloud setup instead of asking users to install the Codex skill:

```bash
curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
```

Clarify that installing the Codex skill is optional: GitHub Actions does the actual scheduled polling, while the skill only helps Codex modify or extend monitors later.

Required patterns:

- Put Bark keys in repository Secrets, for example `BARK_KEY_BINANCE_CONTRACT`.
- Set group, keywords, and state path as workflow environment variables.
- Restore and save `.bark-state` with `actions/cache/restore@v4` and `actions/cache/save@v4`; GitHub runners are ephemeral, so a plain local state file disappears after each run.
- Run cloud jobs with `--once --init-if-empty` so the first run initializes state instead of pushing old messages.
- Use a schedule such as `*/5 * * * *`; warn that GitHub schedules can be delayed by a few minutes.

The bundled `examples/github-actions/chaincatcher-bark.yml` is a copy-ready starting point.

For ordinary users, prefer the helper:

```bash
scripts/setup_github_actions.sh
```

It copies the workflow, asks for Bark keys, saves repository Secrets with `gh secret set`, and commits/pushes the workflow when possible.

## Common Mistakes

- Do not `source .env` blindly when values contain spaces or non-ASCII text. Parse key/value lines or use a dotenv parser.
- Do not log full command lines that include Bark keys. Catch curl errors and print sanitized messages.
- Do not run live polling before `--init-seen`; otherwise the first run can push old search results.
- Do not put a live scheduled workflow in a public template repo unless it is meant to run there. Prefer examples under `examples/github-actions/`.
- Do not infer the page title from meta tags. Extract the repeated result item title from the API or rendered list.

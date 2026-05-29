#!/usr/bin/env python3
import argparse
import html
import json
import os
import re
import shlex
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


CHAINCATCHER_API_URL = "https://www.api.chaincatcher.com/pc/search/list"
ODAILY_NEWSFLASH_URL = "https://www.odaily.news/zh-CN/newsflash"
PANEWS_RSS_URL = "https://www.panewslab.com/rss.xml?lang=zh&type=NEWS"
COINDESK_RSS_URL = "https://www.coindesk.com/arc/outboundfeeds/rss/"
SOURCE_CHOICES = ("chaincatcher-search", "odaily-newsflash", "panews-rss", "coindesk-rss")


def env_suffix(topic):
    return re.sub(r"[^A-Za-z0-9]+", "_", topic).strip("_").upper()


def strip_html(value):
    text = re.sub(r"<[^>]+>", "", value or "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def normalize_bark_key(value):
    value = (value or "").strip()
    value = value.removeprefix("https://api.day.app/")
    value = value.removeprefix("http://api.day.app/")
    return value.split("/", 1)[0]


def parse_env_value(value):
    try:
        parts = shlex.split(value)
    except ValueError:
        return value.strip().strip("\"'")
    return " ".join(parts) if parts else ""


def load_env(path):
    env = {}
    if path.exists():
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            env[key.strip()] = parse_env_value(value)
    for key, value in os.environ.items():
        if (
            key == "BARK_KEY"
            or key in {"SOURCE", "KEYWORDS", "SOURCE_URL"}
            or key.startswith("BARK_KEY_")
            or key.startswith("BARK_GROUP_")
            or key.startswith("CHAINCATCHER_KEYWORDS_")
            or key.startswith("KEYWORDS_")
            or key.startswith("SOURCE_")
            or key.startswith("SOURCE_URL_")
            or key.startswith("STATE_PATH_")
        ):
            env[key] = value
    for key in list(env):
        if key == "BARK_KEY" or key.startswith("BARK_KEY_"):
            env[key] = normalize_bark_key(env[key])
    return env


def curl_text(url, payload=None):
    command = ["curl", "-fsSL", "--max-time", "30"]
    if payload is not None:
        command.extend(
            [
                "-X",
                "POST",
                "-H",
                "Content-Type: application/json; charset=utf-8",
                "-d",
                json.dumps(payload, ensure_ascii=False),
            ]
        )
    command.append(url)
    result = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"curl failed with exit code {result.returncode}: {detail}")
    return result.stdout


def curl_json(url, payload=None):
    return json.loads(curl_text(url, payload))


def extract_titles(payload):
    items = payload.get("data", {}).get("items", [])
    titles = []
    for item in items:
        title = strip_html(item.get("title", ""))
        if title:
            titles.append({"id": str(item.get("id") or title), "title": title})
    return titles


def fetch_chaincatcher_titles(keywords, page_size):
    payload = {"keywords": keywords, "pageNumber": 1, "pageSize": page_size}
    return extract_titles(curl_json(CHAINCATCHER_API_URL, payload))


def split_keywords(keywords):
    return [part.strip().lower() for part in re.split(r"[,，\n|]+", keywords or "") if part.strip()]


def matches_keywords(item, keywords):
    parts = split_keywords(keywords)
    if not parts:
        return True
    haystack = " ".join(str(item.get(key, "")) for key in ("title", "description")).lower()
    return any(part in haystack for part in parts)


def filter_titles(items, keywords):
    return [item for item in items if matches_keywords(item, keywords)]


def child_text(element, names):
    for name in names:
        found = element.find(name)
        if found is not None and found.text:
            return strip_html(found.text)
    for child in list(element):
        local_name = child.tag.rsplit("}", 1)[-1]
        if local_name in names and child.text:
            return strip_html(child.text)
    return ""


def fetch_rss_titles(url, keywords, page_size):
    root = ET.fromstring(curl_text(url))
    items = []
    for item in root.findall(".//item"):
        title = child_text(item, {"title"})
        link = child_text(item, {"link"})
        guid = child_text(item, {"guid"})
        description = child_text(item, {"description"})
        if title:
            items.append(
                {
                    "id": guid or link or title,
                    "title": title,
                    "description": description,
                }
            )
    return filter_titles(items, keywords)[:page_size]


def iter_json_ld_documents(html_text):
    pattern = re.compile(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        re.IGNORECASE | re.DOTALL,
    )
    for match in pattern.finditer(html_text):
        raw = html.unescape(match.group(1)).strip()
        if not raw:
            continue
        try:
            yield json.loads(raw)
        except json.JSONDecodeError:
            continue


def iter_json_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from iter_json_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_json_objects(child)


def collect_odaily_items(document):
    documents = list(iter_json_objects(document))
    items = []
    for entry in documents:
        if entry.get("@type") != "ItemList":
            continue
        for wrapped in entry.get("itemListElement", []):
            item = wrapped.get("item", wrapped) if isinstance(wrapped, dict) else {}
            if not isinstance(item, dict):
                continue
            title = strip_html(item.get("name", ""))
            url = item.get("url") or item.get("@id") or title
            if title:
                items.append({"id": str(url), "title": title})
    return items


def fetch_odaily_newsflash_titles(url, keywords, page_size):
    items = []
    for document in iter_json_ld_documents(curl_text(url)):
        items.extend(collect_odaily_items(document))
    return filter_titles(items, keywords)[:page_size]


def fetch_titles(source, keywords, page_size, source_url=None):
    if source == "chaincatcher-search":
        return fetch_chaincatcher_titles(keywords, page_size)
    if source == "odaily-newsflash":
        return fetch_odaily_newsflash_titles(source_url or ODAILY_NEWSFLASH_URL, keywords, page_size)
    if source == "panews-rss":
        return fetch_rss_titles(source_url or PANEWS_RSS_URL, keywords, page_size)
    if source == "coindesk-rss":
        return fetch_rss_titles(source_url or COINDESK_RSS_URL, keywords, page_size)
    raise SystemExit(f"Unsupported source: {source}. Choose one of: {', '.join(SOURCE_CHOICES)}")


def send_bark(bark_key, group, body):
    payload = {"title": group, "body": body, "group": group}
    return curl_json(f"https://api.day.app/{bark_key}", payload)


def load_seen(path):
    if not path.exists():
        return set()
    return set(json.loads(path.read_text(encoding="utf-8")).get("seen_ids", []))


def save_seen(path, seen):
    path.write_text(
        json.dumps({"seen_ids": sorted(seen)}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def resolve_config(env, topic):
    suffix = env_suffix(topic)
    bark_key = env.get(f"BARK_KEY_{suffix}") or env.get("BARK_KEY")
    if not bark_key:
        raise SystemExit(f"BARK_KEY_{suffix} or BARK_KEY missing in .env")
    group = env.get(f"BARK_GROUP_{suffix}") or topic
    source = env.get(f"SOURCE_{suffix}") or env.get("SOURCE") or "chaincatcher-search"
    keywords = env.get(f"KEYWORDS_{suffix}") or env.get("KEYWORDS") or env.get(f"CHAINCATCHER_KEYWORDS_{suffix}") or group
    source_url = env.get(f"SOURCE_URL_{suffix}") or env.get("SOURCE_URL")
    state_path = Path(env.get(f"STATE_PATH_{suffix}") or f"seen_{topic.replace('-', '_')}.json")
    return bark_key, group, source, keywords, source_url, state_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", required=True, help="Topic name, e.g. binance-contract.")
    parser.add_argument("--env", default=".env")
    parser.add_argument("--page-size", type=int, default=10)
    parser.add_argument("--init-seen", action="store_true")
    parser.add_argument("--init-if-empty", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--test-title")
    args = parser.parse_args()

    env = load_env(Path(args.env))
    bark_key, group, source, keywords, source_url, state_path = resolve_config(env, args.topic)

    if args.test_title:
        response = send_bark(bark_key, group, args.test_title)
        print(json.dumps({"code": response.get("code"), "message": response.get("message")}, ensure_ascii=False))
        return

    titles = fetch_titles(source, keywords, args.page_size, source_url)
    seen = load_seen(state_path)

    if args.init_seen or (args.init_if_empty and not state_path.exists()):
        save_seen(state_path, seen | {item["id"] for item in titles})
        print(f"Initialized {state_path} without pushing.")
        return

    if not args.once:
        raise SystemExit("Use --once, --init-seen, or --test-title.")

    pushed = []
    for item in reversed(titles):
        if item["id"] in seen:
            continue
        response = send_bark(bark_key, group, item["title"])
        if response.get("code") != 200:
            raise SystemExit(f"Bark push failed: {response}")
        seen.add(item["id"])
        pushed.append(item["title"])

    save_seen(state_path, seen)
    print(json.dumps({"pushed": pushed}, ensure_ascii=False))


if __name__ == "__main__":
    main()

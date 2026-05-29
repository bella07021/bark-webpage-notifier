#!/usr/bin/env python3
import argparse
import html
import json
import re
import shlex
import subprocess
from pathlib import Path


API_URL = "https://www.api.chaincatcher.com/pc/search/list"


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
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = parse_env_value(value)
    for key in list(env):
        if key == "BARK_KEY" or key.startswith("BARK_KEY_"):
            env[key] = normalize_bark_key(env[key])
    return env


def curl_json(url, payload):
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "-X",
            "POST",
            url,
            "-H",
            "Content-Type: application/json; charset=utf-8",
            "-d",
            json.dumps(payload, ensure_ascii=False),
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"curl failed with exit code {result.returncode}: {detail}")
    return json.loads(result.stdout)


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
    return extract_titles(curl_json(API_URL, payload))


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
    keywords = env.get(f"CHAINCATCHER_KEYWORDS_{suffix}") or group
    state_path = Path(env.get(f"STATE_PATH_{suffix}") or f"seen_{topic.replace('-', '_')}.json")
    return bark_key, group, keywords, state_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", required=True, help="Topic name, e.g. binance-contract.")
    parser.add_argument("--env", default=".env")
    parser.add_argument("--page-size", type=int, default=10)
    parser.add_argument("--init-seen", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--test-title")
    args = parser.parse_args()

    env = load_env(Path(args.env))
    bark_key, group, keywords, state_path = resolve_config(env, args.topic)

    if args.test_title:
        response = send_bark(bark_key, group, args.test_title)
        print(json.dumps({"code": response.get("code"), "message": response.get("message")}, ensure_ascii=False))
        return

    titles = fetch_chaincatcher_titles(keywords, args.page_size)
    seen = load_seen(state_path)

    if args.init_seen:
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

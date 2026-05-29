#!/usr/bin/env python3
import argparse
import getpass
import json
import re
import subprocess
import sys
from pathlib import Path


SOURCES = [
    ("chaincatcher-search", "ChainCatcher 搜索页 / Chinese search"),
    ("odaily-newsflash", "Odaily 星球日报快讯 / Chinese newsflash"),
    ("panews-rss", "PANews RSS / Chinese RSS"),
    ("coindesk-rss", "CoinDesk RSS / English RSS"),
]


def open_tty():
    try:
        return open("/dev/tty", "r", encoding="utf-8")
    except OSError:
        return sys.stdin


TTY = open_tty()


def ask(prompt, default=""):
    suffix = f" [{default}]" if default else ""
    print(f"{prompt}{suffix}: ", end="", flush=True)
    value = TTY.readline()
    if value == "":
        return default
    value = value.rstrip("\n")
    return value or default


def ask_yes_no(prompt, default="Y"):
    value = ask(f"{prompt} [{default}]", "").strip().lower()
    if not value:
        value = default.lower()
    return value in {"y", "yes"}


def ask_secret(prompt):
    if TTY is sys.stdin:
        return getpass.getpass(f"{prompt}: ")
    print(f"{prompt}: ", end="", flush=True)
    return getpass.getpass("", stream=sys.stderr)


def slugify(value, fallback):
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or fallback


def env_suffix(value):
    suffix = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").upper()
    return suffix or "TOPIC"


def load_config(path):
    if not path.exists():
        return {"topics": []}
    return json.loads(path.read_text(encoding="utf-8"))


def save_config(path, config):
    path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def next_topic_name(existing, source):
    names = {topic["name"] for topic in existing}
    prefix = slugify(source.replace("-rss", "").replace("-newsflash", ""), "topic")
    index = 1
    while True:
        name = f"{prefix}-{index}"
        if name not in names:
            return name
        index += 1


def choose_source():
    print("\n选择信息来源 / Choose source:")
    for index, (source, label) in enumerate(SOURCES, start=1):
        print(f"  {index}. {source} - {label}")
    while True:
        value = ask("Source number", "1").strip()
        if value.isdigit() and 1 <= int(value) <= len(SOURCES):
            return SOURCES[int(value) - 1][0]
        if value in {source for source, _ in SOURCES}:
            return value
        print("Please choose a valid source.")


def set_secret(repo, secret_name, bark_value):
    subprocess.run(
        ["gh", "secret", "set", secret_name, "--repo", repo, "--body", bark_value],
        check=True,
    )


def patch_workflow(path, secret_names):
    text = path.read_text(encoding="utf-8")
    begin = "          # BEGIN TOPIC SECRETS\n"
    end = "          # END TOPIC SECRETS\n"
    secret_lines = "".join(
        f"          {name}: ${{{{ secrets.{name} }}}}\n" for name in sorted(set(secret_names))
    )
    block = begin + secret_lines + end

    if begin in text and end in text:
        before = text.split(begin, 1)[0]
        after = text.split(end, 1)[1]
        text = before + block + after
    else:
        marker = "        env:\n"
        if marker not in text:
            raise SystemExit(f"Cannot find env block in {path}")
        text = text.replace(marker, marker + block, 1)
    path.write_text(text, encoding="utf-8")


def print_summary(topic):
    print("\n信息确认 / Confirm notification group:")
    print(f"  source:   {topic['source']}")
    print(f"  keywords: {topic['keywords']}")
    print(f"  group:    {topic['group']}")
    print(f"  secret:   {topic['secret_env']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--config", default="bark_topics.json")
    parser.add_argument("--workflow", default=".github/workflows/bark-web-watch.yml")
    args = parser.parse_args()

    config_path = Path(args.config)
    workflow_path = Path(args.workflow)
    config = load_config(config_path)
    topics = config.setdefault("topics", [])

    if topics:
        print("\nExisting notification groups:")
        for topic in topics:
            print(f"  - {topic['group']} ({topic['source']}, {topic['keywords']})")

    if topics and not ask_yes_no("Add another notification group?", "Y"):
        patch_workflow(workflow_path, [topic["secret_env"] for topic in topics])
        save_config(config_path, config)
        return

    while True:
        source = choose_source()
        keywords = ask("输入关键词 / Keywords").strip()
        while not keywords:
            keywords = ask("Keywords cannot be empty. 输入关键词 / Keywords").strip()
        group = ask("输入 Bark 分组名 / Bark group", keywords).strip()
        bark_value = ask_secret("输入 Bark key 或完整 Bark URL / Bark key or URL").strip()
        while not bark_value:
            bark_value = ask_secret("Bark value cannot be empty. Bark key or URL").strip()

        name = next_topic_name(topics, source)
        secret_name = f"BARK_KEY_{env_suffix(name)}"
        topic = {
            "name": name,
            "source": source,
            "keywords": keywords,
            "group": group,
            "secret_env": secret_name,
            "state_path": f".bark-state/seen_{name.replace('-', '_')}.json",
        }
        print_summary(topic)
        if not ask_yes_no("Save this notification group?", "Y"):
            print("Skipped this group.")
        else:
            set_secret(args.repo, secret_name, bark_value)
            topics.append(topic)
            save_config(config_path, config)
            patch_workflow(workflow_path, [item["secret_env"] for item in topics])
            print(f"Saved {group}.")

        if not ask_yes_no("Add another notification group?", "N"):
            break

    if not topics:
        raise SystemExit("No notification groups configured.")


if __name__ == "__main__":
    main()

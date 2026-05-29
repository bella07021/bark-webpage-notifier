#!/usr/bin/env python3
import argparse
import getpass
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


SOURCES = [
    ("chaincatcher-search", "ChainCatcher 搜索页", "ChainCatcher search"),
    ("odaily-newsflash", "Odaily 星球日报快讯", "Odaily newsflash"),
    ("panews-rss", "PANews RSS", "PANews RSS"),
    ("coindesk-rss", "CoinDesk RSS", "CoinDesk RSS"),
]


def open_tty():
    try:
        return open("/dev/tty", "r", encoding="utf-8")
    except OSError:
        return sys.stdin


TTY = open_tty()
LANG = "zh"

if sys.stdout.isatty():
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    RESET = "\033[0m"
else:
    BOLD = DIM = RED = GREEN = YELLOW = BLUE = RESET = ""


def tr(zh, en):
    return zh if LANG == "zh" else en


def step(zh, en):
    print(f"\n{BOLD}{BLUE}==> {tr(zh, en)}{RESET}")


def note(zh, en):
    print(f"{DIM}{tr(zh, en)}{RESET}")


def ok(zh, en):
    print(f"{GREEN}{tr(zh, en)}{RESET}")


def warn(zh, en):
    print(f"{YELLOW}{tr(zh, en)}{RESET}")


def ask(prompt, default=""):
    suffix = f" [{default}]" if default else ""
    print(f"{BOLD}{prompt}{RESET}{DIM}{suffix}{RESET}: ", end="", flush=True)
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
        return getpass.getpass(f"{BOLD}{prompt}{RESET}: ")
    print(f"{BOLD}{prompt}{RESET}: ", end="", flush=True)
    return getpass.getpass("", stream=sys.stderr)


def slugify(value, fallback):
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or fallback


def env_suffix(value):
    suffix = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").upper()
    return suffix or "TOPIC"


def normalize_bark_key(value):
    value = (value or "").strip()
    value = value.removeprefix("https://api.day.app/")
    value = value.removeprefix("http://api.day.app/")
    return value.split("/", 1)[0]


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
    step("选择信息来源", "Choose a source")
    note(
        "信息来源决定脚本去哪里抓标题。RSS/快讯源会在本地按关键词过滤。",
        "The source decides where titles come from. RSS/newsflash sources are filtered locally by keywords.",
    )
    for index, (source, zh_label, en_label) in enumerate(SOURCES, start=1):
        label = zh_label if LANG == "zh" else en_label
        print(f"  {index}. {source} - {label}")
    while True:
        value = ask(tr("输入序号或 source 名称", "Source number or source name"), "1").strip()
        if value.isdigit() and 1 <= int(value) <= len(SOURCES):
            return SOURCES[int(value) - 1][0]
        if value in {source for source, _, _ in SOURCES}:
            return value
        warn("请输入有效的信息来源。", "Please choose a valid source.")


def set_secret(repo, secret_name, bark_value):
    subprocess.run(
        ["gh", "secret", "set", secret_name, "--repo", repo, "--body", bark_value],
        check=True,
    )


def send_test_push(bark_value, group):
    bark_key = normalize_bark_key(bark_value)
    payload = json.dumps(
        {"title": group, "body": "test success", "group": group},
        ensure_ascii=False,
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.day.app/{bark_key}",
        data=payload,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Bark test push failed: {exc}") from exc

    try:
        result = json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Bark test push returned non-JSON response") from exc
    if result.get("code") != 200:
        raise RuntimeError(f"Bark test push failed: {result.get('message') or result}")


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
    step("信息确认", "Confirm notification group")
    print(f"  source:   {topic['source']}")
    print(f"  keywords: {topic['keywords']}")
    print(f"  group:    {topic['group']}")
    print(f"  secret:   {topic['secret_env']}")
    note(
        "Bark key 不会写入配置文件，只会保存到 GitHub Secrets。",
        "The Bark key is not written to the config file; it is saved as a GitHub Secret.",
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--config", default="bark_topics.json")
    parser.add_argument("--workflow", default=".github/workflows/bark-web-watch.yml")
    parser.add_argument("--lang", choices=("zh", "en"), default="zh")
    args = parser.parse_args()
    global LANG
    LANG = args.lang

    config_path = Path(args.config)
    workflow_path = Path(args.workflow)
    config = load_config(config_path)
    topics = config.setdefault("topics", [])

    if topics:
        step("已有推送组", "Existing notification groups")
        for topic in topics:
            print(f"  - {topic['group']} ({topic['source']}, {topic['keywords']})")

    if topics and not ask_yes_no(tr("继续添加新的推送组？", "Add another notification group?"), "Y"):
        patch_workflow(workflow_path, [topic["secret_env"] for topic in topics])
        save_config(config_path, config)
        return

    while True:
        source = choose_source()
        step("填写关键词", "Enter keywords")
        note(
            "脚本只会推送匹配关键词的新标题。多个关键词可用逗号分隔，任意一个命中就会推送。",
            "Only new titles matching these keywords are pushed. Separate multiple keywords with commas; any match counts.",
        )
        keywords = ask(tr("输入关键词", "Keywords")).strip()
        while not keywords:
            keywords = ask(tr("关键词不能为空，请重新输入", "Keywords cannot be empty. Try again")).strip()

        step("设置 Bark 分组", "Set Bark group")
        note(
            "Bark 分组会显示在手机通知里，用来把同类消息归在一起。",
            "The Bark group appears in iOS notifications and groups related messages together.",
        )
        group = ask(tr("输入 Bark 分组名", "Bark group"), keywords).strip()

        step("保存 Bark Key", "Save Bark key")
        note(
            "可以粘贴 Bark key，也可以粘贴 Bark App 里的完整测试 URL。输入会隐藏显示。",
            "Paste either the Bark key or the full Bark test URL. Input is hidden.",
        )
        bark_value = ask_secret(tr("输入 Bark key 或完整 Bark URL", "Bark key or URL")).strip()
        while not bark_value:
            bark_value = ask_secret(tr("Bark key 不能为空，请重新输入", "Bark value cannot be empty. Try again")).strip()

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
        if not ask_yes_no(tr("保存这个推送组？", "Save this notification group?"), "Y"):
            warn("已跳过这个推送组。", "Skipped this group.")
        else:
            note("正在保存 GitHub Secret...", "Saving GitHub Secret...")
            set_secret(args.repo, secret_name, bark_value)
            note("正在发送 test success 测试推送...", "Sending test success push...")
            send_test_push(bark_value, group)
            topics.append(topic)
            save_config(config_path, config)
            patch_workflow(workflow_path, [item["secret_env"] for item in topics])
            ok(f"已保存并测试成功：{group}", f"Saved and tested: {group}")

        if not ask_yes_no(tr("继续添加另一个推送组？", "Add another notification group?"), "N"):
            break

    if not topics:
        raise SystemExit(tr("没有配置任何推送组。", "No notification groups configured."))


if __name__ == "__main__":
    main()

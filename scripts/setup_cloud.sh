#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

SOURCE_OWNER="${SOURCE_OWNER:-bella07021}"
SOURCE_REPO="${SOURCE_REPO:-bark-webpage-notifier}"
BRANCH="${BRANCH:-main}"
DEFAULT_REPO_SUFFIX="${DEFAULT_REPO_SUFFIX:-bark-webpage-notifier-watch}"

usage() {
  cat <<'EOF'
Usage:
  bash setup_cloud.sh [--repo owner/name] [--public|--private] [--lang zh|en] [--no-run]

This guided setup creates or updates a GitHub repository, saves Bark keys as
GitHub Secrets, pushes the GitHub Actions workflow, and optionally starts the
first run.

Requirements:
  - git
  - curl
  - python3
  - GitHub CLI: gh auth login
EOF
}

TARGET_REPO=""
VISIBILITY=""
RUN_WORKFLOW=1
LANG_CHOICE=""

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  RESET=""
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      TARGET_REPO="${2:-}"
      shift
      ;;
    --public)
      VISIBILITY="public"
      ;;
    --private)
      VISIBILITY="private"
      ;;
    --lang)
      LANG_CHOICE="${2:-}"
      shift
      ;;
    --no-run)
      RUN_WORKFLOW=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    if [ "${LANG_CHOICE:-en}" = "zh" ]; then
      echo "${RED}缺少必要命令：$1${RESET}" >&2
    else
      echo "${RED}Missing required command: $1${RESET}" >&2
    fi
    exit 1
  fi
}

say_step() {
  local zh="$1"
  local en="$2"
  echo
  if [ "${LANG_CHOICE:-en}" = "zh" ]; then
    echo "${BOLD}${BLUE}==> ${zh}${RESET}"
  else
    echo "${BOLD}${BLUE}==> ${en}${RESET}"
  fi
}

say_note() {
  local zh="$1"
  local en="$2"
  if [ "${LANG_CHOICE:-en}" = "zh" ]; then
    echo "${DIM}${zh}${RESET}"
  else
    echo "${DIM}${en}${RESET}"
  fi
}

say_ok() {
  local zh="$1"
  local en="$2"
  if [ "${LANG_CHOICE:-en}" = "zh" ]; then
    echo "${GREEN}${zh}${RESET}"
  else
    echo "${GREEN}${en}${RESET}"
  fi
}

say_warn() {
  local zh="$1"
  local en="$2"
  if [ "${LANG_CHOICE:-en}" = "zh" ]; then
    echo "${YELLOW}${zh}${RESET}"
  else
    echo "${YELLOW}${en}${RESET}"
  fi
}

read_input() {
  if [ -r /dev/tty ]; then
    read -r "$@" </dev/tty
  else
    read -r "$@"
  fi
}

ask() {
  local prompt="$1"
  local default="$2"
  local value=""
  read_input -p "${BOLD}${prompt}${RESET} ${DIM}[${default}]${RESET}: " value
  echo "${value:-$default}"
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local value=""
  read_input -p "${BOLD}${prompt}${RESET} ${DIM}[${default}]${RESET} " value
  value="${value:-$default}"
  case "$value" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

copy_project_files() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  tar \
    --exclude='.git' \
    --exclude='.env' \
    --exclude='.bark-state' \
    --exclude='seen_*.json' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -C "$src" -cf - . | tar -C "$dst" -xf -
}

ensure_git_identity() {
  if ! git config user.email >/dev/null; then
    git config user.email "bark-webpage-notifier@example.invalid"
  fi
  if ! git config user.name >/dev/null; then
    git config user.name "Bark Webpage Notifier"
  fi
}

start_workflow() {
  local attempts=8
  local attempt=1

  while [ "$attempt" -le "$attempts" ]; do
    if gh workflow run "bark-web-watch.yml" --repo "$TARGET_REPO" --ref main >/dev/null 2>&1; then
      say_ok "已启动第一次 workflow。" "Started the first workflow run."
      return 0
    fi

    if [ "$attempt" -lt "$attempts" ]; then
      say_warn "等待 GitHub 注册 workflow... (${attempt}/${attempts})" "Waiting for GitHub to register the workflow... (${attempt}/${attempts})"
      sleep 3
    fi
    attempt=$((attempt + 1))
  done

  say_warn "workflow 已推送，但 GitHub 没有自动启动。" "Workflow was pushed, but GitHub did not start it automatically."
  echo "https://github.com/${TARGET_REPO}/actions/workflows/bark-web-watch.yml"
  return 1
}

choose_language() {
  if [ -n "$LANG_CHOICE" ]; then
    case "$LANG_CHOICE" in
      zh|en) return ;;
      *)
        echo "${RED}--lang must be zh or en.${RESET}" >&2
        exit 1
        ;;
    esac
  fi

  echo "${BOLD}${BLUE}Bark Webpage Notifier${RESET}"
  echo "1. 中文"
  echo "2. English"
  local value=""
  read_input -p "${BOLD}选择语言 / Choose language${RESET} ${DIM}[1]${RESET}: " value
  case "${value:-1}" in
    2|en|EN|English|english) LANG_CHOICE="en" ;;
    *) LANG_CHOICE="zh" ;;
  esac
}

choose_language

say_step "检查本机环境" "Checking local requirements"
say_note "需要 git、curl、python3 和 GitHub CLI。GitHub CLI 用来创建仓库、保存 Secrets 和启动 Actions。" "Requires git, curl, python3, and GitHub CLI. GitHub CLI creates repos, saves Secrets, and starts Actions."

need_command git
need_command curl
need_command gh
need_command python3

if ! gh auth status >/dev/null 2>&1; then
  if [ "$LANG_CHOICE" = "zh" ]; then
    echo "${RED}GitHub CLI 未登录。请先运行：gh auth login${RESET}" >&2
  else
    echo "${RED}GitHub CLI is not logged in. Run: gh auth login${RESET}" >&2
  fi
  exit 1
fi

say_ok "环境检查通过。" "Requirements look good."

say_step "选择 GitHub 仓库" "Choosing the GitHub repository"
say_note "脚本会把监控代码、配置文件和 GitHub Actions workflow 放进这个仓库。" "The script stores monitor code, config, and the GitHub Actions workflow in this repo."
GITHUB_USER="$(gh api user --jq .login)"
if [ -z "$TARGET_REPO" ]; then
  if [ "$LANG_CHOICE" = "zh" ]; then
    TARGET_REPO="$(ask "要创建或使用的 GitHub 仓库" "${GITHUB_USER}/${DEFAULT_REPO_SUFFIX}")"
  else
    TARGET_REPO="$(ask "GitHub repository to create or use" "${GITHUB_USER}/${DEFAULT_REPO_SUFFIX}")"
  fi
fi
if [[ "$TARGET_REPO" != */* ]]; then
  TARGET_REPO="${GITHUB_USER}/${TARGET_REPO}"
fi

if [ -z "$VISIBILITY" ]; then
  say_note "public 方便分享给别人；private 只适合自己用。" "Public is easier to share; private is for personal use."
  if [ "$LANG_CHOICE" = "zh" ]; then
    VISIBILITY="$(ask "仓库可见性：public 或 private" "private")"
  else
    VISIBILITY="$(ask "Repository visibility: public or private" "private")"
  fi
fi
VISIBILITY="$(printf '%s' "$VISIBILITY" | tr '[:upper:]' '[:lower:]')"
case "$VISIBILITY" in
  public|private) ;;
  *)
    if [ "$LANG_CHOICE" = "zh" ]; then
      echo "${RED}仓库可见性必须是 public 或 private。${RESET}" >&2
    else
      echo "${RED}Visibility must be public or private.${RESET}" >&2
    fi
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
SOURCE_DIR="$TMP_DIR/source"
WORK_DIR="$TMP_DIR/work"
ARCHIVE_URL="https://github.com/${SOURCE_OWNER}/${SOURCE_REPO}/archive/refs/heads/${BRANCH}.tar.gz"

say_step "下载项目模板" "Downloading the project template"
say_note "这一步会临时下载最新模板，不会读取或上传你的 Bark key。" "This temporarily downloads the latest template. It does not read or upload your Bark key."
echo "Downloading ${SOURCE_OWNER}/${SOURCE_REPO}..."
curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/source.tar.gz"
tar -xzf "$TMP_DIR/source.tar.gz" -C "$TMP_DIR"
mv "$TMP_DIR/${SOURCE_REPO}-${BRANCH}" "$SOURCE_DIR"

if gh repo view "$TARGET_REPO" >/dev/null 2>&1; then
  say_step "更新已有仓库" "Updating existing repository"
  echo "${TARGET_REPO}"
  if [ "$LANG_CHOICE" = "zh" ]; then
    if ! ask_yes_no "更新这个仓库并配置推送组吗？" "Y"; then
      echo "已取消。"
      exit 0
    fi
  else
    if ! ask_yes_no "Update this repository and configure notification groups?" "Y"; then
      echo "Canceled."
      exit 0
    fi
  fi
  gh repo clone "$TARGET_REPO" "$WORK_DIR"
  copy_project_files "$SOURCE_DIR" "$WORK_DIR"
  (
    cd "$WORK_DIR"
    ensure_git_identity
    git add .
    if git diff --cached --quiet; then
      say_note "模板文件没有变化。" "No template file changes to commit."
    else
      git commit -m "Set up Bark webpage notifier"
      git push
    fi
  )
else
  say_step "创建新仓库" "Creating a new repository"
  say_note "脚本会初始化仓库并推送模板文件。" "The script initializes the repo and pushes template files."
  copy_project_files "$SOURCE_DIR" "$WORK_DIR"
  (
    cd "$WORK_DIR"
    git init -b main
    ensure_git_identity
    git add .
    git commit -m "Set up Bark webpage notifier"
    if [ "$VISIBILITY" = "public" ]; then
      gh repo create "$TARGET_REPO" --public --source=. --remote=origin --push
    else
      gh repo create "$TARGET_REPO" --private --source=. --remote=origin --push
    fi
  )
fi

(
  cd "$WORK_DIR"
  ensure_git_identity
  say_step "配置推送组" "Configuring notification groups"
  say_note "你可以添加一个或多个推送组。每个组包含：信息来源、关键词、Bark 分组名和 Bark key。" "You can add one or more groups. Each group has a source, keywords, Bark group, and Bark key."
  python3 scripts/topic_wizard.py --repo "$TARGET_REPO" --lang "$LANG_CHOICE"
  git add bark_topics.json .github/workflows/bark-web-watch.yml
  if git diff --cached --quiet; then
    say_note "推送组配置没有变化。" "No topic changes to commit."
  else
    say_step "保存配置到 GitHub" "Saving config to GitHub"
    say_note "Bark key 会保存为 GitHub Secret；配置文件只保存来源、关键词、分组名和 Secret 名称。" "Bark keys are stored as GitHub Secrets; the config file only stores source, keywords, group, and Secret name."
    git commit -m "Configure Bark notification topics"
    git push
  fi
)

if [ "$RUN_WORKFLOW" -eq 1 ]; then
  say_step "启动第一次 workflow" "Starting the first workflow"
  say_note "第一次运行只记录当前旧消息，不推送历史标题；之后定时检查新增标题。" "The first run records current old titles without pushing them. Later runs check for new titles."
  start_workflow || true
fi

echo
say_ok "完成。" "Done."
echo "${BOLD}Repository:${RESET} https://github.com/${TARGET_REPO}"
echo "${BOLD}Workflow:${RESET}   https://github.com/${TARGET_REPO}/actions/workflows/bark-web-watch.yml"
echo
if [ "$LANG_CHOICE" = "zh" ]; then
  echo "${DIM}第一次运行只记录当前标题，不推送旧消息。${RESET}"
else
  echo "${DIM}The first run records current titles without pushing old messages.${RESET}"
fi

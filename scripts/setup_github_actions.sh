#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_SRC="examples/github-actions/chaincatcher-bark.yml"
WORKFLOW_DEST=".github/workflows/bark-web-watch.yml"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup_github_actions.sh [--force] [--lang zh|en]

What it does:
  1. Copies the Bark GitHub Actions workflow into .github/workflows/.
  2. Guides you through adding notification groups.
  3. Saves Bark keys as GitHub repository Secrets.
  4. Commits and pushes the config/workflow when possible.

Run this from your cloned or forked bark-webpage-notifier repository.

If you are starting from zero, use:
  curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
EOF
}

FORCE=0
LANG_CHOICE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    --lang)
      LANG_CHOICE="${2:-}"
      shift
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

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  RED="$(printf '\033[31m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  BLUE=""
  GREEN=""
  RED=""
  RESET=""
fi

read_input() {
  if [ -r /dev/tty ]; then
    read -r "$@" </dev/tty
  else
    read -r "$@"
  fi
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

say_step() {
  if [ "$LANG_CHOICE" = "zh" ]; then
    echo
    echo "${BOLD}${BLUE}==> $1${RESET}"
  else
    echo
    echo "${BOLD}${BLUE}==> $2${RESET}"
  fi
}

say_ok() {
  if [ "$LANG_CHOICE" = "zh" ]; then
    echo "${GREEN}$1${RESET}"
  else
    echo "${GREEN}$2${RESET}"
  fi
}

choose_language

if [ ! -f "$WORKFLOW_SRC" ]; then
  echo "Missing $WORKFLOW_SRC. Run this script from the repository root." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it from https://cli.github.com/ and run gh auth login." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login" >&2
  exit 1
fi

TARGET_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

say_step "准备 GitHub Actions workflow" "Preparing GitHub Actions workflow"
mkdir -p "$(dirname "$WORKFLOW_DEST")"
if [ -f "$WORKFLOW_DEST" ] && [ "$FORCE" -ne 1 ]; then
  echo "$WORKFLOW_DEST already exists; keeping it. Use --force to overwrite."
else
  cp "$WORKFLOW_SRC" "$WORKFLOW_DEST"
  echo "Wrote $WORKFLOW_DEST"
fi

say_step "配置推送组" "Configuring notification groups"
python3 scripts/topic_wizard.py --repo "$TARGET_REPO" --workflow "$WORKFLOW_DEST" --lang "$LANG_CHOICE"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$WORKFLOW_DEST" bark_topics.json
  if git diff --cached --quiet; then
    echo "No config changes to commit."
  else
    git commit -m "Configure Bark webpage watch action"
    git push
    say_ok "配置和 workflow 已推送到 GitHub。" "Pushed config and workflow to GitHub."
  fi
fi

echo
echo "Done. Open GitHub Actions -> Bark Webpage Watch -> Run workflow."

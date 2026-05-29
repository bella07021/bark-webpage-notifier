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
  bash setup_cloud.sh [--repo owner/name] [--public|--private] [--no-run]

This guided setup creates or updates a GitHub repository, saves Bark keys as
GitHub Secrets, pushes the GitHub Actions workflow, and optionally starts the
first run.

Requirements:
  - git
  - curl
  - GitHub CLI: gh auth login
EOF
}

TARGET_REPO=""
VISIBILITY=""
RUN_WORKFLOW=1

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
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ask() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "${prompt} [${default}]: " value
  echo "${value:-$default}"
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "${prompt} [${default}] " value
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

set_bark_secret() {
  local secret_name="$1"
  local label="$2"
  local default_answer="$3"
  local value=""

  if ask_yes_no "Enable ${label} notifications?" "$default_answer"; then
    read -r -s -p "Paste Bark key or full Bark URL for ${label}: " value
    echo
    if [ -z "$value" ]; then
      echo "Skipped ${label}: empty Bark key."
      return 1
    fi
    gh secret set "$secret_name" --repo "$TARGET_REPO" --body "$value"
    echo "Saved ${secret_name}"
    return 0
  fi

  echo "Skipped ${label}"
  return 1
}

need_command git
need_command curl
need_command gh

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login" >&2
  exit 1
fi

GITHUB_USER="$(gh api user --jq .login)"
if [ -z "$TARGET_REPO" ]; then
  TARGET_REPO="$(ask "GitHub repository to create or use" "${GITHUB_USER}/${DEFAULT_REPO_SUFFIX}")"
fi

if [ -z "$VISIBILITY" ]; then
  VISIBILITY="$(ask "Repository visibility: public or private" "private")"
fi
VISIBILITY="$(printf '%s' "$VISIBILITY" | tr '[:upper:]' '[:lower:]')"
case "$VISIBILITY" in
  public|private) ;;
  *)
    echo "Visibility must be public or private." >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
SOURCE_DIR="$TMP_DIR/source"
WORK_DIR="$TMP_DIR/work"
ARCHIVE_URL="https://github.com/${SOURCE_OWNER}/${SOURCE_REPO}/archive/refs/heads/${BRANCH}.tar.gz"

echo "Downloading ${SOURCE_OWNER}/${SOURCE_REPO}..."
curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/source.tar.gz"
tar -xzf "$TMP_DIR/source.tar.gz" -C "$TMP_DIR"
mv "$TMP_DIR/${SOURCE_REPO}-${BRANCH}" "$SOURCE_DIR"

if gh repo view "$TARGET_REPO" >/dev/null 2>&1; then
  echo "Repository ${TARGET_REPO} already exists."
  if ! ask_yes_no "Update this repository with Bark Webpage Notifier files?" "N"; then
    echo "Canceled."
    exit 0
  fi
  gh repo clone "$TARGET_REPO" "$WORK_DIR"
  copy_project_files "$SOURCE_DIR" "$WORK_DIR"
  (
    cd "$WORK_DIR"
    ensure_git_identity
    git add .
    if git diff --cached --quiet; then
      echo "No file changes to commit."
    else
      git commit -m "Set up Bark webpage notifier"
      git push
    fi
  )
else
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

enabled_count=0
if set_bark_secret "BARK_KEY_BINANCE_CONTRACT" "币安合约" "Y"; then
  enabled_count=$((enabled_count + 1))
fi
if set_bark_secret "BARK_KEY_BINANCE_ALPHA" "币安 alpha" "Y"; then
  enabled_count=$((enabled_count + 1))
fi

if [ "$enabled_count" -eq 0 ]; then
  echo "No Bark key was saved. Add at least one repository secret before the workflow can push." >&2
fi

if [ "$RUN_WORKFLOW" -eq 1 ]; then
  if gh workflow run "bark-web-watch.yml" --repo "$TARGET_REPO" >/dev/null 2>&1; then
    echo "Started the first workflow run."
  else
    echo "Workflow was pushed, but GitHub did not start it automatically. Open Actions and click Run workflow."
  fi
fi

echo
echo "Done."
echo "Repository: https://github.com/${TARGET_REPO}"
echo "Workflow:   https://github.com/${TARGET_REPO}/actions/workflows/bark-web-watch.yml"
echo
echo "The first run records current titles without pushing old messages."

#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

REPO_OWNER="${REPO_OWNER:-bella07021}"
REPO_NAME="${REPO_NAME:-bark-webpage-notifier}"
BRANCH="${BRANCH:-main}"
SKILL_NAME="${SKILL_NAME:-bark-webpage-notifier}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="${INSTALL_DIR:-$CODEX_HOME/skills/$SKILL_NAME}"

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

copy_skill() {
  local src="$1"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  tar \
    --exclude='.git' \
    --exclude='.env' \
    --exclude='.bark-state' \
    --exclude='seen_*.json' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -C "$src" -cf - . | tar -C "$INSTALL_DIR" -xf -
}

if [ -f "SKILL.md" ] && [ -f "scripts/bark_web_watch.py" ]; then
  SOURCE_DIR="$(pwd)"
else
  TMP_DIR="$(mktemp -d)"
  ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
  echo "Downloading ${REPO_OWNER}/${REPO_NAME}..."
  curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/skill.tar.gz"
  tar -xzf "$TMP_DIR/skill.tar.gz" -C "$TMP_DIR"
  SOURCE_DIR="$TMP_DIR/${REPO_NAME}-${BRANCH}"
fi

copy_skill "$SOURCE_DIR"

echo "Installed ${SKILL_NAME} to:"
echo "  ${INSTALL_DIR}"
echo
echo "Next:"
echo "  Restart Codex or open a new Codex chat, then ask it to use ${SKILL_NAME}."
echo "  For cloud polling, run:"
echo "    curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/scripts/setup_cloud.sh | bash"

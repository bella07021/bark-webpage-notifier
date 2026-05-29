#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_SRC="examples/github-actions/chaincatcher-bark.yml"
WORKFLOW_DEST=".github/workflows/bark-web-watch.yml"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup_github_actions.sh [--force]

What it does:
  1. Copies the Bark GitHub Actions workflow into .github/workflows/.
  2. Lets you add Bark keys as GitHub repository Secrets.
  3. Commits and pushes the workflow when possible.

Run this from your cloned or forked bark-webpage-notifier repository.
EOF
}

FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
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

if [ ! -f "$WORKFLOW_SRC" ]; then
  echo "Missing $WORKFLOW_SRC. Run this script from the repository root." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it from https://cli.github.com/ and run gh auth login." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login" >&2
  exit 1
fi

mkdir -p "$(dirname "$WORKFLOW_DEST")"
if [ -f "$WORKFLOW_DEST" ] && [ "$FORCE" -ne 1 ]; then
  echo "$WORKFLOW_DEST already exists; keeping it. Use --force to overwrite."
else
  cp "$WORKFLOW_SRC" "$WORKFLOW_DEST"
  echo "Wrote $WORKFLOW_DEST"
fi

set_secret() {
  local secret_name="$1"
  local label="$2"
  local answer=""
  local value=""

  read -r -p "Set ${label} Bark key as ${secret_name}? [Y/n] " answer
  answer="${answer:-Y}"
  case "$answer" in
    y|Y|yes|YES)
      read -r -s -p "Paste Bark key or full Bark URL for ${label}: " value
      echo
      if [ -z "$value" ]; then
        echo "Skipped ${secret_name}: empty value."
        return
      fi
      gh secret set "$secret_name" --body "$value"
      echo "Saved ${secret_name}"
      ;;
    *)
      echo "Skipped ${secret_name}"
      ;;
  esac
}

set_secret "BARK_KEY_BINANCE_CONTRACT" "币安合约"
set_secret "BARK_KEY_BINANCE_ALPHA" "币安 alpha"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$WORKFLOW_DEST"
  if git diff --cached --quiet; then
    echo "No workflow changes to commit."
  else
    git commit -m "Enable Bark webpage watch action"
    git push
    echo "Pushed workflow to GitHub."
  fi
fi

echo
echo "Done. Open GitHub Actions -> Bark Webpage Watch -> Run workflow."

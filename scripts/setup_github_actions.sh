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
  2. Guides you through adding notification groups.
  3. Saves Bark keys as GitHub repository Secrets.
  4. Commits and pushes the config/workflow when possible.

Run this from your cloned or forked bark-webpage-notifier repository.

If you are starting from zero, use:
  curl -fsSL https://raw.githubusercontent.com/bella07021/bark-webpage-notifier/main/scripts/setup_cloud.sh | bash
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
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login" >&2
  exit 1
fi

TARGET_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

mkdir -p "$(dirname "$WORKFLOW_DEST")"
if [ -f "$WORKFLOW_DEST" ] && [ "$FORCE" -ne 1 ]; then
  echo "$WORKFLOW_DEST already exists; keeping it. Use --force to overwrite."
else
  cp "$WORKFLOW_SRC" "$WORKFLOW_DEST"
  echo "Wrote $WORKFLOW_DEST"
fi

python3 scripts/topic_wizard.py --repo "$TARGET_REPO" --workflow "$WORKFLOW_DEST"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$WORKFLOW_DEST" bark_topics.json
  if git diff --cached --quiet; then
    echo "No config changes to commit."
  else
    git commit -m "Configure Bark webpage watch action"
    git push
    echo "Pushed config and workflow to GitHub."
  fi
fi

echo
echo "Done. Open GitHub Actions -> Bark Webpage Watch -> Run workflow."

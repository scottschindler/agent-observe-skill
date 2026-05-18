#!/usr/bin/env bash
set -euo pipefail

repo_url="${AGENT_OBSERVE_REPO_URL:-https://github.com/scottschindler/agent-observe-skill.git}"
repo_ref="${AGENT_OBSERVE_REF:-main}"
target_dir="${AGENT_OBSERVE_TARGET_DIR:-.agents/skills/agent-observe-skill}"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

git clone --depth 1 --filter=blob:none --sparse --branch "$repo_ref" "$repo_url" "$tmpdir/agent-observe-skill"
git -C "$tmpdir/agent-observe-skill" sparse-checkout set agent-observe-skill

mkdir -p "$(dirname "$target_dir")"
rm -rf "$target_dir"
cp -R "$tmpdir/agent-observe-skill/agent-observe-skill" "$target_dir"
chmod +x "$target_dir/scripts/skill.sh"

printf 'Installed Agent Observe Skill to %s\n' "$target_dir"
printf 'Restart Codex from this repo, then ask: Use $agent-observe-skill to scan this repo.\n'

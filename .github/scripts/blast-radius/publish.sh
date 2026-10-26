#!/usr/bin/env bash
# Puts the blast radius on the pull request: one comment (created once, then
# updated on every push) and exactly one risk:* label.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, OUT_DIR (comment.md, risk)
set -euo pipefail

repo=$GITHUB_REPOSITORY
risk=$(cat "$OUT_DIR/risk")
marker='<!-- blast-radius -->'

# Comment: update ours if it exists, so the PR keeps a single, current one.
id=$(gh api "repos/$repo/issues/$PR_NUMBER/comments" --paginate \
       --jq ".[] | select(.body | startswith(\"$marker\")) | .id" | head -n 1)
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$id" -F "body=@$OUT_DIR/comment.md" > /dev/null
  echo "Updated comment $id"
else
  gh api -X POST "repos/$repo/issues/$PR_NUMBER/comments" -F "body=@$OUT_DIR/comment.md" > /dev/null
  echo "Created comment"
fi

# Labels: make sure the four exist, then keep only the current one on the PR.
declare -A color=([low]=0E8A16 [medium]=FBCA04 [high]=D93F0B [critical]=B60205)
for level in low medium high critical; do
  gh label create "risk:$level" --repo "$repo" --color "${color[$level]}" \
    --description "Blast radius: $level" --force > /dev/null
done
for level in low medium high critical; do
  [ "$level" = "$risk" ] && continue
  gh api -X DELETE "repos/$repo/issues/$PR_NUMBER/labels/risk:$level" > /dev/null 2>&1 || true
done
gh api -X POST "repos/$repo/issues/$PR_NUMBER/labels" -f "labels[]=risk:$risk" > /dev/null
echo "Label risk:$risk"

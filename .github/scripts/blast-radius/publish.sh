#!/usr/bin/env bash
# Puts the blast radius on the pull request: one comment, created once and then
# updated on every push.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, OUT_DIR (comment.md)
set -euo pipefail

repo=$GITHUB_REPOSITORY
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

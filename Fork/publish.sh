#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac
#
# Prepares what GitHub will show, without pushing anything: the local branch
# "public" becomes origin/main plus one commit holding main's files, minus the
# personal ones below (working notes, the plan, observations of other apps).
# main keeps its own history and those files; the push stays a separate step:
#   git push origin public:main
#
# Usage: ./Fork/publish.sh "Hublot 0.1"
set -euo pipefail
cd "$(dirname "$0")/.."

MESSAGE="${1:?usage: ./Fork/publish.sh \"<message>\"}"
PRIVATE=(CLAUDE.md docs/HUBLOT-PLAN.md docs/reference)

git fetch --quiet origin main
INDEX=$(mktemp)
trap 'rm -f "$INDEX"' EXIT
export GIT_INDEX_FILE="$INDEX"
git read-tree main
git rm -r --cached --quiet --ignore-unmatch -- "${PRIVATE[@]}"
TREE=$(git write-tree)
unset GIT_INDEX_FILE

if [[ "$TREE" == "$(git rev-parse 'origin/main^{tree}')" ]]; then
    echo "Nothing new to publish."
    exit 0
fi
COMMIT=$(git commit-tree "$TREE" -p origin/main -m "$MESSAGE")
git branch -f public "$COMMIT"

for item in "${PRIVATE[@]}"; do
    if git ls-tree -r --name-only public | grep -q "^$item"; then
        echo "✗ $item is still in public" >&2
        exit 1
    fi
done
echo "✓ public = origin/main + « $MESSAGE »"
git diff --shortstat origin/main public
echo "Push it, once agreed: git push origin public:main"

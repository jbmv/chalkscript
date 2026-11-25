#!/bin/sh
# Refuses text that only makes sense inside a private tracker: its record ids and links.
#
# Usage: scripts/check-public.sh [--tree COMMIT] [REVISIONS...]
#   With no arguments it checks every tracked file in the working tree.
#   --tree COMMIT checks the files of that commit instead.
#   REVISIONS are passed to `git log`, and the messages of those commits are checked too,
#   e.g. scripts/check-public.sh origin/main..HEAD
set -u
pattern='(^|[^A-Za-z])(NIB|CHS)-[0-9]+|kyosei://|claude\.ai/artifact'
status=0
tree=""

if [ "${1:-}" = "--tree" ]; then
    tree="$2"
    shift 2
fi

# The tree argument is deliberately unquoted: empty means the working tree.
if git grep -nE "$pattern" $tree -- . ':!scripts/check-public.sh'; then
    echo "check-public: the lines above cite a private record or link; say it in plain words or cite the spec (EXP-n)." >&2
    status=1
fi

if [ "$#" -ge 1 ]; then
    if git log --format='%h %B' "$@" | grep -nE "$pattern"; then
        echo "check-public: a commit message being checked cites a private record or link." >&2
        status=1
    fi
fi

exit $status

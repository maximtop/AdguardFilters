#!/usr/bin/env bash
# Copy one AdguardFilters report into this fork as a new issue, for a filters-agent test run.
#
# The run must not see where the report came from: an upstream link leads to maintainer replies and
# the fix, and the run would be judged on an answer it could look up. So the copy carries the
# report text only: no upstream comments and no reference back. copy-fresh-issues.sh records which
# upstream report each copy came from, on a branch the run never checks out.
#
# Nothing in the copy may reach back to the upstream repository either: an @mention notifies the
# person, and a cross-repository issue reference or issue URL adds a "mentioned this issue" event
# to the upstream issue's timeline. Every such token is wrapped in a code span, which GitHub
# renders as plain text and never links. Bare #N references are wrapped too: in the fork they
# would point at the fork's own, unrelated issues.
#
# Usage: copy-upstream-issue.sh <issue-number> <fork-owner/repo>
# Prints "Created <issue-url>".
#
# Environment:
#   UPSTREAM_REPOSITORY  Source repository (default AdguardTeam/AdguardFilters).
#
# Requires `gh` authenticated with write access to the fork's issues, `jq` and `perl`.
set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ ]]; then
    echo "Usage: $(basename "$0") <issue-number> <fork-owner/repo>" >&2
    exit 1
fi
issue_number="$1"
fork="$2"
upstream="${UPSTREAM_REPOSITORY:-AdguardTeam/AdguardFilters}"

# Wrap every token that would notify someone or link back to another issue in a code span.
# The lookbehinds skip tokens already inside a code span and e-mail addresses.
neutralize() {
    perl -0pe '
        s{(?<![`\w])(https?://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull|discussions)/\d+[^\s)]*)}{`$1`}g;
        s{(?<![`\w/])([\w.-]+/[\w.-]+#\d+)}{`$1`}g;
        s{(?<![`\w/&])(#\d+)\b}{`$1`}g;
        s{(?<![`\w])(@[A-Za-z0-9][A-Za-z0-9-]*)}{`$1`}g;
    '
}

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

gh api "repos/${upstream}/issues/${issue_number}" > "${workdir}/issue.json"
if jq -e '.pull_request != null' "${workdir}/issue.json" > /dev/null; then
    echo "${upstream}#${issue_number} is a pull request, not an issue." >&2
    exit 1
fi

jq -r '.body // ""' "${workdir}/issue.json" | neutralize > "${workdir}/body.md"
issue_url="$(gh issue create --repo "${fork}" --title "$(jq -r '.title' "${workdir}/issue.json")" \
    --body-file "${workdir}/body.md")"
echo "Created ${issue_url}"

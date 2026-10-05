#!/usr/bin/env bash
# Copy every fresh AdguardFilters report from the AdGuard Browser Extension or AdGuard for
# Windows or Mac into this fork and start a filters-agent run on each, so both the extension route
# and the AdGuard CLI module keep getting real issues.
#
# Reports maintainers already closed are copied too: their fix can be compared with the run's
# answer. A report already copied (its copy names it as `AdguardTeam/AdguardFilters#N`) is never
# copied again.
#
# Usage: copy-fresh-issues.sh <since-hours>
#   Copies reports opened in the last <since-hours> hours.
# Environment:
#   MAX_PARALLEL_RUNS  Agent runs allowed at once (default 5); each is a paid LLM run.
# Needs GH_TOKEN with issues: write and actions: write on this fork; GITHUB_REPOSITORY names it.
set -euo pipefail

since_hours="${1:?Usage: copy-fresh-issues.sh <since-hours>}"
max_parallel="${MAX_PARALLEL_RUNS:-5}"
upstream="${UPSTREAM_REPOSITORY:-AdguardTeam/AdguardFilters}"
fork="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name this fork}"
script_dir="$(dirname "${BASH_SOURCE[0]}")"
products='Browser Extension|AdGuard for (Windows|Mac)'

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Upstream numbers already copied into the fork, read from the footer every copy carries.
gh issue list --repo "${fork}" --state all --limit 5000 --json body \
    | jq -r '.[].body' \
    | grep -oE "Copied from \`${upstream}#[0-9]+\`" \
    | grep -oE '[0-9]+`$' | tr -d '`' | sort -u > "${workdir}/copied.txt" || true

# Upstream reports opened since the cutoff whose product line matches, oldest first.
since="$(date -u -d "${since_hours} hours ago" +%Y-%m-%dT%H:%M:%SZ)"
gh issue list --repo "${upstream}" --state all --limit 1000 --search "created:>=${since}" \
    --json number,body \
    | jq -r --arg products "${products}" '
        map(select((.body // "")
            | capture("AdGuard product:[^\\n]*?(?<p>AdGuard[^\\n|]*)").p // ""
            | test($products)))
        | sort_by(.number) | .[].number' \
    | { grep -vxF -f "${workdir}/copied.txt" || true; } > "${workdir}/picked.txt"

count="$(wc -l < "${workdir}/picked.txt" | tr -d ' ')"
echo "${count} fresh report(s) since ${since}"

# Agent runs not finished yet: queued, waiting or in progress.
active_runs() {
    gh run list --repo "${fork}" --workflow filters-agent.yml --limit 50 --json status \
        --jq '[.[] | select(.status != "completed")] | length'
}

while IFS= read -r number; do
    while (( $(active_runs) >= max_parallel )); do
        sleep 60
    done
    # The label alone would start no run: events the workflow token causes start no workflows.
    created="$(bash "${script_dir}/copy-upstream-issue.sh" "${number}" "${fork}")"
    echo "${created}"
    fork_number="$(sed -n 's#^Created .*/issues/\([0-9]*\)$#\1#p' <<< "${created}")"
    gh workflow run filters-agent.yml --repo "${fork}" -f "issueNumber=${fork_number}"
    echo "Copied upstream #${number} as #${fork_number} and started its run"
    # A dispatched run takes a few seconds to appear in the list the slot count reads.
    sleep 15
done < "${workdir}/picked.txt"

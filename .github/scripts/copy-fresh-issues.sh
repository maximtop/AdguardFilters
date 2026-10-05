#!/usr/bin/env bash
# Copy every fresh AdguardFilters report from the AdGuard Browser Extension or AdGuard for
# Windows or Mac into this fork and start a filters-agent run on each, so both the extension route
# and the AdGuard CLI module keep getting real issues.
#
# Only reports still open are copied: a closed one usually has its fix in the published filter
# lists already, and the run would find the page fixed.
#
# Which upstream report each copy came from is kept in copies.tsv on the filters-agent-copies
# branch, never in the copy itself, which the run reads. A report listed there is never copied
# again.
#
# Usage: copy-fresh-issues.sh <since-hours>
#   Copies reports opened in the last <since-hours> hours.
# Environment:
#   MAX_PARALLEL_RUNS  Agent runs allowed at once (default 5); each is a paid LLM run.
# Needs GH_TOKEN with contents: write, issues: write and actions: write on this fork;
# GITHUB_REPOSITORY names it.
set -euo pipefail

since_hours="${1:?Usage: copy-fresh-issues.sh <since-hours>}"
max_parallel="${MAX_PARALLEL_RUNS:-5}"
upstream="${UPSTREAM_REPOSITORY:-AdguardTeam/AdguardFilters}"
fork="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name this fork}"
script_dir="$(dirname "${BASH_SOURCE[0]}")"
products='Browser Extension|AdGuard for (Windows|Mac)'
mapping_branch='filters-agent-copies'
mapping_path='copies.tsv'

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Read the mapping (fork number, upstream number per line) and the blob sha its update needs.
read_mapping() {
    gh api "repos/${fork}/contents/${mapping_path}?ref=${mapping_branch}" > "${workdir}/mapping.json"
    jq -r '.content' "${workdir}/mapping.json" | base64 -d > "${workdir}/mapping.tsv"
}

# Append one copy to the mapping. The commit message names no issue with `#`: GitHub would add the
# commit to that issue's timeline, and an upstream one would be linked back to the copy.
record_copy() {
    local fork_number="$1" upstream_number="$2"
    read_mapping
    printf '%s\t%s\n' "${fork_number}" "${upstream_number}" >> "${workdir}/mapping.tsv"
    gh api --method PUT "repos/${fork}/contents/${mapping_path}" \
        -f branch="${mapping_branch}" \
        -f message="Record fork issue ${fork_number}" \
        -f sha="$(jq -r '.sha' "${workdir}/mapping.json")" \
        -f content="$(base64 < "${workdir}/mapping.tsv" | tr -d '\n')" > /dev/null
}

read_mapping
cut -f2 "${workdir}/mapping.tsv" | grep -E '^[0-9]+$' | sort -u > "${workdir}/copied.txt" || true

# Open upstream reports opened since the cutoff whose product line matches, oldest first.
since="$(date -u -d "${since_hours} hours ago" +%Y-%m-%dT%H:%M:%SZ)"
gh issue list --repo "${upstream}" --state open --limit 1000 --search "created:>=${since}" \
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
    created="$(bash "${script_dir}/copy-upstream-issue.sh" "${number}" "${fork}")"
    echo "${created}"
    fork_number="$(sed -n 's#^Created .*/issues/\([0-9]*\)$#\1#p' <<< "${created}")"
    record_copy "${fork_number}" "${number}"
    # A dispatch, not a label: events the workflow token causes start no workflows.
    gh workflow run filters-agent.yml --repo "${fork}" -f "issueNumber=${fork_number}"
    echo "Copied upstream #${number} as #${fork_number} and started its run"
    # A dispatched run takes a few seconds to appear in the list the slot count reads.
    sleep 15
done < "${workdir}/picked.txt"

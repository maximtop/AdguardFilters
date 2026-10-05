#!/usr/bin/env bash
# Copy the freshest open AdguardFilters reports into this fork and start a filters-agent run on
# each: a few reported from the AdGuard Browser Extension and a few from AdGuard for Windows or Mac,
# so both the extension route and the AdGuard CLI module keep getting real issues.
#
# A report already copied (its copy names it as `AdguardTeam/AdguardFilters#N`) is never copied again.
#
# Usage: copy-fresh-issues.sh <extension-count> <desktop-count>
# Needs GH_TOKEN with issues: write and actions: write on this fork; GITHUB_REPOSITORY names it.
set -euo pipefail

extension_count="${1:?Usage: copy-fresh-issues.sh <extension-count> <desktop-count>}"
desktop_count="${2:?Usage: copy-fresh-issues.sh <extension-count> <desktop-count>}"
upstream="${UPSTREAM_REPOSITORY:-AdguardTeam/AdguardFilters}"
fork="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name this fork}"
script_dir="$(dirname "${BASH_SOURCE[0]}")"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Upstream numbers already copied into the fork, read from the footer every copy carries.
gh issue list --repo "${fork}" --state all --limit 1000 --json body \
    | jq -r '.[].body' \
    | grep -oE "Copied from \`${upstream}#[0-9]+\`" \
    | grep -oE '[0-9]+`$' | tr -d '`' | sort -u > "${workdir}/copied.txt" || true

# Newest open upstream reports, with the product line their template carries.
gh issue list --repo "${upstream}" --state open --limit 100 --json number,body \
    | jq -c '.[] | {number, product: ((.body // "") | capture("AdGuard product:[^\\n]*?(?<p>AdGuard[^\\n|]*)").p // "")}' \
    > "${workdir}/candidates.jsonl"

# Pick the newest not-yet-copied reports whose product matches.
pick() {
    local pattern="$1" count="$2"
    jq -r --arg pattern "${pattern}" 'select(.product | test($pattern)) | .number' \
        "${workdir}/candidates.jsonl" \
        | grep -vxF -f "${workdir}/copied.txt" \
        | head -n "${count}" || true
}

picked=()
while IFS= read -r number; do [[ -n "${number}" ]] && picked+=("${number}"); done \
    < <(pick 'Browser Extension' "${extension_count}")
while IFS= read -r number; do [[ -n "${number}" ]] && picked+=("${number}"); done \
    < <(pick 'AdGuard for (Windows|Mac)' "${desktop_count}")

if [[ ${#picked[@]} -eq 0 ]]; then
    echo 'No fresh reports to copy.'
    exit 0
fi

# Start the agent run on one fork issue and wait until it ends. Runs go one at a time: the agent
# workflow's concurrency group keeps a single pending run and cancels any older pending one, so
# dispatching them all at once would lose every run but the first and the last.
run_agent() {
    local fork_number="$1" before run_id
    before="$(gh run list --repo "${fork}" --workflow filters-agent.yml --limit 1 \
        --json databaseId --jq '.[0].databaseId // 0')"
    gh workflow run filters-agent.yml --repo "${fork}" -f "issueNumber=${fork_number}"
    for _ in $(seq 1 30); do
        run_id="$(gh run list --repo "${fork}" --workflow filters-agent.yml --limit 1 \
            --json databaseId --jq '.[0].databaseId // 0')"
        [[ "${run_id}" != "${before}" ]] && break
        sleep 5
    done
    echo "Started filters-agent run ${run_id} on #${fork_number}"
    gh run watch "${run_id}" --repo "${fork}" --interval 60 > /dev/null || true
    echo "Run ${run_id}: $(gh run view "${run_id}" --repo "${fork}" --json conclusion --jq .conclusion)"
}

for number in "${picked[@]}"; do
    # The label alone would start no run: events the workflow token causes start no workflows.
    created="$(bash "${script_dir}/copy-upstream-issue.sh" "${number}" "${fork}")"
    echo "${created}"
    fork_number="$(sed -n 's#^Created .*/issues/\([0-9]*\)$#\1#p' <<< "${created}")"
    echo "Copied upstream #${number} as #${fork_number}"
    run_agent "${fork_number}"
done

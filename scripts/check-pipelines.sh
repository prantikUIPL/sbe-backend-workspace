#!/usr/bin/env bash
set -euo pipefail

# Check Bitbucket Pipelines status for the five SBE service repos.
#
# Auth: Atlassian API token (scoped for Bitbucket) over HTTP basic auth.
#   BB_EMAIL      -> your Atlassian account email
#   BB_API_TOKEN  -> scoped API token (read:repository:bitbucket + read:pipeline:bitbucket)
# (Bitbucket accepts API tokens only as email:token basic auth, not as a Bearer token.)
# Read from (in order):
#   1. env vars
#   2. file      scripts/.bitbucket-creds   (gitignored; KEY=VALUE lines)
#
# Usage:
#   check-pipelines.sh                       # latest pipeline per repo (all 5)
#   check-pipelines.sh <repo>                # latest pipeline for one repo
#   check-pipelines.sh <repo> --branch dev   # latest pipeline on a branch
#   check-pipelines.sh <repo> --logs <num>   # dump failed-step logs for build <num>
#
# Exit status is non-zero if any reported pipeline result is FAILED/ERROR/STOPPED.

WORKSPACE="unified-dev-cls-a"
REPOS=(admin-backend-api exhibitor-backend-api background-worker-service external-api-service pulse-broker-service)
API="https://api.bitbucket.org/2.0/repositories/${WORKSPACE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_creds() {
    if [[ -z "${BB_EMAIL:-}" || -z "${BB_API_TOKEN:-}" ]]; then
        local f="${SCRIPT_DIR}/.bitbucket-creds"
        if [[ -f "$f" ]]; then
            # shellcheck disable=SC1090
            set -a; source "$f"; set +a
        fi
    fi
    if [[ -z "${BB_EMAIL:-}" || -z "${BB_API_TOKEN:-}" ]]; then
        echo "ERROR: Bitbucket credentials not found." >&2
        echo "Set BB_EMAIL + BB_API_TOKEN, or create ${SCRIPT_DIR}/.bitbucket-creds with those keys." >&2
        exit 2
    fi
}

api() {
    # -L: step logs are served via a 307 redirect to signed storage
    curl -fsSL -u "${BB_EMAIL}:${BB_API_TOKEN}" "$@"
}

# Bitbucket pipeline/step UUIDs come wrapped in {braces}; encode for use in a URL path.
enc_uuid() { printf '%s' "$1" | sed 's/{/%7B/g; s/}/%7D/g'; }

# Print latest pipeline for one repo. Optional branch filter via $2.
report_repo() {
    local repo="$1" branch="${2:-}"
    local url="${API}/${repo}/pipelines/?sort=-created_on&pagelen=1"
    if [[ -n "$branch" ]]; then
        url="${API}/${repo}/pipelines/?sort=-created_on&pagelen=1&q=$(printf 'target.ref_name="%s"' "$branch" | jq -sRr @uri)"
    fi

    local json
    if ! json="$(api "$url" 2>/dev/null)"; then
        printf '%-28s  %s\n' "$repo" "⚠️  API error (auth/repo/network)"
        return 1
    fi

    local row
    row="$(jq -r '
        .values[0] // empty |
        [ (.build_number|tostring),
          (.state.name // "?"),
          (.state.result.name // .state.stage.name // "—"),
          ( .target.ref_name
            // (if .target.pullrequest then "PR#\(.target.pullrequest.id) \(.target.source)→\(.target.destination)" else null end)
            // .target.source
            // "?" ),
          ((.target.commit.hash // "")[0:8]),
          .uuid
        ] | @tsv' <<<"$json")"

    if [[ -z "$row" ]]; then
        printf '%-28s  %s\n' "$repo" "(no pipelines${branch:+ on $branch})"
        return 0
    fi

    IFS=$'\t' read -r num state result ref sha uuid <<<"$row"

    local icon="•"
    case "$result" in
        SUCCESSFUL) icon="✅" ;;
        FAILED|ERROR) icon="❌" ;;
        STOPPED) icon="⏹️" ;;
        *) case "$state" in IN_PROGRESS|PENDING) icon="🟡" ;; esac ;;
    esac

    printf '%-28s %s #%-5s %-11s %-26s %s\n' \
        "$repo" "$icon" "$num" "$result" "$ref" "$sha"

    case "$result" in FAILED|ERROR|STOPPED) return 1 ;; esac
    return 0
}

# Resolve a build number to its pipeline UUID. The pipelines list `q=build_number=N`
# filter is unreliable, so match client-side over pages sorted newest-first
# (build_number tracks created_on, so we can stop once we pass it).
resolve_build_uuid() {
    local repo="$1" num="$2" page=1 uuid="" minbn
    while (( page <= 20 )); do
        local json
        json="$(api "${API}/${repo}/pipelines/?sort=-created_on&pagelen=30&page=${page}")" || break
        uuid="$(jq -r --argjson n "$num" '.values[] | select(.build_number==$n) | .uuid' <<<"$json")"
        [[ -n "$uuid" ]] && { printf '%s' "$uuid"; return 0; }
        minbn="$(jq -r '[.values[].build_number] | min // empty' <<<"$json")"
        [[ -z "$minbn" || "$minbn" -lt "$num" ]] && break   # gone past it / no more pages
        ((page++))
    done
    return 1
}

# Dump failed-step logs for a given build number of a repo.
show_logs() {
    local repo="$1" num="$2"
    local uuid
    uuid="$(resolve_build_uuid "$repo" "$num")"
    if [[ -z "$uuid" ]]; then echo "Build #${num} not found in ${repo}." >&2; exit 1; fi
    local p_enc; p_enc="$(enc_uuid "$uuid")"

    local steps
    steps="$(api "${API}/${repo}/pipelines/${p_enc}/steps/")"
    echo "$steps" | jq -r '.values[] | [.uuid, .name, (.state.result.name // .state.name)] | @tsv' |
    while IFS=$'\t' read -r s_uuid s_name s_res; do
        echo
        echo "════════ STEP: ${s_name:-unnamed}  [${s_res}] ════════"
        if [[ "$s_res" == "FAILED" || "$s_res" == "ERROR" ]]; then
            api "${API}/${repo}/pipelines/${p_enc}/steps/$(enc_uuid "$s_uuid")/log" || echo "(no log available)"
        else
            echo "(passed — log skipped; pass step uuid manually to view)"
        fi
    done
}

main() {
    load_creds
    local rc=0

    if [[ $# -eq 0 ]]; then
        echo "Latest pipeline per repo (workspace: ${WORKSPACE})"
        echo "------------------------------------------------------------"
        for r in "${REPOS[@]}"; do report_repo "$r" || rc=1; done
        return $rc
    fi

    local repo="$1"; shift
    case "${1:-}" in
        --branch) report_repo "$repo" "${2:-}" || rc=1 ;;
        --logs)   show_logs "$repo" "${2:?build number required}" ;;
        "")       report_repo "$repo" || rc=1 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    return $rc
}

main "$@"

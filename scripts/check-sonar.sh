#!/usr/bin/env bash
set -euo pipefail

# Query the self-hosted SonarQube server for quality-gate status and issues,
# for the five SBE service repos. Project keys are read from each repo's
# sonar-project.properties (sonar.projectKey=...), so nothing is hardcoded.
#
# Credentials are read from env or scripts/.sonar-creds (gitignored, KEY=VALUE):
#   SONAR_HOST_URL  -> e.g. https://sonar.example.com   (the private CI variable)
#   SONAR_TOKEN     -> a SonarQube *user token* (My Account > Security)
#
# NOTE: the server (sonar.techbreeze.in) is SonarQube COMMUNITY edition, which has
# NO per-branch / per-PR analysis — every scan overwrites one main project. So this
# tool only ever reports the project's latest analysis (no --branch/--pr).
#
# Usage:
#   check-sonar.sh                # quality gate for all 5 repos (latest analysis)
#   check-sonar.sh <repo>         # quality gate for one repo
#   check-sonar.sh <repo> --issues   # list open issues (new code) + hotspots to review
#
# Exit status is non-zero if any reported gate is ERROR.

REPOS=(admin-backend-api exhibitor-backend-api background-worker-service external-api-service pulse-broker-service)
APIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${APIS_DIR}/scripts"

load_creds() {
    if [[ -z "${SONAR_HOST_URL:-}" || -z "${SONAR_TOKEN:-}" ]]; then
        local f="${SCRIPT_DIR}/.sonar-creds"
        if [[ -f "$f" ]]; then set -a; source "$f"; set +a; fi
    fi
    if [[ -z "${SONAR_HOST_URL:-}" || -z "${SONAR_TOKEN:-}" ]]; then
        echo "ERROR: SonarQube credentials not found." >&2
        echo "Set SONAR_HOST_URL + SONAR_TOKEN, or create ${SCRIPT_DIR}/.sonar-creds" >&2
        exit 2
    fi
    SONAR_HOST_URL="${SONAR_HOST_URL%/}"   # strip trailing slash
}

# SonarQube token auth = HTTP basic, token as username with empty password.
sq() { curl -fsS -u "${SONAR_TOKEN}:" "${SONAR_HOST_URL}$1"; }

project_key() {
    local repo="$1" f="${APIS_DIR}/${repo}/sonar-project.properties"
    [[ -f "$f" ]] && grep -h '^sonar.projectKey=' "$f" | cut -d= -f2- | tr -d '[:space:]'
}

# $1=repo  $2=scope query string (e.g. "&branch=dev" or "&pullRequest=272" or "")
gate() {
    local repo="$1" scope="${2:-}"
    local key; key="$(project_key "$repo")"
    if [[ -z "$key" ]]; then printf '%-28s  %s\n' "$repo" "(no sonar-project.properties)"; return 0; fi

    local json
    if ! json="$(sq "/api/qualitygates/project_status?projectKey=${key}${scope}" 2>/dev/null)"; then
        printf '%-28s  %s\n' "$repo" "⚠️  Sonar API error (auth / project / not analyzed)"
        return 1
    fi

    local status
    status="$(jq -r '.projectStatus.status' <<<"$json")"
    local icon="•"
    case "$status" in OK) icon="✅" ;; ERROR) icon="❌" ;; WARN) icon="⚠️" ;; NONE) icon="—" ;; esac
    printf '%-28s %s %s%s\n' "$repo" "$icon" "$status" "${scope:+   ($scope)}"

    # List the failing (and warning) conditions with actual vs threshold.
    jq -r '.projectStatus.conditions[]
            | select(.status=="ERROR" or .status=="WARN")
            | "      \(.status)  \(.metricKey)  actual=\(.actualValue)  \(.comparator) threshold=\(.errorThreshold)"' \
        <<<"$json"

    [[ "$status" == "ERROR" ]] && return 1
    return 0
}

list_issues() {
    local repo="$1" scope="${2:-}"
    local key; key="$(project_key "$repo")"
    [[ -z "$key" ]] && { echo "No project key for $repo"; return 0; }
    echo "Open issues (new code) for ${repo}:"
    sq "/api/issues/search?componentKeys=${key}${scope}&resolved=false&inNewCodePeriod=true&ps=100&s=SEVERITY&asc=false" \
      | jq -r '.issues[] | "  [\(.severity)/\(.type)] \(.component | sub(".*:";""))#\(.line // 0)  \(.message)  (\(.rule))  by \(.author // "?")"'
    echo
    echo "Security hotspots TO_REVIEW:"
    sq "/api/hotspots/search?projectKey=${key}${scope}&status=TO_REVIEW&ps=100" \
      | jq -r '.hotspots[]? | "  [\(.vulnerabilityProbability)] \(.component | sub(".*:";""))#\(.line // 0)  \(.message)  by \(.author // "?")"' \
      || echo "  (none / not available)"
}

main() {
    load_creds
    local rc=0

    if [[ $# -eq 0 ]]; then
        echo "Quality gate per repo (host: ${SONAR_HOST_URL})"
        echo "------------------------------------------------------------"
        for r in "${REPOS[@]}"; do gate "$r" || rc=1; done
        return $rc
    fi

    local repo="$1"; shift
    local issues=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issues) issues=1; shift ;;
            *) echo "Unknown option: $1" >&2; exit 2 ;;
        esac
    done

    if [[ "$issues" -eq 1 ]]; then
        list_issues "$repo"
    else
        gate "$repo" || rc=1
    fi
    return $rc
}

main "$@"

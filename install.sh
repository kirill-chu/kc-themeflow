#!/usr/bin/env bash
#
# kc-themeflow — installer entry point
#
# Runs the bootstrap steps in order. Each step is self-contained and
# idempotent; install.sh only orchestrates them.
#
# Usage:
#   ./install.sh                  run all steps
#   ./install.sh --plan           show plan, do nothing
#   ./install.sh --dry-run        pass --dry-run to step 50
#   ./install.sh --from 30        start from step 30
#   ./install.sh --only 50        run only step 50
#   ./install.sh --skip 40        skip step 40
#   ./install.sh --list           list available steps
#   ./install.sh --help
#
set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BOOTSTRAP_DIR="$SCRIPT_DIR/bootstrap"

# Ordered list of bootstrap steps.
readonly STEPS=(
    "00-preflight.sh"
    "10-apt-packages.sh"
    "20-uv-tools.sh"
    "40-clone-github.sh"
    "50-deploy-configs.sh"
    "60-first-run.sh"
)

# ─── Output helpers ───────────────────────────────────────────
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly NC=$'\033[0m'

ok()    { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
fail()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; }
info()  { printf "  ${BLUE}→${NC} %s\n" "$*"; }
title() { printf "\n${BOLD}▸${NC} %s\n" "$*"; }

banner() {
    printf "%s\n" "═══════════════════════════════════════════════════════════"
    printf "  %s\n" "$*"
    printf "%s\n" "═══════════════════════════════════════════════════════════"
}

# ─── Flag parsing ─────────────────────────────────────────────
FROM_STEP=""
ONLY_STEP=""
SKIP_STEPS=()
PASSTHRU_ARGS=()
PLAN_ONLY=0

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

list_steps() {
    printf "Available steps (in order):\n"
    for step in "${STEPS[@]}"; do
        printf "  %s\n" "$step"
    done
    printf "\n"
    printf "Steps are run in the order listed. Use --only <step> or --from <step>\n"
    printf "with the numeric prefix (00, 10, 20, ...).\n"
    exit 0
}

step_number() {
    # Extract leading digits from a step filename, e.g. "50-deploy-configs.sh" -> "50"
    printf '%s\n' "${1%%-*}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)     PLAN_ONLY=1; shift ;;
        --from)     FROM_STEP="$2"; shift 2 ;;
        --only)     ONLY_STEP="$2"; shift 2 ;;
        --skip)     SKIP_STEPS+=("$2"); shift 2 ;;
        --list)     list_steps ;;
        --help|-h)  usage 0 ;;
        --dry-run|--install-reference|--auto-append|--no-append)
            PASSTHRU_ARGS+=("$1")
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage 1
            ;;
    esac
done

# ─── Preconditions ────────────────────────────────────────────
printf "\n"
banner "kc-themeflow — installer"

if [[ ! -d "$BOOTSTRAP_DIR" ]]; then
    fail "Bootstrap directory not found: $BOOTSTRAP_DIR"
    exit 1
fi

if [[ ! -t 0 ]] && (( ${#PASSTHRU_ARGS[@]} == 0 )); then
    warn "stdin is not a terminal — some steps may prompt and fail"
    warn "Consider running with --install-reference --auto-append for non-interactive"
fi

if (( EUID == 0 )); then
    fail "Do not run as root. Run as a regular user with sudo access."
    exit 1
fi

# ─── Filter steps ─────────────────────────────────────────────
selected_steps=()
active=1

if [[ -n "$ONLY_STEP" ]]; then
    active=0
fi

for step in "${STEPS[@]}"; do
    num="$(step_number "$step")"

    # --only: only matching step is active
    if [[ -n "$ONLY_STEP" ]]; then
        if [[ "$num" == "$ONLY_STEP" ]]; then
            active=1
        else
            continue
        fi
    fi

    # --from: skip everything before
    if [[ -n "$FROM_STEP" && "$num" < "$FROM_STEP" ]]; then
        continue
    fi

    # --skip: skip listed steps (may be specified by number or filename)
    skip=0
    for s in "${SKIP_STEPS[@]}"; do
        if [[ "$num" == "$s" || "$step" == "$s" ]]; then
            skip=1
            break
        fi
    done
    (( skip )) && continue

    selected_steps+=("$step")
done

if (( ${#selected_steps[@]} == 0 )); then
    fail "No steps selected. Check --from / --only / --skip arguments."
    exit 1
fi

# ─── Show plan ────────────────────────────────────────────────
title "Plan"

for step in "${selected_steps[@]}"; do
    path="$BOOTSTRAP_DIR/$step"
    if [[ ! -x "$path" ]]; then
        printf "  ${RED}✗${NC} %s  ${DIM}(not found or not executable)${NC}\n" "$step"
    else
        printf "  ${BLUE}▸${NC} %s\n" "$step"
    fi
done

if (( PLAN_ONLY )); then
    printf "\n  ${DIM}Plan only — nothing will be executed.${NC}\n\n"
    exit 0
fi

if (( ${#PASSTHRU_ARGS[@]} > 0 )); then
    printf "\n  ${DIM}Passing through to step 50: %s${NC}\n" "${PASSTHRU_ARGS[*]}"
fi

# ─── Pre-flight sanity check ──────────────────────────────────
missing=0
for step in "${selected_steps[@]}"; do
    path="$BOOTSTRAP_DIR/$step"
    if [[ ! -x "$path" ]]; then
        missing=1
    fi
done

if (( missing )); then
    fail "One or more selected steps are missing or not executable."
    info "Ensure all files in bootstrap/ have the +x bit set:"
    info "    chmod +x bootstrap/*.sh"
    exit 1
fi

# ─── Run steps ────────────────────────────────────────────────
start_time=$(date +%s)

for step in "${selected_steps[@]}"; do
    path="$BOOTSTRAP_DIR/$step"

    # Compute elapsed for the previous step
    printf "\n"
    banner "$step"
    printf "\n"

    step_start=$(date +%s)

    # Only step 50 accepts our passthru flags. Others are called plainly.
    if [[ "$step" == "50-deploy-configs.sh" ]] && (( ${#PASSTHRU_ARGS[@]} > 0 )); then
        if ! "$path" "${PASSTHRU_ARGS[@]}"; then
            rc=$?
            fail "$step failed (exit code $rc)"
            exit "$rc"
        fi
    else
        if ! "$path"; then
            rc=$?
            fail "$step failed (exit code $rc)"
            exit "$rc"
        fi
    fi

    step_end=$(date +%s)
    printf "\n  ${DIM}%s finished in %ds${NC}\n" \
        "$step" "$(( step_end - step_start ))"
done

# ─── Summary ──────────────────────────────────────────────────
end_time=$(date +%s)
total=$(( end_time - start_time ))
mins=$(( total / 60 ))
secs=$(( total % 60 ))

printf "\n"
banner "Installation complete"

printf "  Steps run:   %d\n" "${#selected_steps[@]}"
printf "  Total time:  ${mins}m ${secs}s\n"

printf "\n  ${BOLD}Next steps:${NC}\n"
printf "    • Apply a theme:      ${BOLD}kc-themeflow -i <wallpaper>${NC}\n"
printf "    • Load a theme:       ${BOLD}kc-themeflow -f <theme.json>${NC}\n"
printf "    • Read manual steps:  ${BOLD}docs/manual-steps.md${NC}\n"
printf "\n"

exit 0
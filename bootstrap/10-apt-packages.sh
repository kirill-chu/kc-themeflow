#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 10: APT packages
#
# Installs system packages declared in deps.toml:
#
#   [apt.required]   install and fail on error
#   [apt.optional]   install silently if missing, do not fail on error
#   [apt.present]    check only, warn if missing
#
# Assumes bootstrap/00-preflight.sh has passed.
# Idempotent: safe to run multiple times.
#
# Requires: sudo, python3 with tomllib (Python 3.11+).
#

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEPS_FILE="$PROJECT_ROOT/deps.toml"

# ─── Output helpers ───────────────────────────────────────────
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly BOLD=$'\033[1m'
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

# ─── Preconditions ────────────────────────────────────────────
printf "\n"
banner "kc-themeflow — bootstrap 10: APT packages"

if [[ ! -f "$DEPS_FILE" ]]; then
    fail "deps.toml not found: $DEPS_FILE"
    exit 1
fi

if ! python3 -c 'import tomllib' 2>/dev/null; then
    fail "python3 tomllib module not available (need Python 3.11+)"
    exit 1
fi

# ─── TOML parsing ─────────────────────────────────────────────
# get_packages <section>
# Prints one package name per line from <section>.packages.
get_packages() {
    local section="$1"
    python3 - "$DEPS_FILE" "$section" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

node = data
for key in sys.argv[2].split("."):
    if not isinstance(node, dict):
        node = {}
        break
    node = node.get(key, {})

for pkg in node.get("packages", []):
    print(pkg)
PY
}

# is_installed <package>
is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# filter_missing — reads package names from stdin, prints those not installed.
filter_missing() {
    local pkg
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if ! is_installed "$pkg"; then
            printf '%s\n' "$pkg"
        fi
    done
}

# ─── Parse deps.toml ──────────────────────────────────────────
mapfile -t required_all < <(get_packages "apt.required")
mapfile -t optional_all < <(get_packages "apt.optional")
mapfile -t present_all  < <(get_packages "apt.present")

mapfile -t required_missing < <(printf '%s\n' "${required_all[@]:-}" | filter_missing)
mapfile -t optional_missing < <(printf '%s\n' "${optional_all[@]:-}" | filter_missing)

# ─── Report what was found ────────────────────────────────────
title "Required packages"
if [[ ${#required_all[@]} -eq 0 ]]; then
    warn "No required packages declared in deps.toml"
elif [[ ${#required_missing[@]} -eq 0 ]]; then
    ok "All ${#required_all[@]} required packages already installed"
else
    info "Missing: ${required_missing[*]}"
fi

title "Optional packages"
if [[ ${#optional_all[@]} -eq 0 ]]; then
    ok "No optional packages declared"
elif [[ ${#optional_missing[@]} -eq 0 ]]; then
    ok "All ${#optional_all[@]} optional packages already installed"
else
    info "Missing: ${optional_missing[*]}"
fi

# ─── apt-get update (only if something needs installing) ──────
need_install=0
if [[ ${#required_missing[@]} -gt 0 ]] || [[ ${#optional_missing[@]} -gt 0 ]]; then
    need_install=1
fi

if (( need_install )); then
    title "Updating apt cache"
    if sudo apt-get update -qq; then
        ok "apt cache updated"
    else
        fail "apt-get update failed"
        exit 1
    fi
fi

# ─── Install required ─────────────────────────────────────────
if [[ ${#required_missing[@]} -gt 0 ]]; then
    title "Installing required packages"
    info "${required_missing[*]}"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            "${required_missing[@]}"; then
        ok "Required packages installed"
    else
        fail "Failed to install required packages"
        exit 1
    fi
fi

# ─── Install optional (batch, then fallback to per-package) ───
if [[ ${#optional_missing[@]} -gt 0 ]]; then
    title "Installing optional packages"
    info "${optional_missing[*]}"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            "${optional_missing[@]}" 2>/dev/null; then
        ok "Optional packages installed"
    else
        warn "Batch install failed, retrying individually..."
        for pkg in "${optional_missing[@]}"; do
            if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    "$pkg" >/dev/null 2>&1; then
                ok "Installed: $pkg"
            else
                warn "Failed: $pkg"
            fi
        done
    fi
fi

# ─── Check presence-only ──────────────────────────────────────
title "Presence check (manual install required)"
present_missing=()
for pkg in "${present_all[@]:-}"; do
    [[ -z "$pkg" ]] && continue
    if ! is_installed "$pkg"; then
        present_missing+=("$pkg")
    fi
done

if [[ ${#present_all[@]} -eq 0 ]]; then
    ok "No presence-only packages declared"
elif [[ ${#present_missing[@]} -eq 0 ]]; then
    ok "All presence-only packages present"
else
    for pkg in "${present_missing[@]}"; do
        warn "Not installed: $pkg — see docs/manual-steps.md"
    done
fi

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

if (( need_install )); then
    req_installed=${#required_missing[@]}
    req_present=$(( ${#required_all[@]} - ${#required_missing[@]} ))
    opt_installed=${#optional_missing[@]}
    opt_present=$(( ${#optional_all[@]} - ${#optional_missing[@]} ))

    printf "  Required: %d installed, %d already present\n" \
        "$req_installed" "$req_present"
    printf "  Optional: %d installed, %d already present\n" \
        "$opt_installed" "$opt_present"
else
    printf "  All packages already installed. Nothing to do.\n"
fi

printf "\n  Next step: ${BOLD}bootstrap/20-uv-tools.sh${NC}\n\n"

exit 0

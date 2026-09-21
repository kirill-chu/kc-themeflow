#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 20: uv and Python tools
#
# Installs:
#   - uv (Astral's Python tool installer), if not already available
#   - pywal16 as a uv tool (provides the `wal` command)
#
# Reads: deps.toml ([uv.bootstrap], [uv.tools])
# Idempotent: safe to run multiple times.
#
# Requires: bootstrap/00-preflight.sh has passed, bootstrap/10-apt-packages.sh
# has installed curl and python3.
#

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEPS_FILE="$PROJECT_ROOT/deps.toml"
readonly LOCAL_BIN="$HOME/.local/bin"

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
banner "kc-themeflow — bootstrap 20: uv and Python tools"

if [[ ! -f "$DEPS_FILE" ]]; then
    fail "deps.toml not found: $DEPS_FILE"
    exit 1
fi

# ─── Read deps.toml ───────────────────────────────────────────
# get_uv_bootstrap_url — prints installer URL from [uv.bootstrap].
# get_uv_tools — prints "name<TAB>spec" lines from [uv.tools].
get_uv_bootstrap_url() {
    python3 - "$DEPS_FILE" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
node = data.get("uv", {}).get("bootstrap", {})
print(node.get("installer_url", ""))
PY
}

get_uv_tools() {
    python3 - "$DEPS_FILE" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
tools = data.get("uv", {}).get("tools", {})
for name, spec in tools.items():
    print(f"{name}\t{spec}")
PY
}

readonly UV_INSTALLER_URL="$(get_uv_bootstrap_url)"
mapfile -t UV_TOOLS < <(get_uv_tools)

# ─── Ensure ~/.local/bin exists and is in PATH ────────────────
title "Environment"
if [[ ! -d "$LOCAL_BIN" ]]; then
    mkdir -p "$LOCAL_BIN"
    ok "Created: $LOCAL_BIN"
else
    ok "Exists: $LOCAL_BIN"
fi

if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    warn "$LOCAL_BIN is not in PATH for this session"
    info "Adding it for the current script run only"
    info "Make it permanent: add to ~/.xsessionrc (see config/xsessionrc)"
    export PATH="$LOCAL_BIN:$PATH"
else
    ok "$LOCAL_BIN is in PATH"
fi

# ─── Install uv if missing ────────────────────────────────────
title "uv"
uv_installed=0

if command -v uv >/dev/null 2>&1; then
    uv_version="$(uv --version 2>/dev/null | awk '{print $2}')"
    ok "uv already installed: $uv_version"
    uv_installed=1
else
    if [[ -z "$UV_INSTALLER_URL" ]]; then
        fail "uv not installed and no installer_url in deps.toml"
        exit 1
    fi

    info "Installing uv from: $UV_INSTALLER_URL"
    if curl -LsSf "$UV_INSTALLER_URL" | sh 2>&1 | grep -vE '^\s*$'; then
        # The installer puts uv into ~/.local/bin. Hash the new PATH.
        hash -r
        if command -v uv >/dev/null 2>&1; then
            uv_version="$(uv --version 2>/dev/null | awk '{print $2}')"
            ok "uv installed: $uv_version"
            uv_installed=1
        else
            fail "uv installer reported success but uv is not in PATH"
            info "Expected location: $LOCAL_BIN/uv"
            exit 1
        fi
    else
        fail "uv installer failed"
        exit 1
    fi
fi

# ─── Install each uv tool ─────────────────────────────────────
title "uv tools"

if [[ ${#UV_TOOLS[@]} -eq 0 ]]; then
    warn "No uv tools declared in deps.toml [uv.tools]"
fi

# is_uv_tool_installed <name> — checks `uv tool list` for a matching entry
is_uv_tool_installed() {
    local name="$1"
    uv tool list 2>/dev/null | grep -qE "^${name} v[0-9]"
}

for entry in "${UV_TOOLS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    name="${entry%%$'\t'*}"
    spec="${entry#*$'\t'}"

    if is_uv_tool_installed "$name"; then
        ver="$(uv tool list 2>/dev/null | grep -E "^${name} v[0-9]" | head -n1 | awk '{print $2}')"
        ok "$name already installed ($ver)"
        continue
    fi

    info "Installing $name from: $spec"
    if uv tool install --force --from "$spec" "$name" >/dev/null 2>&1; then
        ver="$(uv tool list 2>/dev/null | grep -E "^${name} v[0-9]" | head -n1 | awk '{print $2}')"
        ok "$name installed ($ver)"
    else
        fail "Failed to install $name"
        exit 1
    fi
done

# ─── Verify the `wal` command is available ───────────────────
title "Verification"

if command -v wal >/dev/null 2>&1; then
    wal_path="$(command -v wal)"
    wal_version="$(wal --version 2>/dev/null | head -n1 || true)"
    ok "wal: $wal_path"
    [[ -n "$wal_version" ]] && info "Version: $wal_version"
else
    fail "wal command not found in PATH"
    info "pywal16 was installed as a uv tool but its entry point is missing"
    info "Expected: $LOCAL_BIN/wal"
    exit 1
fi

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

printf "  uv:        %s\n" "$(command -v uv)"

tool_names=()
for entry in "${UV_TOOLS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    tool_names+=("${entry%%$'\t'*}")
done
printf "  tools:     %s\n" "${tool_names[*]:-none}"

printf "  wal:       %s\n" "$(command -v wal)"

printf "\n  Next step: ${BOLD}bootstrap/40-clone-github.sh${NC}\n\n"

exit 0

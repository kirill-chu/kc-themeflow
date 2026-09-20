#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 30: Flatpak applications
#
# Adds the configured Flatpak remote and installs required applications:
#
#   [flatpak.remote]   remote name and URL (added if missing)
#   [flatpak.apps]     required applications
#
# Assumes flatpak was installed by bootstrap/10-apt-packages.sh.
# Idempotent: safe to run multiple times.
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
banner "kc-themeflow — bootstrap 30: Flatpak applications"

if [[ ! -f "$DEPS_FILE" ]]; then
    fail "deps.toml not found: $DEPS_FILE"
    exit 1
fi

if ! command -v flatpak >/dev/null 2>&1; then
    fail "flatpak not found — run bootstrap/10-apt-packages.sh first"
    exit 1
fi

# ─── Read deps.toml ───────────────────────────────────────────
get_flatpak_remote() {
    python3 - "$DEPS_FILE" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
node = data.get("flatpak", {}).get("remote", {})
print(node.get("name", ""))
print(node.get("url", ""))
PY
}

get_flatpak_apps() {
    python3 - "$DEPS_FILE" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
apps = data.get("flatpak", {}).get("apps", {}).get("required", [])
for app in apps:
    print(app)
PY
}

mapfile -t REMOTE < <(get_flatpak_remote)
readonly REMOTE_NAME="${REMOTE[0]:-}"
readonly REMOTE_URL="${REMOTE[1]:-}"

mapfile -t APPS < <(get_flatpak_apps)

# ─── Remote ───────────────────────────────────────────────────
title "Flatpak remote"

if [[ -z "$REMOTE_NAME" || -z "$REMOTE_URL" ]]; then
    fail "No [flatpak.remote] declared in deps.toml"
    exit 1
fi

if flatpak remote-list 2>/dev/null | awk '{print $1}' | grep -qx "$REMOTE_NAME"; then
    ok "Remote already configured: $REMOTE_NAME"
else
    info "Adding remote: $REMOTE_NAME"
    if flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"; then
        ok "Remote added: $REMOTE_NAME"
    else
        fail "Failed to add remote: $REMOTE_NAME"
        exit 1
    fi
fi

# ─── Applications ─────────────────────────────────────────────
title "Applications"

if [[ ${#APPS[@]} -eq 0 ]]; then
    warn "No required Flatpak applications declared in deps.toml"
fi

is_flatpak_installed() {
    local app_id="$1"
    flatpak list --app --columns=application 2>/dev/null | grep -qx "$app_id"
}

installed_count=0
skipped_count=0

for app in "${APPS[@]:-}"; do
    [[ -z "$app" ]] && continue

    if is_flatpak_installed "$app"; then
        ok "$app already installed"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    info "Installing: $app (this may take a while)"
    if flatpak install -y --noninteractive "$REMOTE_NAME" "$app" >/dev/null 2>&1; then
        ok "$app installed"
        installed_count=$((installed_count + 1))
    else
        fail "Failed to install: $app"
        info "Retry manually: flatpak install $REMOTE_NAME $app"
        exit 1
    fi
done

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

printf "  Remote:           %s\n" "$REMOTE_NAME"
printf "  Installed:        %d\n" "$installed_count"
printf "  Already present:  %d\n" "$skipped_count"

printf "\n  Next step: ${BOLD}bootstrap/40-clone-github.sh${NC}\n\n"

exit 0

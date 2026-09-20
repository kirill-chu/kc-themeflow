#!/usr/bin/env bash
#
# kc-themeflow — preflight check
#
# Verifies that the current system meets the requirements of kc-themeflow.
# Run this before any other bootstrap step.
#
# This script is READ-ONLY: it does not install, modify, or delete anything.
# Exit codes:
#   0  all checks passed (warnings allowed)
#   1  one or more checks failed
#

set -euo pipefail

# ─── Output helpers ───────────────────────────────────────────
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly BOLD=$'\033[1m'
readonly NC=$'\033[0m'

PASS=0
WARN=0
FAIL=0

ok()    { printf "  ${GREEN}✓${NC} %s\n" "$*"; PASS=$((PASS + 1)); }
warn()  { printf "  ${YELLOW}!${NC} %s\n" "$*"; WARN=$((WARN + 1)); }
fail()  { printf "  ${RED}✗${NC} %s\n" "$*"; FAIL=$((FAIL + 1)); }
title() { printf "\n${BOLD}▸${NC} %s\n" "$*"; }

banner() {
    printf "%s\n" "═══════════════════════════════════════════════════════════"
    printf "  %s\n" "$*"
    printf "%s\n" "═══════════════════════════════════════════════════════════"
}

# ─── Header ───────────────────────────────────────────────────
printf "\n"
banner "kc-themeflow — preflight check"

# ─── 1. Distribution ──────────────────────────────────────────
title "Distribution"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "debian" ]]; then
        ok "Debian ${VERSION_ID:-?} (${VERSION_CODENAME:-unknown})"
    else
        warn "Distribution: ${ID:-unknown} — only Debian is tested"
    fi
else
    fail "/etc/os-release not found — cannot determine distribution"
fi

if command -v dpkg >/dev/null 2>&1; then
    arch="$(dpkg --print-architecture)"
    if [[ "$arch" == "amd64" ]]; then
        ok "Architecture: $arch"
    else
        warn "Architecture: $arch — only amd64 is tested"
    fi
else
    fail "dpkg not found — this does not look like a Debian system"
fi

# ─── 2. User and privileges ───────────────────────────────────
title "User and privileges"

if [[ "$EUID" -eq 0 ]]; then
    fail "Running as root — run as a regular user with sudo access"
else
    ok "Regular user: ${USER:-unknown}"
fi

if command -v sudo >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
        ok "Passwordless sudo is available"
    else
        ok "sudo available (password will be requested when needed)"
    fi
else
    fail "sudo not found"
fi

# ─── 3. Network connectivity ──────────────────────────────────
title "Network connectivity"

# Some hosts may be intermittently unreachable due to sanctions, VPN
# routing, or transient network hiccups. Retry each check a few times
# before declaring the host unreachable.
NET_ATTEMPTS=3
NET_TIMEOUT=10
NET_DELAY=1
NET_UA="kc-themeflow/0.1"

check_url() {
    local name="$1"
    local url="$2"
    local attempt

    for attempt in $(seq 1 "$NET_ATTEMPTS"); do
        if curl -fsSL --max-time "$NET_TIMEOUT" -A "$NET_UA" \
                -o /dev/null "$url" 2>/dev/null; then
            if (( attempt == 1 )); then
                ok "$name"
            else
                ok "$name (after $attempt attempts)"
            fi
            return 0
        fi
        if (( attempt < NET_ATTEMPTS )); then
            sleep "$NET_DELAY"
        fi
    done

    fail "$name — unreachable after $NET_ATTEMPTS attempts"
    printf "    ${YELLOW}↳${NC} If the host is blocked by sanctions or a VPN, enable it and re-run.\n"
}

check_url "deb.debian.org" "https://deb.debian.org"
check_url "github.com"     "https://github.com"
check_url "flathub.org"    "https://flathub.org"
check_url "astral.sh"      "https://astral.sh"

# ─── 4. Free disk space ───────────────────────────────────────
title "Disk space"

# kc-themeflow needs roughly:
#     ~100 MB  uv tools + github clones (pywal16, pywalium, adw-gtk3)
#     ~200 MB  flatpak apps, if installed per-user
#     ~200 MB  headroom for caches and generated files
# Minimum: 500 MB free in $HOME.
MIN_FREE_MB=500

if [[ -d "$HOME" ]]; then
    avail_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
    avail_mb=$((avail_kb / 1024))
    if (( avail_mb >= MIN_FREE_MB )); then
        ok "Free space in \$HOME: ${avail_mb} MiB"
    else
        fail "Free space in \$HOME: ${avail_mb} MiB — at least ${MIN_FREE_MB} MiB required"
    fi
fi

# ─── 5. Base tools ────────────────────────────────────────────
title "Base tools"

for tool in bash curl git apt dpkg sudo python3; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        fail "$tool — not found"
    fi
done

# ─── 6. Python version ────────────────────────────────────────
title "Python"

# kc-themeflow reads deps.toml through tomllib, which is part of the
# standard library only since Python 3.11. Python 3.10 would require
# an external tomli dependency, which we deliberately avoid.
PY_MIN_MAJOR=3
PY_MIN_MINOR=11

if command -v python3 >/dev/null 2>&1; then
    py_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    py_major="$(python3 -c 'import sys; print(sys.version_info.major)')"
    py_minor="$(python3 -c 'import sys; print(sys.version_info.minor)')"

    if (( py_major > PY_MIN_MAJOR )) || \
       (( py_major == PY_MIN_MAJOR && py_minor >= PY_MIN_MINOR )); then
        ok "Python $py_version"

        if python3 -c 'import tomllib' 2>/dev/null; then
            ok "tomllib available (used to parse deps.toml)"
        else
            fail "tomllib not importable — this is unexpected on Python >= 3.11"
        fi
    else
        fail "Python $py_version — version ${PY_MIN_MAJOR}.${PY_MIN_MINOR}+ required"
        printf "    ${YELLOW}↳${NC} kc-themeflow reads deps.toml via tomllib (stdlib since 3.11).\n"
        printf "    ${YELLOW}↳${NC} On Debian 13 python3 is 3.13 by default; upgrade if possible.\n"
    fi
else
    fail "python3 not found in PATH"
fi

# ─── 7. X11 session ───────────────────────────────────────────
title "Session"

session_type="${XDG_SESSION_TYPE:-unknown}"
case "$session_type" in
    x11)
        ok "Session type: x11"
        ;;
    wayland)
        warn "Session type: wayland — kc-themeflow targets x11"
        ;;
    *)
        warn "Session type: $session_type (unknown)"
        ;;
esac

if [[ -n "${DISPLAY:-}" ]]; then
    ok "DISPLAY=$DISPLAY"
else
    warn "DISPLAY is not set — not running inside an X session"
fi

# ─── 8. Directory layout ──────────────────────────────────────
title "Directory layout"

for d in "$HOME/.config" "$HOME/.local" "$HOME/.local/bin" "$HOME/.cache"; do
    if [[ -d "$d" ]]; then
        ok "Exists: $d"
    else
        warn "Missing: $d (will be created by the bootstrap)"
    fi
done

# ─── 9. PATH sanity ───────────────────────────────────────────
title "PATH"

if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    ok "\$HOME/.local/bin is in PATH"
else
    warn "\$HOME/.local/bin is not in PATH (add it to ~/.xsessionrc)"
fi

# ─── 10. Flatpak ──────────────────────────────────────────────
title "Flatpak"

if command -v flatpak >/dev/null 2>&1; then
    ok "flatpak $(flatpak --version 2>/dev/null | awk '{print $2}')"

    if flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
        ok "flathub remote is configured"
    else
        warn "flathub remote is not configured (will be added by the bootstrap)"
    fi
else
    fail "flatpak not found — required for Gradience"
fi

# ─── 11. Optional tools already present ───────────────────────
title "Optional tools (checked, not required by preflight)"

for tool in feh qt6ct alacritty dunst rofi keepassxc kvantummanager; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "Installed: $tool"
    else
        warn "Not installed: $tool (the bootstrap can install it)"
    fi
done

# ─── 12. Existing kc-themeflow artifacts ─────────────────────
title "Existing kc-themeflow artifacts"

if [[ -f "$HOME/.config/qtile/custom_utils/colors.py" ]]; then
    if head -n1 "$HOME/.config/qtile/custom_utils/colors.py" | grep -q "kc-themeflow"; then
        ok "colors.py already generated by kc-themeflow"
    else
        warn "colors.py exists but is not managed by kc-themeflow"
    fi
else
    ok "No previous colors.py — clean install"
fi

if [[ -d "$HOME/.config/Kvantum/pywal" ]]; then
    ok "Existing Kvantum theme found — will be overwritten"
else
    ok "No previous Kvantum theme"
fi

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Summary"

printf "  ${GREEN}Pass: %d${NC}   ${YELLOW}Warn: %d${NC}   ${RED}Fail: %d${NC}\n" \
    "$PASS" "$WARN" "$FAIL"

if (( FAIL > 0 )); then
    printf "\n  ${RED}Preflight failed.${NC} Fix the errors above and re-run.\n\n"
    exit 1
fi

if (( WARN > 0 )); then
    printf "\n  ${YELLOW}Preflight passed with warnings.${NC} Review them before continuing.\n"
    printf "  Next step: ${BOLD}bootstrap/10-apt-packages.sh${NC}\n\n"
else
    printf "\n  ${GREEN}Preflight passed.${NC}\n"
    printf "  Next step: ${BOLD}bootstrap/10-apt-packages.sh${NC}\n\n"
fi

exit 0

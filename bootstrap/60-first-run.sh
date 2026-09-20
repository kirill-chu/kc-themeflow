#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 60: first run
#
# Runs the theme pipeline for the first time, so that all generated
# files exist before the user starts working.
#
# If a pywal cache already exists, does nothing.
# Otherwise, looks for a default wallpaper and applies it.
#
# Idempotent: safe to run multiple times.
#
set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEPS_FILE="$PROJECT_ROOT/deps.toml"
readonly WAL_CACHE="$HOME/.cache/wal/colors.json"
readonly SET_THEME="$HOME/.local/share/kc-themeflow/runtime/set_theme.sh"

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

# ─── Read wallpaper directory from deps.toml ──────────────────
read_wallpaper_dir() {
    [[ -f "$DEPS_FILE" ]] || { printf '%s\n' "$HOME/Pictures/wallpapers"; return; }
    python3 - "$DEPS_FILE" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(0)
val = data.get("assets", {}).get("wallpapers_dir", "")
if isinstance(val, str):
    print(val)
PY
}

# ─── Preconditions ────────────────────────────────────────────
printf "\n"
banner "kc-themeflow — bootstrap 60: first run"

if [[ ! -x "$SET_THEME" ]]; then
    fail "set_theme.sh not found: $SET_THEME"
    info "Run bootstrap/50-deploy-configs.sh first"
    exit 1
fi

# ─── Already initialized? ─────────────────────────────────────
if [[ -f "$WAL_CACHE" ]]; then
    ok "Pywal cache already exists: $WAL_CACHE"
    info "Nothing to do — run 'kc-themeflow -i <wallpaper>' to change theme"
    printf "\n"
    exit 0
fi

# ─── Find a default wallpaper ─────────────────────────────────
title "Looking for a default wallpaper"

wallpaper_dir="$(read_wallpaper_dir)"
wallpaper_dir="${wallpaper_dir/#\~/$HOME}"

info "Search directory: $wallpaper_dir"

wallpaper=""
if [[ -d "$wallpaper_dir" ]]; then
    # Pick the first regular image file, sorted alphabetically
    while IFS= read -r f; do
        wallpaper="$f"
        break
    done < <(find "$wallpaper_dir" -maxdepth 1 -type f \
             \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
             | sort)
fi

if [[ -z "$wallpaper" ]]; then
    warn "No wallpaper found in: $wallpaper_dir"
    info "Place an image there, then run:"
    info "    kc-themeflow -i $wallpaper_dir/<your-wallpaper>"
    printf "\n"
    info "Alternatively, run kc-themeflow with an existing theme JSON:"
    info "    kc-themeflow -f <theme.json>"
    printf "\n"
    exit 0
fi

ok "Selected: $wallpaper"

# ─── Run the pipeline ─────────────────────────────────────────
title "Applying theme"
printf "\n"
"$SET_THEME" -i "$wallpaper"

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

printf "  Wallpaper:  %s\n" "$wallpaper"
printf "  Palette:    %s\n" "$WAL_CACHE"

printf "\n  kc-themeflow is ready. To change theme later:\n"
printf "      ${BOLD}kc-themeflow -i <wallpaper>${NC}\n"
printf "      ${BOLD}kc-themeflow -f <theme.json>${NC}\n\n"

exit 0

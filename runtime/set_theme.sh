#!/usr/bin/env bash
#
# kc-themeflow — theme pipeline orchestrator
#
# Generates a color palette (from a wallpaper or a prepared JSON file)
# and applies it to every supported application in the environment.
#
# Usage:
#   set_theme.sh -i /path/to/wallpaper.jpg
#   set_theme.sh -f /path/to/theme.json
#   set_theme.sh -i wall.jpg --hover=border --no-wallpaper
#
# Options:
#   -i <file>          Generate palette from image and set as wallpaper
#   -f <file>          Use palette from a prepared pywal JSON file
#   --hover=soft       Kvantum hover style: soft (default) or border
#   --no-wallpaper     With -i, apply theme only; do not set wallpaper
#   -h, --help         Show this help
#
set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly WAL_CACHE="$CACHE_HOME/wal"

readonly QTILE_COLORS_SCRIPT="$SCRIPT_DIR/qtile_colors.py"
readonly KVANTUM_SCRIPT="$SCRIPT_DIR/kvantum_build.py"

readonly GRADIENCE_PRESET="$HOME/.var/app/com.github.GradienceTeam.Gradience/config/presets/user/pywal.json"
readonly PREFS_FILE="$HOME/.config/kc-themeflow/preferences.toml"

# Read github_dir from preferences.toml, falling back to ~/githubs.
read_github_dir() {
    local default="$HOME/githubs"
    [[ -f "$PREFS_FILE" ]] || { printf '%s\n' "$default"; return; }
    local val
    val="$(python3 - "$PREFS_FILE" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(0)
node = data.get("paths", {}).get("github_dir")
if isinstance(node, str):
    print(node)
PY
)"
    printf '%s\n' "${val:-$default}"
}

readonly GITHUB_DIR="$(read_github_dir)"
readonly PYWALIUM_DIR="$GITHUB_DIR/pywalium"

# ─── Subcommand routing ───────────────────────────────────────
# kc-themeflow supports subcommands alongside the default theme
# pipeline. When the first argument is "tool", the second argument
# selects a utility; the rest are passed to it.
#
#   kc-themeflow tool al-conv --input file.yml
#
# Otherwise, the script runs the theme pipeline as usual.

if [[ "${1:-}" == "tool" ]]; then
    shift
    tool_name="${1:-}"
    shift || true
    case "$tool_name" in
        al-conv)
            exec python3 "$SCRIPT_DIR/tools/convert_alacritty.py" "$@"
            ;;
        "")
            echo "Usage: kc-themeflow tool <name> [args]" >&2
            echo "Available tools: al-conv" >&2
            exit 1
            ;;
        *)
            echo "Unknown tool: $tool_name" >&2
            echo "Available tools: al-conv" >&2
            exit 1
            ;;
    esac
fi

# ─── Argument parsing ─────────────────────────────────────────
MODE=""
SOURCE=""
HOVER="soft"
NO_WALLPAPER=0

usage() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) MODE="image"; SOURCE="$2"; shift 2 ;;
        -f) MODE="file";  SOURCE="$2"; shift 2 ;;
        --hover=*) HOVER="${1#--hover=}"; shift ;;
        --no-wallpaper) NO_WALLPAPER=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -n "$MODE" && -n "$SOURCE" ]] || { echo "Missing -i or -f" >&2; usage 1; }
[[ -f "$SOURCE" ]] || { echo "File not found: $SOURCE" >&2; exit 1; }

# ─── Helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }

# find_wal_file <basename>
# Prints the path to a file rendered by pywal in ~/.cache/wal/.
# Returns non-zero if not found.
find_wal_file() {
    local name="$1"
    local path="$WAL_CACHE/$name"
    [[ -f "$path" ]] && printf '%s\n' "$path"
}

# install_theme_file <wal-file> <target>
# Copies a rendered theme file to its target location, creating the
# directory if needed.
install_theme_file() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        warn "Source not found: $src"
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    log "Updated: $dst"
}

# ─── 1. Wallpaper ─────────────────────────────────────────────
if [[ "$MODE" == "image" && "$NO_WALLPAPER" -eq 0 ]]; then
    log "Setting wallpaper: $SOURCE"
    feh --bg-fill "$SOURCE"
fi

# ─── 2. Generate palette ──────────────────────────────────────
log "Generating palette..."
if [[ "$MODE" == "image" ]]; then
    wal -i "$SOURCE" --cols16
else
    wal -f "$SOURCE" --cols16
fi

# ─── 3. Qtile ─────────────────────────────────────────────────
log "Updating Qtile colors..."
python3 "$QTILE_COLORS_SCRIPT"

if pgrep -x qtile >/dev/null; then
    qtile cmd-obj -o cmd -f reload_config 2>/dev/null || true
fi

# ─── 4. Alacritty ─────────────────────────────────────────────
log "Updating alacritty theme..."
if alacritty_src="$(find_wal_file 'alacritty-theme.toml')"; then
    install_theme_file "$alacritty_src" "$CONFIG_HOME/alacritty/current-theme.toml"
else
    warn "alacritty-theme.toml not rendered. Is the template installed?"
    warn "Expected at: $WAL_CACHE/alacritty-theme.toml"
fi

# ─── 5. Rofi ──────────────────────────────────────────────────
log "Updating rofi theme..."
if rofi_src="$(find_wal_file 'rofi-theme.rasi')"; then
    install_theme_file "$rofi_src" "$CONFIG_HOME/rofi/current-theme.rasi"
else
    warn "rofi-theme.rasi not rendered. Is the template installed?"
fi

# ─── 6. Dunst ─────────────────────────────────────────────────
log "Updating dunst theme..."
if dunst_src="$(find_wal_file 'dunst-theme.dunstrc')"; then
    install_theme_file "$dunst_src" "$CONFIG_HOME/dunst/dunstrc"
else
    warn "dunst-theme.dunstrc not rendered. Is the template installed?"
fi

# Restart dunst entirely. SIGUSR1 only reloads the config dunst
# already has in memory; it does not re-resolve the config path.
# stderr is redirected so warnings (e.g. missing icons) do not
# leak into the terminal that invoked set_theme.sh.
pkill -x dunst 2>/dev/null || true
sleep 0.2
dunst >/dev/null 2>&1 &

# ─── 7. GTK 3 / GTK 4 via Gradience ───────────────────────────
log "Applying GTK theme via Gradience..."
if [[ -f "$WAL_CACHE/pywal.json" ]]; then
    mkdir -p "$(dirname "$GRADIENCE_PRESET")"
    cp -f "$WAL_CACHE/pywal.json" "$GRADIENCE_PRESET"
    if command -v flatpak >/dev/null; then
        flatpak run --command=gradience-cli com.github.GradienceTeam.Gradience \
            apply -n "pywal" --gtk both >/dev/null 2>&1 \
            || warn "Gradience apply failed — is the flatpak installed?"
    fi
else
    warn "pywal.json not rendered. Is the Gradience template installed?"
fi

# ─── 8. Qt via Kvantum ────────────────────────────────────────
log "Building Kvantum theme (hover=$HOVER)..."
python3 "$KVANTUM_SCRIPT" --hover="$HOVER"

if command -v kvantummanager >/dev/null; then
    kvantummanager --set pywal >/dev/null 2>&1 || true
fi

# ─── 9. Chromium via pywalium ─────────────────────────────────
if [[ -x "$PYWALIUM_DIR/generate.sh" ]]; then
    log "Regenerating Chromium theme..."
    (cd "$PYWALIUM_DIR" && LC_ALL=C ./generate.sh >/dev/null)
    printf '  note: restart Chromium to apply the new colors\n'
else
    warn "pywalium not found at: $PYWALIUM_DIR"
    warn "Chromium theme will not be updated."
fi

#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 50: deploy configuration files
#
# Deploys the project into the user's home directory using three policies:
#
#   Category A (owned):
#     Files fully managed by kc-themeflow. Backed up and replaced silently.
#
#   Category B (user-owned, extended):
#     Files owned by the user, into which kc-themeflow adds or replaces
#     one or two lines. Never replaced entirely.
#
#   Category C (user-owned, never touched):
#     Files that only appear in printed instructions.
#
# Flags:
#   --dry-run            Show what would be done without changing anything.
#   --install-reference  Install reference configs without prompting.
#   --auto-append        Append include lines automatically, without prompting.
#   --no-append          Never modify user files; only print instructions.
#
# Idempotent: safe to run multiple times.
#

set -euo pipefail

# ─── Flag parsing ─────────────────────────────────────────────
DRY_RUN=0
INSTALL_REFERENCE=0
AUTO_APPEND=0
NO_APPEND=0

usage() {
    sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)           DRY_RUN=1 ;;
        --install-reference) INSTALL_REFERENCE=1 ;;
        --auto-append)       AUTO_APPEND=1 ;;
        --no-append)         NO_APPEND=1 ;;
        -h|--help)           usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
    shift
done

if (( AUTO_APPEND && NO_APPEND )); then
    echo "Conflicting flags: --auto-append and --no-append" >&2
    exit 1
fi

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

readonly SRC_RUNTIME="$PROJECT_ROOT/runtime"
readonly SRC_REFERENCE="$PROJECT_ROOT/config/reference"
readonly SRC_TEMPLATES="$PROJECT_ROOT/config/templates"
readonly SRC_SNIPPETS="$PROJECT_ROOT/config/snippets"

readonly KC_CONFIG_DIR="$HOME/.config/kc-themeflow"
readonly KC_BACKUP_ROOT="$KC_CONFIG_DIR/backup"
readonly KC_RUNTIME_DIR="$HOME/.local/share/kc-themeflow/runtime"
readonly KC_WRAPPER="$HOME/.local/bin/kc-themeflow"
readonly WAL_CACHE="$HOME/.cache/wal"
readonly WAL_TEMPLATES="$HOME/.config/wal/templates"

readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="$KC_BACKUP_ROOT/$TIMESTAMP"

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

dry() { (( DRY_RUN )) && printf "  ${YELLOW}[dry-run]${NC} %s\n" "$*"; return 0; }

# ─── Backup helpers ───────────────────────────────────────────
ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]] && (( ! DRY_RUN )); then
        mkdir -p "$BACKUP_DIR"
    fi
}

# backup_path <path>
# Copies an existing file/dir into the timestamped backup directory.
# Uses copy (not move): the original stays in place, the caller decides
# whether to replace, modify, or leave it as is.
backup_path() {
    local src="$1"
    [[ -e "$src" || -L "$src" ]] || return 0

    if (( DRY_RUN )); then
        dry "backup: $src"
        return 0
    fi

    ensure_backup_dir
    local rel="${src#$HOME/}"
    local dest="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    info "Backed up: $rel"
}

has_marker() {
    local file="$1" marker="$2"
    [[ -f "$file" ]] && grep -qF -- "$marker" "$file"
}

# ─── User prompt ──────────────────────────────────────────────
# ask_yes <question>
# In --dry-run, never prompts; prints the question and returns "no"
# so the caller prints instructions instead.
ask_yes() {
    local question="$1"

    if (( DRY_RUN )); then
        dry "would ask: $question"
        return 1
    fi
    if (( INSTALL_REFERENCE )); then return 0; fi
    if (( NO_APPEND )); then return 1; fi
    if (( AUTO_APPEND )); then return 0; fi

    local answer
    printf "  %s [y/N] " "$question"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ─── Instruction printing ─────────────────────────────────────
print_instruction() {
    local file="$1"; shift
    printf "  ${YELLOW}▸${NC} Action required: %s\n" "$file"
    for line in "$@"; do
        printf "      ${BOLD}%s${NC}\n" "$line"
    done
    printf "\n"
}

# ─── Category A helpers ───────────────────────────────────────
deploy_owned_dir() {
    local src="$1" dst="$2"
    if (( DRY_RUN )); then
        dry "deploy dir: $src -> $dst"
        return 0
    fi
    backup_path "$dst"
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
    ok "Deployed: $dst"
}

deploy_owned_file() {
    local src="$1" dst="$2"
    if (( DRY_RUN )); then
        dry "deploy file: $src -> $dst"
        return 0
    fi
    backup_path "$dst"
    rm -f "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    ok "Deployed: $dst"
}

# ─── Category B helpers ───────────────────────────────────────
# append_block <file> <marker> <lines...>
#   Idempotent append. If <marker> already present, does nothing.
append_block() {
    local file="$1" marker="$2"; shift 2

    if has_marker "$file" "$marker"; then
        ok "Already integrated: $file"
        return 0
    fi

    if (( DRY_RUN )); then
        dry "append to $file:"
        for line in "$@"; do printf "      | %s\n" "$line"; done
        return 0
    fi

    backup_path "$file"
    mkdir -p "$(dirname "$file")"
    {
        printf '\n'
        for line in "$@"; do printf '%s\n' "$line"; done
    } >> "$file"
    ok "Appended to: $file"
}

# ini_set <file> <section> <key> <value>
#   Sets a key in an INI-style file. If the key already exists anywhere,
#   its value is replaced in place. If missing, the key is inserted into
#   the given section (creating the section at the end if necessary).
ini_set() {
    local file="$1" section="$2" key="$3" value="$4"

    if [[ ! -f "$file" ]]; then
        warn "ini_set: no such file: $file"
        return 1
    fi

    if grep -qE "^${key}=${value}$" "$file"; then
        ok "Already set: $key=$value in $file"
        return 0
    fi

    if (( DRY_RUN )); then
        if grep -qE "^${key}=" "$file"; then
            dry "would replace: ${key}=... -> ${key}=${value} in $file"
        else
            dry "would add: ${key}=${value} under [${section}] in $file"
        fi
        return 0
    fi

    backup_path "$file"

    if grep -qE "^${key}=" "$file"; then
        sed -i -E "s|^${key}=.*|${key}=${value}|" "$file"
        ok "Replaced: $key=$value in $file"
    else
        awk -v section="$section" -v line="${key}=${value}" '
            BEGIN { in_section = 0; inserted = 0 }
            /^\[/ {
                if (in_section && !inserted) {
                    print line
                    inserted = 1
                }
                if ($0 == "[" section "]") {
                    in_section = 1
                } else {
                    in_section = 0
                }
                print
                next
            }
            { print }
            END {
                if (in_section && !inserted) {
                    print line
                    inserted = 1
                }
                if (!inserted) {
                    print ""
                    print "[" section "]"
                    print line
                }
            }
        ' "$file" > "$file.tmp"
        if [[ -s "$file.tmp" ]]; then
            mv "$file.tmp" "$file"
            ok "Added: $key=$value under [${section}] in $file"
        else
            rm -f "$file.tmp"
            fail "Failed to update $file (awk produced empty output)"
            return 1
        fi
    fi
}

# install_reference <reference-file> <target> <description>
#   If target does not exist, offer to install the reference config.
install_reference() {
    local ref="$1" dst="$2" desc="$3"

    if [[ -f "$dst" ]]; then
        return 1
    fi

    if [[ ! -f "$ref" ]]; then
        warn "No reference config available yet: $desc"
        info "Expected: $ref"
        return 2
    fi

    info "No existing config for $desc"
    if ! ask_yes "Install reference config at $dst?"; then
        print_instruction "$dst" "Copy the reference from: $ref"
        return 1
    fi

    deploy_owned_file "$ref" "$dst"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

printf "\n"
banner "kc-themeflow — bootstrap 50: deploy configuration files"

(( DRY_RUN )) && warn "DRY RUN — no changes will be made"

if [[ ! -d "$SRC_RUNTIME" ]]; then
    fail "Runtime source not found: $SRC_RUNTIME"
    exit 1
fi

# ─── A. Runtime scripts ───────────────────────────────────────
title "Category A — runtime scripts"
deploy_owned_dir "$SRC_RUNTIME" "$KC_RUNTIME_DIR"

if (( ! DRY_RUN )); then
    shopt -s nullglob
    for f in "$KC_RUNTIME_DIR"/*.sh; do chmod +x "$f"; done
    shopt -u nullglob
    ok "Shell scripts marked executable"
fi

# ─── A. pywal templates ───────────────────────────────────────
title "Category A — pywal templates"

if [[ -d "$SRC_TEMPLATES" ]]; then
    if (( DRY_RUN )); then
        dry "deploy templates: $SRC_TEMPLATES -> $WAL_TEMPLATES"
    else
        mkdir -p "$WAL_TEMPLATES"
        for tpl in "$SRC_TEMPLATES"/*; do
            [[ -f "$tpl" ]] || continue
            cp -f "$tpl" "$WAL_TEMPLATES/$(basename "$tpl")"
            ok "Template deployed: $(basename "$tpl")"
        done
    fi
else
    warn "No templates directory: $SRC_TEMPLATES"
fi

# ─── A. Command wrapper ───────────────────────────────────────
title "Category A — command wrapper"

readonly WRAPPER_TEMPLATE='#!/usr/bin/env bash
#
# kc-themeflow — entry point wrapper
#
# Generated by bootstrap/50-deploy-configs.sh. Do not edit by hand.
#
set -euo pipefail

readonly ENTRY="$HOME/.local/share/kc-themeflow/runtime/set_theme.sh"

if [[ ! -x "$ENTRY" ]]; then
    echo "kc-themeflow: runtime script not found: $ENTRY" >&2
    echo "Run bootstrap/50-deploy-configs.sh to install it." >&2
    exit 1
fi

exec "$ENTRY" "$@"
'

if (( DRY_RUN )); then
    dry "write wrapper: $KC_WRAPPER"
else
    backup_path "$KC_WRAPPER"
    mkdir -p "$(dirname "$KC_WRAPPER")"
    printf '%s' "$WRAPPER_TEMPLATE" > "$KC_WRAPPER"
    chmod +x "$KC_WRAPPER"
    ok "Installed: $KC_WRAPPER"
fi

# ─── A. Initial Qtile colors ──────────────────────────────────
title "Category A — initial Qtile colors"

if [[ -f "$WAL_CACHE/colors.json" ]]; then
    if (( DRY_RUN )); then
        dry "generate: ~/.config/qtile/custom_utils/colors.py"
    elif python3 "$KC_RUNTIME_DIR/qtile_colors.py"; then
        :
    else
        warn "qtile_colors.py failed"
    fi
else
    warn "No pywal cache: $WAL_CACHE/colors.json"
    info "Run 'kc-themeflow -i <wallpaper>' after deployment"
fi

# ─── A. Dunst (fully generated) ───────────────────────────────
title "Category A — dunst (generated from template)"

DUNST_CONF="$HOME/.config/dunst/dunstrc"
DUNST_SRC="$WAL_CACHE/dunst-theme.dunstrc"

if [[ -f "$DUNST_SRC" ]]; then
    if (( DRY_RUN )); then
        dry "deploy: $DUNST_SRC -> $DUNST_CONF"
    else
        backup_path "$DUNST_CONF"
        mkdir -p "$(dirname "$DUNST_CONF")"
        cp -f "$DUNST_SRC" "$DUNST_CONF"
        ok "Deployed: $DUNST_CONF"
    fi
else
    warn "No rendered dunst theme: $DUNST_SRC"
    info "It will be generated on the first 'kc-themeflow -i <wallpaper>' run"
fi

# ─── B. ~/.xsessionrc ─────────────────────────────────────────
title "Category B — ~/.xsessionrc"

XSESSIONRC="$HOME/.xsessionrc"
XSESSIONRC_MARKER="# kc-themeflow"
XSESSIONRC_LINES=(
    "$XSESSIONRC_MARKER"
    'export PATH="$HOME/.local/bin:$PATH"'
    'export QT_QPA_PLATFORMTHEME='
    'export QT_STYLE_OVERRIDE=kvantum'
)

if has_marker "$XSESSIONRC" "$XSESSIONRC_MARKER"; then
    ok "Already integrated: $XSESSIONRC"
elif [[ -f "$XSESSIONRC" ]]; then
    if ask_yes "Append kc-themeflow exports to $XSESSIONRC?"; then
        append_block "$XSESSIONRC" "$XSESSIONRC_MARKER" "${XSESSIONRC_LINES[@]}"
    else
        print_instruction "$XSESSIONRC" "${XSESSIONRC_LINES[@]}"
    fi
else
    if (( DRY_RUN )); then
        dry "create $XSESSIONRC with kc-themeflow exports"
    else
        mkdir -p "$(dirname "$XSESSIONRC")"
        printf '%s\n' "${XSESSIONRC_LINES[@]}" > "$XSESSIONRC"
        ok "Created: $XSESSIONRC"
    fi
fi

# ─── B. Alacritty ─────────────────────────────────────────────
title "Category B — alacritty"

ALACRITTY_TOML="$HOME/.config/alacritty/alacritty.toml"

if [[ ! -f "$ALACRITTY_TOML" ]]; then
    install_reference "$SRC_REFERENCE/alacritty/alacritty.toml" \
                      "$ALACRITTY_TOML" "alacritty.toml" || true
elif has_marker "$ALACRITTY_TOML" "current-theme.toml"; then
    ok "Already integrated: $ALACRITTY_TOML"
else
    print_instruction "$ALACRITTY_TOML" \
        "Add inside the [general] section:" \
        "" \
        '    import = ["current-theme.toml"]'
fi

# ─── B. Rofi ──────────────────────────────────────────────────
title "Category B — rofi"

ROFI_CONF="$HOME/.config/rofi/config.rasi"
ROFI_THEME_LINE='@theme "current-theme.rasi"'

if [[ ! -f "$ROFI_CONF" ]]; then
    install_reference "$SRC_REFERENCE/rofi/config.rasi" \
                      "$ROFI_CONF" "config.rasi" || true
else
    existing_theme="$(grep -E '^[[:space:]]*@theme[[:space:]]' "$ROFI_CONF" | head -n1 || true)"

    if [[ "$existing_theme" == *'current-theme.rasi'* ]]; then
        ok "Already integrated: $ROFI_CONF"
    elif [[ -n "$existing_theme" ]]; then
        if ask_yes "Replace @theme line in $ROFI_CONF with $ROFI_THEME_LINE?"; then
            if (( DRY_RUN )); then
                dry "would replace: $existing_theme"
                dry "           with: $ROFI_THEME_LINE"
            else
                backup_path "$ROFI_CONF"
                sed -i -E 's|^[[:space:]]*@theme[[:space:]]+.*$|'"$ROFI_THEME_LINE"'|' "$ROFI_CONF"
                ok "Replaced @theme in $ROFI_CONF"
            fi
        else
            print_instruction "$ROFI_CONF" \
                "Replace the existing @theme line with:" \
                "" \
                "    $ROFI_THEME_LINE"
        fi
    else
        if ask_yes "Append $ROFI_THEME_LINE to $ROFI_CONF?"; then
            append_block "$ROFI_CONF" "current-theme.rasi" "$ROFI_THEME_LINE"
        else
            print_instruction "$ROFI_CONF" "$ROFI_THEME_LINE"
        fi
    fi
fi

# ─── B. GTK 3 / GTK 4 ─────────────────────────────────────────
title "Category B — GTK 3 and GTK 4"

for ver in 3.0 4.0; do
    GTK_INI="$HOME/.config/gtk-$ver/settings.ini"

    if [[ ! -f "$GTK_INI" ]]; then
        install_reference "$SRC_REFERENCE/gtk-$ver/settings.ini" \
                          "$GTK_INI" "gtk-$ver settings.ini" || true
        continue
    fi

    current="$(grep -E '^gtk-theme-name=' "$GTK_INI" | head -n1 | cut -d= -f2-)"
    if [[ "$current" == "adw-gtk3-dark" ]]; then
        ok "Already set: gtk-theme-name=adw-gtk3-dark in $GTK_INI"
        continue
    fi

    if [[ -n "$current" ]]; then
        msg="Replace gtk-theme-name=$current with gtk-theme-name=adw-gtk3-dark?"
    else
        msg="Add gtk-theme-name=adw-gtk3-dark under [Settings] in $GTK_INI?"
    fi

    if ask_yes "$msg"; then
        ini_set "$GTK_INI" "Settings" "gtk-theme-name" "adw-gtk3-dark"
    else
        print_instruction "$GTK_INI" \
            "Replace or add the following key under [Settings]:" \
            "" \
            "    gtk-theme-name=adw-gtk3-dark"
    fi
done

# ─── B. qt6ct ─────────────────────────────────────────────────
title "Category B — qt6ct"

QT6CT_CONF="$HOME/.config/qt6ct/qt6ct.conf"

if [[ ! -f "$QT6CT_CONF" ]]; then
    install_reference "$SRC_REFERENCE/qt6ct/qt6ct.conf" \
                      "$QT6CT_CONF" "qt6ct.conf" || true
else
    current="$(grep -E '^style=' "$QT6CT_CONF" | head -n1 | cut -d= -f2-)"
    if [[ "$current" == "kvantum" ]]; then
        ok "Already set: style=kvantum in $QT6CT_CONF"
    else
        if [[ -n "$current" ]]; then
            msg="Replace style=$current with style=kvantum in $QT6CT_CONF?"
        else
            msg="Add style=kvantum under [Appearance] in $QT6CT_CONF?"
        fi

        if ask_yes "$msg"; then
            ini_set "$QT6CT_CONF" "Appearance" "style" "kvantum"
        else
            print_instruction "$QT6CT_CONF" \
                "Replace or add the following key under [Appearance]:" \
                "" \
                "    style=kvantum"
        fi
    fi
fi

# ─── B. Qtile config.py (always print snippet) ────────────────
title "Category B — Qtile config.py (manual integration)"

QTILE_CONFIG="$HOME/.config/qtile/config.py"
QTILE_SNIPPET="$SRC_SNIPPETS/qtile-config.py.txt"

if [[ ! -f "$QTILE_CONFIG" ]]; then
    warn "No Qtile config at $QTILE_CONFIG"
    info "Create your config first, then return to this step"
elif has_marker "$QTILE_CONFIG" "from custom_utils.colors import"; then
    ok "Already integrated: $QTILE_CONFIG"
elif [[ -f "$QTILE_SNIPPET" ]]; then
    printf "  ${YELLOW}▸${NC} Manual integration required: %s\n" "$QTILE_CONFIG"
    printf "      Add the following snippet near the top:\n\n"
    sed 's/^/      /' "$QTILE_SNIPPET"
    printf "\n"
else
    warn "Qtile snippet not found: $QTILE_SNIPPET"
fi

# ─── C. Manual-only integrations ──────────────────────────────
title "Category C — manual only (never touched)"

github_dir="$(python3 - <<'PY'
import sys, tomllib
from pathlib import Path
prefs = Path.home() / ".config" / "kc-themeflow" / "preferences.toml"
default = str(Path.home() / "githubs")
if not prefs.exists():
    print(default)
    sys.exit(0)
try:
    with open(prefs, "rb") as f:
        data = tomllib.load(f)
except Exception:
    print(default)
    sys.exit(0)
val = data.get("paths", {}).get("github_dir")
print(val if isinstance(val, str) and val else default)
PY
)"

cat <<EOF
  These integrations cannot be automated. Follow the manual steps:
    • Neovim:    install RedsXDD/neopywal.nvim, call colorscheme("neopywal")
    • VSCode:    install extension dlasagno.wal-theme, select "Wal" theme
    • Chromium:  load unpacked extension from ${github_dir}/pywalium
                 at chrome://extensions/
  See docs/manual-steps.md for details.
EOF

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

if (( DRY_RUN )); then
    printf "  ${YELLOW}Dry run — nothing was changed.${NC}\n\n"
    exit 0
fi

printf "  Runtime: %s\n" "$KC_RUNTIME_DIR"
printf "  Wrapper: %s\n" "$KC_WRAPPER"
[[ -d "$BACKUP_DIR" ]] && printf "  Backup:  %s\n" "$BACKUP_DIR"

printf "\n  Next step: ${BOLD}bootstrap/60-first-run.sh${NC}\n\n"

exit 0

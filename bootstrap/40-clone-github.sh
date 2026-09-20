#!/usr/bin/env bash
#
# kc-themeflow — bootstrap step 40: clone and build GitHub repositories
#
# Reads: deps.toml ([paths], [git.*]), ~/.config/kc-themeflow/preferences.toml
# Writes: ~/.config/kc-themeflow/preferences.toml (on first run)
#
# Repositories cloned:
#   adw-gtk3             -> meson build + install into ~/.local
#   pywal16-libadwaita   -> only templates/pywal.json is copied
#   pywalium             -> cloned as-is; extension loaded manually
#
# Idempotent: safe to run multiple times.
#

set -euo pipefail

# Prevent git from prompting for credentials in non-interactive runs.
# If a repository is unreachable, private, or the URL is wrong, git
# fails immediately instead of hanging on a username/password prompt.
export GIT_TERMINAL_PROMPT=0

# ─── Paths ────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEPS_FILE="$PROJECT_ROOT/deps.toml"
readonly PREFS_DIR="$HOME/.config/kc-themeflow"
readonly PREFS_FILE="$PREFS_DIR/preferences.toml"
readonly WAL_TEMPLATES_DIR="$HOME/.config/wal/templates"

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

# ─── TOML helpers ─────────────────────────────────────────────
# read_toml <file> <dotted.key>
# Prints the value, or nothing if key/file missing.
read_toml() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    python3 - "$file" "$key" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(0)
node = data
for part in sys.argv[2].split("."):
    if not isinstance(node, dict):
        sys.exit(0)
    node = node.get(part)
    if node is None:
        sys.exit(0)
if isinstance(node, (str, int, float)):
    print(node)
PY
}

# write_toml_string <file> <section> <key> <value>
# Writes or updates a single string key in a section, preserving other
# sections if the file already exists.
write_toml_string() {
    local file="$1" section="$2" key="$3" value="$4"
    mkdir -p "$(dirname "$file")"
    python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys, tomllib
from pathlib import Path

file, section, key, value = sys.argv[1:5]
path = Path(file)

data: dict = {}
if path.exists():
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except Exception:
        data = {}

data.setdefault(section, {})[key] = value

lines: list[str] = []
for sec, items in data.items():
    lines.append(f"[{sec}]")
    if isinstance(items, dict):
        for k, v in items.items():
            if isinstance(v, str):
                lines.append(f'{k} = "{v}"')
            else:
                lines.append(f"{k} = {v!r}")
    lines.append("")

path.write_text("\n".join(lines))
PY
}

# ─── Path normalization ───────────────────────────────────────
# normalize_path <raw>
# Expands ~, substitutes environment variables, resolves relative
# paths against $HOME, and prints an absolute normalized path.
normalize_path() {
    local raw="$1"

    raw="${raw/#\~/$HOME}"

    if command -v envsubst >/dev/null 2>&1; then
        raw="$(printf '%s' "$raw" | envsubst)"
    fi

    if [[ "$raw" != /* ]]; then
        raw="$HOME/$raw"
    fi

    realpath -m "$raw"
}

# ─── Git helpers ──────────────────────────────────────────────
# clone_repo <url> <dest> [--shallow]
#   --shallow   pass --depth=1 (skip full history)
#
# Returns 0 on success, non-zero on failure with a clear message.
# Never prompts for credentials: GIT_TERMINAL_PROMPT=0 is exported
# at the top of the script.
clone_repo() {
    local url="$1" dest="$2" mode="${3:-}"
    local -a git_args=(clone --quiet)

    [[ "$mode" == "--shallow" ]] && git_args+=(--depth=1)

    if ! git "${git_args[@]}" "$url" "$dest" 2>/dev/null; then
        fail "Failed to clone: $url"
        info "Check the URL in deps.toml and network connectivity."
        info "Verify manually: GIT_TERMINAL_PROMPT=0 git clone $url $dest"
        return 1
    fi
    return 0
}

# ensure_repo <url> <dest> [--shallow]
# Clones the repository if it does not exist, otherwise reports OK.
# Idempotent.
ensure_repo() {
    local url="$1" dest="$2" mode="${3:-}"

    if [[ -d "$dest/.git" ]]; then
        ok "Repository already cloned: $dest"
        return 0
    fi

    info "Cloning: $url"
    if ! clone_repo "$url" "$dest" "$mode"; then
        exit 1
    fi
    ok "Cloned into: $dest"
}

# ─── Preconditions ────────────────────────────────────────────
printf "\n"
banner "kc-themeflow — bootstrap 40: GitHub repositories"

if [[ ! -f "$DEPS_FILE" ]]; then
    fail "deps.toml not found: $DEPS_FILE"
    exit 1
fi

# ─── Determine github_dir ─────────────────────────────────────
title "Clone directory"

github_dir=""

# 1. From preferences.toml (takes precedence)
prefs_val="$(read_toml "$PREFS_FILE" "paths.github_dir")"
[[ -n "$prefs_val" ]] && github_dir="$prefs_val"

# 2. From deps.toml
if [[ -z "$github_dir" ]]; then
    github_dir="$(read_toml "$DEPS_FILE" "paths.github_dir")"
fi

# 3. Interactive prompt
if [[ -z "$github_dir" ]]; then
    printf "  No clone directory configured.\n"
    printf "  Supports ~, environment variables, absolute and relative paths.\n"
    read -r -p "  Clone repositories into [~/githubs]: " user_input
    github_dir="${user_input:-~/githubs}"
fi

# 4. Normalize and validate
github_dir="$(normalize_path "$github_dir")"
info "Resolved path: $github_dir"

# Save to preferences
prefs_existing="$(read_toml "$PREFS_FILE" "paths.github_dir")"
if [[ "$prefs_existing" != "$github_dir" ]]; then
    write_toml_string "$PREFS_FILE" "paths" "github_dir" "$github_dir"
    ok "Saved to: $PREFS_FILE"
fi

# Ensure directory exists
if [[ ! -d "$github_dir" ]]; then
    mkdir -p "$github_dir"
    ok "Created: $github_dir"
else
    ok "Exists: $github_dir"
fi

# ─── adw-gtk3 ─────────────────────────────────────────────────
title "adw-gtk3 (GTK3 theme)"

adw_url="$(read_toml "$DEPS_FILE" "git.adw-gtk3.url")"
adw_tag="$(read_toml "$DEPS_FILE" "git.adw-gtk3.tag")"
adw_prefix="$(read_toml "$DEPS_FILE" "git.adw-gtk3.prefix")"
adw_prefix="$(normalize_path "${adw_prefix:-~/.local}")"

adw_dir="$github_dir/adw-gtk3"

# Full clone (not shallow): we need the tag v5.10, which is not HEAD.
ensure_repo "$adw_url" "$adw_dir"

# Checkout the pinned tag
current_tag="$(git -C "$adw_dir" describe --tags --exact-match 2>/dev/null || true)"
if [[ "$current_tag" != "$adw_tag" ]]; then
    info "Checking out tag: $adw_tag"
    git -C "$adw_dir" fetch --tags --quiet
    git -C "$adw_dir" checkout --quiet "$adw_tag"
    ok "Checked out: $adw_tag"
else
    ok "Already at tag: $adw_tag"
fi

# Build and install if the theme is not yet in the prefix
if [[ -d "$adw_prefix/share/themes/adw-gtk3" && \
      -d "$adw_prefix/share/themes/adw-gtk3-dark" ]]; then
    ok "Theme already installed in: $adw_prefix/share/themes/"
else
    info "Building with meson..."
    pushd "$adw_dir" >/dev/null
    rm -rf builddir
    if meson setup builddir --prefix="$adw_prefix" >/dev/null 2>&1 && \
       meson install -C builddir >/dev/null 2>&1; then
        popd >/dev/null
        ok "Installed into: $adw_prefix/share/themes/"
    else
        popd >/dev/null
        fail "Build failed. Inspect manually:"
        info "  cd $adw_dir"
        info "  meson setup builddir --prefix=$adw_prefix"
        info "  meson install -C builddir"
        exit 1
    fi
fi

# ─── pywal16-libadwaita ───────────────────────────────────────
title "pywal16-libadwaita (Gradience template)"

lib_url="$(read_toml "$DEPS_FILE" "git.pywal16-libadwaita.url")"
lib_dir="$github_dir/pywal16-libadwaita"

# Shallow clone: we only need one file from the current HEAD.
ensure_repo "$lib_url" "$lib_dir" --shallow

# Copy only the template we need
template_src="$lib_dir/templates/pywal.json"
template_dst="$WAL_TEMPLATES_DIR/pywal.json"

if [[ ! -f "$template_src" ]]; then
    fail "Template not found: $template_src"
    exit 1
fi

mkdir -p "$WAL_TEMPLATES_DIR"
if [[ -f "$template_dst" ]] && cmp -s "$template_src" "$template_dst"; then
    ok "Template already up to date: $template_dst"
else
    cp -f "$template_src" "$template_dst"
    ok "Template installed: $template_dst"
fi

# ─── pywalium ─────────────────────────────────────────────────
title "pywalium (Chromium theme generator)"

pyw_url="$(read_toml "$DEPS_FILE" "git.pywalium.url")"
pyw_dir="$github_dir/pywalium"

# Shallow clone: only need generate.sh and templates.
ensure_repo "$pyw_url" "$pyw_dir" --shallow

if [[ -x "$pyw_dir/generate.sh" ]]; then
    ok "Generator ready: $pyw_dir/generate.sh"
else
    warn "generate.sh not found or not executable in: $pyw_dir"
fi

# ─── Summary ──────────────────────────────────────────────────
printf "\n"
banner "Done"

printf "  Clone dir:  %s\n" "$github_dir"
printf "  adw-gtk3:   %s\n" "$adw_dir"
printf "  libadwaita: %s\n" "$lib_dir"
printf "  pywalium:   %s\n" "$pyw_dir"

printf "\n  Next step: ${BOLD}bootstrap/50-deploy-configs.sh${NC}\n\n"

exit 0

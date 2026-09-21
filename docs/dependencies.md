# Dependencies

What kc-themeflow installs on top of an existing Debian 13 + X11 +
LightDM + Qtile system. The authoritative list is in
[`deps.toml`](../deps.toml).

Base system tools (`bash`, `curl`, `git`, `python3`, `qtile`) are assumed
to be present and are not installed by kc-themeflow.

---

## apt

Installed by `bootstrap/10-apt-packages.sh`.

**Required:**

| Package | Why |
|---|---|
| `git` | clone repositories |
| `curl` | download `uv`, network checks |
| `meson`, `ninja-build` | build `adw-gtk3` |
| `sassc` | compile `adw-gtk3` SCSS |
| `qt-style-kvantum` | Kvantum style engine |
| `qt-style-kvantum-themes` | KvAdaptaDark, base for our theme |
| `qt-style-kvantum-l10n` | localization |

**Optional** (installed if missing, skipped if present): `feh`, `qt6ct`,
`alacritty`, `dunst`, `rofi`.

---

## uv

Installed by `bootstrap/20-uv-tools.sh`.

- `uv` — from `https://astral.sh/uv/install.sh`
- `pywal16` — from `git+https://github.com/eylles/pywal16.git`

`uv` puts `wal` into `~/.local/bin`.

---

## GitHub

Cloned by `bootstrap/40-clone-github.sh`. Clone directory is configurable
(default `~/githubs`, stored in
`~/.config/kc-themeflow/preferences.toml`).

| Repository | Version | Why |
|---|---|---|
| [`adw-gtk3`](https://github.com/lassekongo83/adw-gtk3) | tag `v5.10` | GTK 3 theme; required by Gradience |
| [`pywal16-libadwaita`](https://github.com/eylles/pywal16-libadwaita) | HEAD | source of `templates/pywal.json` |
| [`pywalium`](https://github.com/simonmader17/pywalium) | HEAD | Chromium theme generator |

`adw-gtk3` is pinned to `v5.10` because newer versions require Dart Sass,
which is not in Debian 13 apt. `v5.10` builds with `sassc`, which is in
apt.

The Kvantum theme is not taken from `pywal16-libadwaita` — those templates
are incomplete. It is generated from the system `KvAdaptaDark` by
`runtime/kvantum_build.py`.

---

## Manual

Editor plugins and the browser extension — see
[`docs/manual-steps.md`](manual-steps.md).
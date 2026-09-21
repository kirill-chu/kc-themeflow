# Architecture

How kc-themeflow is put together.

---

## Phases

**Bootstrap** — `bootstrap/` runs once. Installs packages, clones
repositories, deploys configs to `~/.config`. Slow, idempotent.

**Runtime** — `runtime/` runs on every theme change. Fast, does not
install anything.

The wrapper `~/.local/bin/kc-themeflow` calls
`~/.local/share/kc-themeflow/runtime/set_theme.sh`.

---

## Data flow

```
   wallpaper  ────┐
                  │
   theme.json ────┤
                  ▼
             ┌──────────┐
             │  pywal   │
             └────┬─────┘
                  │
                  ▼
        ~/.cache/wal/colors.json          ← the palette
                  │
                  │  rendered from templates
                  ├──▶ alacritty-theme.toml
                  ├──▶ rofi-theme.rasi
                  ├──▶ dunst-theme.dunstrc
                  ├──▶ pywal.json (Gradience preset)
                  │
                  ▼
          ┌──────────────────┐
          │  set_theme.sh    │
          └────────┬─────────┘
                   │
      ┌────────────┼────────────┬───────────┬────────────┐
      ▼            ▼            ▼           ▼            ▼
   Qtile       Alacritty      Rofi       Dunst      Kvantum
   colors.py   current-theme  current-   dunstrc    pywal.*
               .toml          theme.rasi
                   │
                   ▼
              GTK 3 / GTK 4 (gtk_theme.py)
                   │
                   ▼
              Chromium extension manifest
```

`set_theme.sh` does not generate colors itself. It copies the rendered
files into place and reloads applications.

---

## File ownership

### Owned by kc-themeflow

Backed up and replaced on every change. Do not edit these by hand.

- `~/.local/share/kc-themeflow/runtime/*`
- `~/.local/bin/kc-themeflow`
- `~/.config/qtile/custom_utils/colors.py`
- `~/.config/alacritty/current-theme.toml`
- `~/.config/rofi/current-theme.rasi`
- `~/.config/dunst/dunstrc`
- `~/.config/Kvantum/pywal/*`
- `~/.cache/wal/*`

### Owned by the user, extended by kc-themeflow

One line added or replaced, only after asking.

- `~/.config/qtile/config.py` — snippet printed, file not edited
- `~/.config/alacritty/alacritty.toml` — one import line
- `~/.config/rofi/config.rasi` — one `@theme` line
- `~/.config/gtk-3.0/settings.ini` — one key
- `~/.config/gtk-4.0/settings.ini` — one key
- `~/.config/qt6ct/qt6ct.conf` — one key
- `~/.xsessionrc` — three export lines

### Never touched

Neovim, VSCode, Chromium configs.

---

## The palette

`~/.cache/wal/colors.json` has two parts:

- `special.background` / `special.foreground` — window colors
- `colors.color0` … `colors.color15` — the 16 ANSI colors

These are not the same. `background` is a soft dark, `color0` is a harsher
terminal black. Every generator script respects the difference.

---

## Environment variables

Three exports, set in `~/.xsessionrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
export QT_QPA_PLATFORMTHEME=
export QT_STYLE_OVERRIDE=kvantum
```

LightDM reads `~/.xsessionrc` before the X session, so all processes
inherit them.
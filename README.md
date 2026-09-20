# kc-themeflow

A unified color theme system for my personal Debian + X11 + Qtile setup.

Generates a palette from a wallpaper (or a prepared JSON file) and applies
it consistently across the environment: Qtile, GTK 3/4, Qt (Kvantum),
Alacritty, Rofi, Dunst, Neovim, Chromium, VSCode, LibreOffice.

One command changes the entire look of the desktop.

---

## Requirements

The base system must already have:

- Debian 13 (trixie)
- X11 session, launched by LightDM
- Qtile running as the window manager

kc-themeflow adds the theme system on top of this. It does not install
the X server, the session manager, or Qtile itself.

---

## Install

```bash
git clone https://github.com/kirill-chu/kc-themeflow.git
cd kc-themeflow
./install.sh
```

The installer runs seven bootstrap steps in order. See
[`docs/manual-steps.md`](docs/manual-steps.md) for what must be done by
hand afterward.

---

## Use

Change theme from a wallpaper:

```bash
kc-themeflow -i ~/Pictures/wallpapers/example.jpg
```

Change theme from a prepared palette:

```bash
kc-themeflow -f ~/.config/kc-themeflow/themes/your-theme.json
```

Options:

```
-i <file>          wallpaper
-f <file>          prepared pywal JSON palette
--hover=fill       Kvantum hover style: fill (default) or text
--no-wallpaper     apply theme only, do not set the wallpaper
```

Convert an Alacritty theme to a pywal palette:

```bash
python3 tools/convert_alacritty.py --input theme.yml --output theme.json
```

---

## Supported applications

| Application | How the theme is applied |
|---|---|
| Qtile | `~/.config/qtile/custom_utils/colors.py` (generated) |
| Alacritty | import from `current-theme.toml` |
| Rofi | `@theme "current-theme.rasi"` |
| Dunst | `~/.config/dunst/dunstrc` (generated) |
| GTK 3/4 | Gradience preset + `adw-gtk3-dark` |
| Qt | Kvantum theme generated from `KvAdaptaDark` |
| Neovim | via a pywal-aware colorscheme plugin |
| Chromium | via the pywalium extension |
| VSCode | via the Wal Theme extension |
| LibreOffice | inherits the GTK 3 theme |

---

## Layout

```
kc-themeflow/
├── install.sh             entry point
├── deps.toml              dependency manifest
├── bootstrap/             install steps (00…60)
├── runtime/               scripts called on every theme change
├── config/                configs and templates deployed to ~/.config
├── tools/                 standalone utilities
└── docs/
```

---

## Docs

- [Manual steps](docs/manual-steps.md) — what to do by hand after install
- [Architecture](docs/architecture.md) — how it works
- [Dependencies](docs/dependencies.md) — what gets installed
- [Themes](docs/themes.md) — palettes and the converter

---

## License

MIT. See [LICENSE](LICENSE).
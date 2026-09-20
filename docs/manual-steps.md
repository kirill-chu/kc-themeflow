# Manual steps

After `./install.sh` some things must be done by hand. This is the
complete list.

---

## 1. Neovim

The author uses [`neopywal.nvim`](https://github.com/RedsXDD/neopywal.nvim).
It reads `~/.cache/wal/colors-wal.vim` and updates colors automatically on
every theme change.

Install it through your plugin manager and activate the colorscheme.

You can use a different plugin, but the effect may differ.

---

## 2. VSCode

The author uses the [`Wal Theme`](https://marketplace.visualstudio.com/items?itemName=dlasagno.wal-theme)
extension. Install it and select **Wal** as the color theme
(`Ctrl+K Ctrl+T`).

You can use a different extension, but the effect may differ.

---

## 3. Chromium

1. Open `chrome://extensions/`.
2. Enable **Developer mode**.
3. Click **Load unpacked**.
4. Select `<github_dir>/pywalium/pywalium-theme`.

The `<github_dir>` is the clone directory chosen during install. Check
`~/.config/kc-themeflow/preferences.toml` if unsure.

After a theme change, restart Chromium to apply the new colors.

---

## 4. Qtile config

Add this import near the top of `~/.config/qtile/config.py`:

```python
from custom_utils.colors import background, foreground, cursor, palette
```

The generated module exposes:

- `background` — window background
- `foreground` — text color
- `cursor` — accent color
- `palette[0..15]` — the 16 ANSI colors

Use them wherever you need colors. Example:

```python
layout.MonadTall(
    border_focus=palette[5],
    border_normal=background,
)
widget.GroupBox(
    active=foreground,
    this_current_screen_border=palette[4],
    urgent_border=palette[1],
    block_highlight_text_color=background,
)
```

After editing `config.py`, reload Qtile: `Mod+Ctrl+R`.

---

## 5. LibreOffice

LibreOffice draws the document through its own engine, not GTK. On first
launch in a dark GTK theme it may set the paper to dark and text to dark,
making it unreadable. Fix it once:

**Tools → Options → LibreOffice → Appearance**:

- Set **Appearance** to **Light**.
- Under **Customizations → Items**, set **Document background** to **White**.
- Set **Font color** to **Automatic**.
- Apply and restart LibreOffice.

The toolbar, sidebar, and dialogs follow the GTK theme automatically.

---

## 6. Application restarts

Some applications read their theme only at startup. After a theme change,
restart them if they don't visibly update:

- **Alacritty** — open a new window
- **Rofi** — open a new menu
- **KeePassXC**, **LibreOffice**, **Qalculate**, etc. — close and reopen the
  process
- **Chromium** — close and reopen the browser

If restarting the process is not enough, log out and back in.
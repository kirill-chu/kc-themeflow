# Themes

How palettes work and how to make your own.

---

## Two modes

**From a wallpaper:**

```bash
kc-themeflow -i ~/Pictures/wallpapers/example.jpg
```

pywal16 analyzes the image and generates a palette. The wallpaper is set
on the desktop.

**From a prepared JSON:**

```bash
kc-themeflow -f ~/.config/kc-themeflow/themes/your-theme.json
```

pywal16 reads the palette directly. The wallpaper is not changed.

Both produce `~/.cache/wal/colors.json`, which every application reads.

---

## Palette format

```json
{
    "wallpaper": "",
    "alpha": "100",
    "special": {
        "background": "#1f1f28",
        "foreground": "#dcd7ba",
        "cursor": "#dcd7ba"
    },
    "colors": {
        "color0":  "#090618",
        "color1":  "#c34043",
        "color2":  "#76946a",
        "color3":  "#c0a36e",
        "color4":  "#7e9cd8",
        "color5":  "#957fb8",
        "color6":  "#6a9589",
        "color7":  "#c8c093",
        "color8":  "#727169",
        "color9":  "#e82424",
        "color10": "#98bb6c",
        "color11": "#e6c384",
        "color12": "#7fb4ca",
        "color13": "#938aa9",
        "color14": "#7aa89f",
        "color15": "#dcd7ba"
    }
}
```

Required: `special.background`, `special.foreground`, `colors.color0` …
`colors.color15`. The rest is optional.

**Note:** `special.background` is not `color0`. `color0` is a terminal
black, `background` is the window color. Use the right one.

---

## Making a palette by hand

Most terminal themes give you 16 hex colors plus a background and
foreground. The mapping is mechanical:

- 8 normal colors → `color0` … `color7`
- 8 bright colors → `color8` … `color15`
- Background → `special.background`
- Foreground → `special.foreground`

Fill in the JSON, save, apply with `kc-themeflow -f`.

---

## Converting an Alacritty theme

```bash
python3 tools/convert_alacritty.py \
    --input  theme.yml \
    --output theme.json

kc-themeflow -f theme.json
```

Options:

| Flag | Meaning |
|---|---|
| `--input` | source file (`.yml`, `.yaml`, `.toml`) |
| `--output` | destination JSON (default: stdout) |
| `--compact` | write compact JSON |

The converter reads `colors.primary`, `colors.normal`, `colors.bright` and
maps them to pywal fields. Sections that pywal does not support
(`colors.cursor`, `colors.selection`, `colors.indexed_colors`) are dropped.

**Requirements:** PyYAML for `.yml` input (`sudo apt install python3-yaml`).
`.toml` uses `tomllib` from Python 3.11+.
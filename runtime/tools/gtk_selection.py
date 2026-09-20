#!/usr/bin/env python3
"""
Append a CSS override for GTK selection color.

adw-gtk3 hard-codes selection colors in its compiled CSS and does
not read theme_selected_bg_color. This tool appends a rule at the
end of gtk.css so that GtkTreeView and GtkListBox selections use
the palette accent (color4) with the window background as text.

Any previous override is removed before the new one is written, so
the block never accumulates.

Usage:
    gtk_selection.py <colors.json> <gtk.css> [<gtk.css> ...]
"""

import json
import sys
from pathlib import Path

MARKER = "/* kc-themeflow: selection */"

BLOCK_TEMPLATE = """
{marker}
treeview.view:selected,
treeview.view:selected:focus,
row:selected,
row:selected:focus {{
    background-color: {bg};
    color: {fg};
}}
"""


def load_colors(colors_path: Path) -> tuple[str, str]:
    with open(colors_path) as f:
        palette = json.load(f)
    return palette["colors"]["color4"], palette["special"]["background"]


def apply_override(css_path: Path, bg: str, fg: str) -> None:
    text = css_path.read_text()
    if MARKER in text:
        text = text[: text.index(MARKER)]
    text = text.rstrip() + "\n"
    block = BLOCK_TEMPLATE.format(marker=MARKER, bg=bg, fg=fg)
    css_path.write_text(text + block)


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    colors_path = Path(sys.argv[1])
    css_paths = [Path(p) for p in sys.argv[2:]]

    bg, fg = load_colors(colors_path)
    for css in css_paths:
        if not css.is_file():
            continue
        apply_override(css, bg, fg)
        print(f"  GTK selection override written: {css}")


if __name__ == "__main__":
    main()

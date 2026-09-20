#!/usr/bin/env python3
"""
Build the Kvantum "pywal" theme from the system KvAdaptaDark theme.

Reads:  ~/.cache/wal/colors.json
Base:   /usr/share/Kvantum/KvAdaptaDark/KvAdaptaDark.{kvconfig,svg}
Writes: ~/.config/Kvantum/pywal/pywal.{kvconfig,svg}

The base KvAdaptaDark SVG contains all the elements Kvantum expects
(including itemview hover states). The pywal16-libadwaita SVG is
incomplete — it lacks several elements — so we use KvAdaptaDark as a
template and only substitute colors.
"""

import argparse
import json
import re
from pathlib import Path

HOME    = Path.home()
WAL     = HOME / ".cache" / "wal" / "colors.json"
ADAPTA  = Path("/usr/share/Kvantum/KvAdaptaDark")
OUT_DIR = HOME / ".config" / "Kvantum" / "pywal"

# Direct hex-to-color substitution table.
# Hex values are taken from KvAdaptaDark; targets come from pywal.
def build_map(colors: dict, special: dict) -> dict:
    BG, FG = special["background"], special["foreground"]
    C0, C1, C2, C3 = colors["color0"], colors["color1"], colors["color2"], colors["color3"]
    C4, C5, C6, C7 = colors["color4"], colors["color5"], colors["color6"], colors["color7"]
    C8, C12, C13 = colors["color8"], colors["color12"], colors["color13"]

    return {
        # kvconfig
        "#263238": BG, "#29353b": BG, "#2d3a41": C0, "#2d393f": C8,
        "#47535a": C8, "#313131": C8, "#191919": C0,
        "#00bcd4": C4, "#009DFF": C12, "#9E4FFF": C13, "#eefcff": FG,
        "#787878": C8,
        "#ffffff50": C8 + "50", "#ffffff7d": FG + "7d", "#ffffff96": FG + "96",
        "#ffffffa0": FG + "a0", "#ffffffaa": FG + "aa", "#ffffffb4": FG + "b4",
        "#ffffffc8": FG + "c8",
        # svg — dark backgrounds
        "#000931": C0, "#141414": C0, "#141b1e": C0, "#192023": C0,
        "#1e282d": BG, "#212b30": BG, "#212c31": BG, "#222d32": BG,
        "#252f35": BG, "#28343a": BG, "#293439": BG,
        "#304048": C0, "#314047": C0, "#39444a": C0,
        "#3d494f": C8, "#3e4a50": C8,
        # svg — teal shades
        "#275f59": C6, "#2d4c4f": C6,
        # svg — mid grays
        "#556165": C8, "#565b5e": C8, "#60727c": C8, "#646464": C8,
        "#6c787d": C8, "#717b81": C8,
        # svg — light grays
        "#7b7b7b": C7, "#7d7d7d": C7, "#7f898f": C7,
        "#828282": C7, "#969696": C7, "#a6afb4": C7, "#acb1bc": C7,
        # svg — light
        "#cfd8dc": FG, "#e4e5e8": FG, "#fafafa": FG,
        "#fbfbfc": FG, "#f6feff": FG,
        # svg — accents
        "#008dd4": C4, "#00c3dc": C4, "#4db6ac": C6,
        "#00c867": C2, "#0cb400": C2,
        "#b74aff": C5, "#f04a50": C1, "#f44336": C1,
        "#ff0a0a": C1, "#ff7a00": C3,
    }


def replace_all(text: str, mapping: dict, literals: dict) -> str:
    for hexv in sorted(mapping, key=len, reverse=True):
        text = re.sub(re.escape(hexv), mapping[hexv], text, flags=re.IGNORECASE)
    for lit, val in literals.items():
        text = re.sub(rf'(=\s*){lit}\b', rf'\1{val}', text)
    return text


def apply_post_override(text: str, overrides: dict) -> str:
    for key, val in overrides.items():
        text = re.sub(
            rf'^{re.escape(key)}\s*=.*$',
            f'{key}={val}',
            text,
            flags=re.MULTILINE,
        )
    return text


def patch_itemview_kvconfig(text: str, fg: str) -> str:
    """Make hover text light instead of dark."""
    text = re.sub(
        r'^text\.press\.color\s*=.*$',
        f'text.press.color={fg}',
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r'^text\.focus\.color\s*=.*$',
        f'text.focus.color={fg}',
        text,
        flags=re.MULTILINE,
    )
    return text


def patch_itemview_svg(text: str, hover: str) -> str:
    """Adjust hover highlight in the SVG."""
    if hover == "fill":
        new_opacity = ".15"
    elif hover == "text":
        new_opacity = "0"
    else:
        raise ValueError(f"Unknown hover style: {hover}")

    lines = text.split("\n")
    for i, line in enumerate(lines):
        if "itemview-focused" in line and "itemview-toggled" in line:
            lines[i] = re.sub(r'opacity:[0-9.]+', f'opacity:{new_opacity}', line)
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the Kvantum 'pywal' theme from KvAdaptaDark.",
    )
    parser.add_argument(
        "--hover",
        choices=("fill", "text"),
        default="fill",
        help="hover style: fill (default) or text",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    with open(WAL) as f:
        w = json.load(f)

    colors = w["colors"]
    special = w["special"]
    BG, FG = special["background"], special["foreground"]

    mapping = build_map(colors, special)
    literals = {"black": colors["color0"], "white": BG}

    # Final overrides applied after MAP and LITERAL.
    # These fix roles where KvAdaptaDark uses a variable name with a
    # meaning different from what its name suggests.
    post_override = {
        # In KvAdaptaDark, light.color controls the background of dialogs
        # and popup windows. Put it in the same tone as the main background.
        "light.color": BG,
        # alt.base.color is the background of alternating rows in lists.
        # Keep it close to the base background.
        "alt.base.color": colors["color0"],
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # kvconfig
    src = (ADAPTA / "KvAdaptaDark.kvconfig").read_text()
    src = replace_all(src, mapping, literals)
    src = apply_post_override(src, post_override)
    src = patch_itemview_kvconfig(src, FG)
    if args.hover == "text":
        src = src.replace(
            "[ItemView]\n",
            f"[ItemView]\nframe.color={colors['color2']}\nframe.expansion=0\n",
            1,
        )
    (OUT_DIR / "pywal.kvconfig").write_text(src)
    print(f"Written: {OUT_DIR / 'pywal.kvconfig'}  [hover={args.hover}]")

    # svg
    src = (ADAPTA / "KvAdaptaDark.svg").read_text()
    src = replace_all(src, mapping, literals)
    src = patch_itemview_svg(src, args.hover)
    (OUT_DIR / "pywal.svg").write_text(src)
    print(f"Written: {OUT_DIR / 'pywal.svg'}")


if __name__ == "__main__":
    main()
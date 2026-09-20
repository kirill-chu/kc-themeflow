#!/usr/bin/env python3
"""
Convert an Alacritty color theme (YAML or TOML) into a pywal-compatible
JSON palette.

Usage:
    convert_alacritty.py --input theme.yml --output theme.json
    convert_alacritty.py --input theme.toml > theme.json

Supported input formats:
    .yml, .yaml    Alacritty YAML theme
    .toml          Alacritty TOML theme

Output format: pywal16 JSON (see docs/themes.md, §2).
"""

import argparse
import json
import sys
from pathlib import Path

# Alacritty color names, in the order they map to color0..color7 (normal)
# and color8..color15 (bright).
COLOR_NAMES = [
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
]


def load_yaml(path: Path) -> dict:
    try:
        import yaml
    except ImportError:
        print("error: PyYAML is required to read YAML files.", file=sys.stderr)
        print("       Install it with one of:", file=sys.stderr)
        print("         sudo apt install python3-yaml", file=sys.stderr)
        print("         pip install --user pyyaml", file=sys.stderr)
        sys.exit(1)

    with open(path) as f:
        return yaml.safe_load(f)


def load_toml(path: Path) -> dict:
    try:
        import tomllib
    except ImportError:
        print("error: tomllib is required (Python 3.11+).", file=sys.stderr)
        sys.exit(1)

    with open(path, "rb") as f:
        return tomllib.load(f)


def load_source(path: Path) -> dict:
    suffix = path.suffix.lower()
    if suffix in (".yml", ".yaml"):
        return load_yaml(path)
    if suffix == ".toml":
        return load_toml(path)
    print(f"error: unsupported input format: {suffix}", file=sys.stderr)
    print("       Supported extensions: .yml, .yaml, .toml", file=sys.stderr)
    sys.exit(1)


def extract_colors(data: dict) -> tuple[str, str, list[str]]:
    """
    Extract background, foreground, and 16 ANSI colors from an Alacritty
    theme structure.

    Returns:
        (background, foreground, colors16)
        where colors16 is a list of 16 hex strings.
    """
    if not isinstance(data, dict) or "colors" not in data:
        print("error: input does not look like an Alacritty theme.", file=sys.stderr)
        print("       Expected a top-level 'colors' section.", file=sys.stderr)
        sys.exit(1)

    colors = data["colors"]

    for section in ("primary", "normal", "bright"):
        if section not in colors:
            print(f"error: missing 'colors.{section}' section.", file=sys.stderr)
            sys.exit(1)

    def get(section_name: str, key: str) -> str:
        section = colors[section_name]
        if not isinstance(section, dict) or key not in section:
            print(
                f"error: missing 'colors.{section_name}.{key}'.",
                file=sys.stderr,
            )
            sys.exit(1)
        return section[key]

    background = get("primary", "background")
    foreground = get("primary", "foreground")

    normal = [get("normal", name) for name in COLOR_NAMES]
    bright = [get("bright", name) for name in COLOR_NAMES]

    return background, foreground, normal + bright


def to_pywal(background: str, foreground: str, colors16: list[str]) -> dict:
    return {
        "wallpaper": "",
        "alpha": "100",
        "special": {
            "background": background,
            "foreground": foreground,
            # kc-themeflow ignores this field; it is set to foreground for
            # compatibility with tools that read pywal's JSON directly.
            "cursor": foreground,
        },
        "colors": {f"color{i}": c for i, c in enumerate(colors16)},
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert an Alacritty theme to a pywal JSON palette.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--input", "-i",
        required=True,
        type=Path,
        help="source file (.yml, .yaml, .toml)",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        help="destination JSON file "
             "(default: ~/.config/kc-themeflow/themes/<input-stem>.json)",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="write to stdout instead of a file",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="write compact JSON instead of pretty-printed",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"error: input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    data = load_source(args.input)
    bg, fg, colors16 = extract_colors(data)
    pywal = to_pywal(bg, fg, colors16)

    if args.compact:
        text = json.dumps(pywal, separators=(",", ":"))
    else:
        text = json.dumps(pywal, indent=4)

    if args.stdout:
        print(text)
        return

    output_path = args.output
    if output_path is None:
        themes_dir = Path.home() / ".config" / "kc-themeflow" / "themes"
        output_path = themes_dir / f"{args.input.stem}.json"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text + "\n")
    print(f"Written: {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()

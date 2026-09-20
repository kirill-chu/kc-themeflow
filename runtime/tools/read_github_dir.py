#!/usr/bin/env python3
"""
Print the configured github_dir from preferences.toml.

Falls back to ~/githubs if the file or the key is missing.
"""

import tomllib
from pathlib import Path

PREFS = Path.home() / ".config" / "kc-themeflow" / "preferences.toml"
DEFAULT = Path.home() / "githubs"


def main() -> None:
    if not PREFS.is_file():
        print(DEFAULT)
        return
    try:
        with open(PREFS, "rb") as f:
            data = tomllib.load(f)
    except Exception:
        print(DEFAULT)
        return
    value = data.get("paths", {}).get("github_dir")
    print(value if isinstance(value, str) and value else DEFAULT)


if __name__ == "__main__":
    main()

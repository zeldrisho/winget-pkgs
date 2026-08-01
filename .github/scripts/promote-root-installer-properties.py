#!/usr/bin/env python3
"""Promote selected first-installer YAML properties to manifest root without reformatting."""

import json
import pathlib
import sys


def main() -> None:
    path = pathlib.Path(sys.argv[1])
    properties = json.loads(sys.argv[2])
    data = path.read_bytes()
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    lines = data.decode().splitlines()
    root_blocks: list[str] = []

    for prop in properties:
        if any(line.startswith(f"{prop}:") for line in lines):
            continue

        installers = lines.index("Installers:")
        first_installer = next(
            i
            for i in range(installers + 1, len(lines))
            if lines[i].startswith("- Architecture:")
        )
        next_installer = next(
            (
                i
                for i in range(first_installer + 1, len(lines))
                if lines[i].startswith("- Architecture:")
                or lines[i].startswith("ManifestType:")
            ),
            len(lines),
        )
        start = next(
            (
                i
                for i in range(first_installer + 1, next_installer)
                if lines[i].startswith(f"  {prop}:")
            ),
            None,
        )
        if start is None:
            raise SystemExit(f"{prop} is missing from the first installer in {path}")

        end = start + 1
        while end < next_installer:
            line = lines[end]
            if line and not line.startswith("    ") and not line.startswith("  - "):
                break
            end += 1
        root_blocks.extend(
            line[2:] if line.startswith("  ") else line for line in lines[start:end]
        )
        del lines[start:end]

    if root_blocks:
        insert_at = next(
            i for i, line in enumerate(lines) if line.startswith("ReleaseDate:")
        )
        lines[insert_at:insert_at] = root_blocks
        path.write_bytes(newline.join(line.encode() for line in lines) + newline)


if __name__ == "__main__":
    main()

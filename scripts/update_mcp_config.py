#!/usr/bin/env python3
"""Update Codex config.toml with MCP server definitions."""

from __future__ import annotations

import sys
from pathlib import Path

import tomlkit


def ensure_table(doc: tomlkit.TOMLDocument, key: str) -> tomlkit.items.Table:
    """Return an existing table or create a new mutable table."""
    table = doc.get(key)
    if table is None:
        table = tomlkit.table()
        doc[key] = table
    return table


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        sys.stderr.write(
            "Usage: update_mcp_config.py <config-path> <python-cmd> <script1> [script2...]\n"
        )
        return 1

    config_path = Path(argv[1])
    python_cmd = argv[2]
    script_names = argv[3:]

    config_path.parent.mkdir(parents=True, exist_ok=True)
    if config_path.exists():
        doc = tomlkit.parse(config_path.read_text(encoding="utf-8"))
    else:
        doc = tomlkit.document()

    mcp_table = ensure_table(doc, "mcp_servers")

    for filename in script_names:
        name = Path(filename).stem
        table = tomlkit.table()
        table.add("command", python_cmd)
        table.add("args", ["-u", f"/opt/codex-home/mcp/{filename}"])
        mcp_table[name] = table

    config_path.write_text(tomlkit.dumps(doc), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

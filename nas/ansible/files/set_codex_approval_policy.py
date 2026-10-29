#!/usr/bin/env python3
"""Set a Codex account's approval policy without replacing other settings."""

import argparse
import os
from pathlib import Path
import re
import stat
import tempfile
import tomllib


POLICY_LINE = 'approval_policy = "never"\n'
POLICY_KEY = re.compile(r"^\s*(?:approval_policy|\"approval_policy\"|'approval_policy')\s*=")
TABLE_HEADER = re.compile(r"^\s*\[")


def updated_config(original: str) -> str:
    parsed = tomllib.loads(original)
    if parsed.get("approval_policy") == "never":
        return original

    lines = original.splitlines(keepends=True)
    top_level_end = next(
        (index for index, line in enumerate(lines) if TABLE_HEADER.match(line)),
        len(lines),
    )
    matches = [
        index for index in range(top_level_end) if POLICY_KEY.match(lines[index])
    ]
    if "approval_policy" in parsed and len(matches) != 1:
        raise ValueError("Could not safely locate the existing top-level approval_policy")

    if matches:
        lines[matches[0]] = POLICY_LINE
    else:
        lines.insert(0, POLICY_LINE)

    updated = "".join(lines)
    if tomllib.loads(updated).get("approval_policy") != "never":
        raise ValueError("The updated Codex config did not set approval_policy")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("home", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    config_path = (args.home / ".codex" / "config.toml").resolve()
    original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    updated = updated_config(original)
    if updated == original:
        print("unchanged")
        return
    if args.check:
        print("would-change")
        return

    existing_mode = stat.S_IMODE(config_path.stat().st_mode) if config_path.exists() else 0o600
    descriptor, temporary_path = tempfile.mkstemp(prefix=".config.toml.", dir=config_path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(updated)
        os.chmod(temporary_path, existing_mode)
        os.replace(temporary_path, config_path)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)
    print("changed")


if __name__ == "__main__":
    main()

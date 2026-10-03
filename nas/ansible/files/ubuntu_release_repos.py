#!/usr/bin/env python3
"""Review third-party APT sources before an Ubuntu release upgrade and restore supported ones after it."""

import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


SOURCES_DIR = Path(os.environ.get("UBUNTU_RELEASE_SOURCES_DIR", "/etc/apt/sources.list.d"))
STATE_DIR = Path(os.environ.get("UBUNTU_RELEASE_STATE_DIR", "/var/lib/ansible-ubuntu-release-upgrade"))
STATE_FILE = STATE_DIR / "repositories.json"
DISTRO_INFO = Path(os.environ.get("UBUNTU_RELEASE_DISTRO_INFO", "/usr/share/distro-info/ubuntu.csv"))


def release_series():
    with DISTRO_INFO.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def os_release():
    result = {}
    path = Path(os.environ.get("UBUNTU_RELEASE_OS_RELEASE", "/etc/os-release"))
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value.strip('"')
    return result


def next_lts_series():
    current = os_release()["VERSION_CODENAME"]
    releases = [row for row in release_series() if "LTS" in row["version"]]
    for index, row in enumerate(releases[:-1]):
        if row["series"] == current:
            return releases[index + 1]["series"]
    raise RuntimeError(f"No next LTS series found after {current}")


def known_series():
    return {row["series"] for row in release_series()}


def candidate_suite(suite, current, target, known):
    if suite == current or suite.startswith(current + "-"):
        return target + suite[len(current):]
    if any(suite == series or suite.startswith(series + "-") for series in known):
        return target + "-" + suite.split("-", 1)[1] if "-" in suite else target
    return suite


def source_blocks(path, content):
    if path.name.endswith(".sources"):
        for block in re.split(r"\n[ \t]*\n", content):
            if not block.strip():
                continue
            fields = dict(re.findall(r"(?m)^([A-Za-z-]+):[ \t]*(.*)$", block))
            if "deb" not in fields.get("Types", "deb").split():
                continue
            yield {
                "uri": fields.get("URIs", "").split(),
                "suites": fields.get("Suites", "").split(),
                "active": fields.get("Enabled", "yes").lower() != "no",
            }
    else:
        for line in content.splitlines():
            stripped = line.lstrip()
            active = not stripped.startswith("#") and not path.name.endswith(".distUpgrade")
            if stripped.startswith("#"):
                stripped = stripped[1:].lstrip()
            match = re.match(r"deb(?:-src)?\s+(?:\[[^]]+\]\s+)?(\S+)\s+(\S+)", stripped)
            if match:
                yield {"uri": [match.group(1)], "suites": [match.group(2)], "active": active}


def official_ubuntu(uri):
    host = urllib.parse.urlsplit(uri).hostname or ""
    return host == "ubuntu.com" or host.endswith(".ubuntu.com")


def release_file_available(uri, suite):
    if not uri.startswith(("http://", "https://")):
        return False
    base = uri.rstrip("/") + "/dists/" + urllib.parse.quote(suite, safe="")
    for filename in ("InRelease", "Release"):
        request = urllib.request.Request(base + "/" + filename, headers={"User-Agent": "ansible-ubuntu-release-check"})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                prefix = response.read(128)
                if response.status == 200 and (
                    prefix.startswith(b"-----BEGIN PGP SIGNED MESSAGE-----")
                    or prefix.startswith(b"Origin:")
                ):
                    return True
        except (OSError, urllib.error.URLError):
            pass
    return False


def updated_content(path, content, current, target):
    if path.name.endswith(".sources"):
        def change_suites(match):
            tokens = match.group(2).split()
            return match.group(1) + " ".join(
                candidate_suite(token, current, target, known_series()) for token in tokens
            )
        return re.sub(r"(?m)^(Suites:[ \t]*)([^\n]+)$", change_suites, content)

    result = []
    for line in content.splitlines(keepends=True):
        match = re.match(r"(\s*deb(?:-src)?\s+(?:\[[^]]+\]\s+)?\S+\s+)(\S+)(.*)", line)
        if match:
            line = match.group(1) + candidate_suite(match.group(2), current, target, known_series()) + match.group(3)
        result.append(line)
    return "".join(result)


def write_private_json(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def plan(target):
    current = os_release()["VERSION_CODENAME"]
    if target != next_lts_series():
        raise RuntimeError(f"Expected next LTS series {next_lts_series()}, got {target}")
    known = known_series()
    selected = []
    reported = set()
    for path in sorted(SOURCES_DIR.iterdir()):
        if not (path.name.endswith((".sources", ".list", ".list.distUpgrade")) and path.is_file()):
            continue
        content = path.read_text(encoding="utf-8")
        blocks = list(source_blocks(path, content))
        if not blocks:
            continue
        third_party = [block for block in blocks if block["uri"] and not all(official_ubuntu(uri) for uri in block["uri"])]
        if not third_party:
            continue
        available = []
        for block in third_party:
            candidates = [candidate_suite(suite, current, target, known) for suite in block["suites"]]
            supported = bool(block["uri"] and candidates) and all(
                release_file_available(uri, suite) for uri in block["uri"] for suite in candidates
            )
            available.append(supported)
            host = urllib.parse.urlsplit(block["uri"][0]).hostname or block["uri"][0]
            state = "available" if supported else "unavailable"
            activity = "active" if block["active"] else "disabled"
            report = f"{path.name}: {host} {','.join(block['suites'])} -> {','.join(candidates)}: {state}, {activity}"
            if report not in reported:
                print(report)
                reported.add(report)
        if len(blocks) == 1 and len(third_party) == 1 and third_party[0]["active"] and available[0]:
            selected.append({
                "path": str(path),
                "content": updated_content(path, content, current, target),
                "mode": path.stat().st_mode & 0o777,
            })
    write_private_json(STATE_FILE, {"from": current, "target": target, "files": selected})
    print(f"Planned active third-party repositories to restore after upgrade: {len(selected)}")
    print("Disabled repositories will remain disabled even if a target suite exists.")


def write_source(path, content, mode):
    descriptor, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def archive_migrated_sources():
    """Keep the release upgrader's temporary source copies outside APT's input directory."""
    archive_dir = STATE_DIR / "migrated-sources"
    archived = 0
    for path in sorted(SOURCES_DIR.iterdir()):
        if not path.is_file() or not path.name.endswith((".list.migrate", ".sources.migrate")):
            continue
        archive_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(archive_dir, 0o700)
        destination = archive_dir / path.name
        suffix = 1
        while destination.exists():
            destination = archive_dir / f"{path.name}.{suffix}"
            suffix += 1
        shutil.move(str(path), str(destination))
        print(f"Archived {path.name} as {destination}")
        archived += 1
    print(f"MIGRATE_ARCHIVED={archived}")


def apply(target):
    state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    if state["target"] != target or os_release()["VERSION_CODENAME"] != target:
        raise RuntimeError("Target release does not match the saved plan or installed Ubuntu release")
    archive_migrated_sources()
    previous = []
    try:
        for item in state["files"]:
            path = Path(item["path"])
            if path.parent != SOURCES_DIR or path.suffix not in (".list", ".sources"):
                raise RuntimeError(f"Unexpected repository path in saved plan: {path}")
            old_content = path.read_text(encoding="utf-8") if path.exists() else None
            if old_content == item["content"]:
                continue
            previous.append((path, old_content, path.stat().st_mode & 0o777 if path.exists() else None))
            write_source(path, item["content"], item["mode"])
            print(f"Restored {path.name} for {target}")
        if previous:
            subprocess.run(["apt-get", "update"], check=True, timeout=300)
    except Exception:
        for path, old_content, old_mode in reversed(previous):
            if old_content is None:
                path.unlink(missing_ok=True)
            else:
                write_source(path, old_content, old_mode)
        raise
    state["completed"] = True
    write_private_json(STATE_FILE, state)
    print(f"REPOS_CHANGED={int(bool(previous))}")


def resume(target):
    if not STATE_FILE.exists():
        print("No saved Ubuntu repository plan to resume")
        print("REPOS_CHANGED=0")
        return
    state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    if state.get("completed") or state["target"] != target or os_release()["VERSION_CODENAME"] != target:
        print("No completed Ubuntu release upgrade with a pending repository plan")
        print("REPOS_CHANGED=0")
        return
    apply(target)
    print("RESUME_APPLIED=1")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "target":
        print(next_lts_series())
    elif len(sys.argv) == 3 and sys.argv[1] == "plan":
        plan(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "apply":
        apply(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "resume":
        resume(sys.argv[2])
    else:
        raise SystemExit("Usage: ubuntu_release_repos.py target|plan SERIES|apply SERIES|resume SERIES")


if __name__ == "__main__":
    main()

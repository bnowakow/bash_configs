"""Rate-limited warm copy of Mailserver PVCs; source mounts are read-only."""
import hashlib
import json
import os
import shutil
import stat
import sys
import time
from pathlib import Path

RATE = 4 * 1024 * 1024
PAIRS = {
    "config": (Path("/source/config"), Path("/target/config")),
    "data": (Path("/source/data"), Path("/target/data")),
    "log": (Path("/source/log"), Path("/target/log")),
    "state": (Path("/source/state"), Path("/target/state")),
}
manifest = {}
copied = 0
verified = 0
entries = 0
started = time.monotonic()
verify_started = started
last_report = started


def pace():
    elapsed = time.monotonic() - started
    remaining = copied / RATE - elapsed
    if remaining > 0:
        time.sleep(remaining)


def pace_verification():
    elapsed = time.monotonic() - verify_started
    remaining = verified / RATE - elapsed
    if remaining > 0:
        time.sleep(remaining)


def remove_path(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def copy_volume(name, source, target, replace_staging, resume_staging):
    global copied, verified, entries, last_report
    if not source.is_mount() or not target.is_mount():
        raise RuntimeError(f"{name}: expected mounted source and target PVCs")
    if not os.path.ismount(source) or not os.path.ismount(target):
        raise RuntimeError(f"{name}: PVC mount check failed")
    existing = [p.name for p in target.iterdir() if p.name != "lost+found"]
    if existing and not (replace_staging or resume_staging):
        raise RuntimeError(f"{name}: target is not empty; inspect before retry")
    if existing and replace_staging:
        for p in target.iterdir():
            if p.name == "lost+found":
                continue
            remove_path(p)
    inode_targets = {}
    rows = {}
    paths = sorted(source.rglob("*"))
    source_rel_paths = {p.relative_to(source) for p in paths}
    if resume_staging:
        for q in sorted(target.rglob("*"), key=lambda p: len(p.parts), reverse=True):
            rel = q.relative_to(target)
            if rel.parts == ("lost+found",):
                continue
            if rel not in source_rel_paths:
                remove_path(q)
    for p in paths:
        rel = p.relative_to(source)
        q = target / rel
        source_stat = p.lstat()
        row = {
            "mode": stat.S_IMODE(source_stat.st_mode),
            "uid": source_stat.st_uid,
            "gid": source_stat.st_gid,
            "size": source_stat.st_size,
            "mtime_ns": source_stat.st_mtime_ns,
        }
        if p.is_symlink():
            link = os.readlink(p)
            same = q.is_symlink() and os.readlink(q) == link
            if not same:
                remove_path(q)
                q.symlink_to(link)
            os.chown(q, source_stat.st_uid, source_stat.st_gid, follow_symlinks=False)
            shutil.copystat(p, q, follow_symlinks=False)
            row["link"] = link
        elif p.is_dir():
            if q.exists() and (q.is_symlink() or not q.is_dir()):
                remove_path(q)
            q.mkdir(exist_ok=True)
            os.chown(q, source_stat.st_uid, source_stat.st_gid)
            row["directory"] = True
        elif p.is_file():
            inode = (source_stat.st_dev, source_stat.st_ino)
            first = inode_targets.get(inode)
            same = False
            if resume_staging and q.is_file() and not q.is_symlink():
                q_stat = q.stat()
                same = (q_stat.st_size, q_stat.st_mtime_ns, q_stat.st_uid, q_stat.st_gid,
                        stat.S_IMODE(q_stat.st_mode)) == (
                    source_stat.st_size, source_stat.st_mtime_ns, source_stat.st_uid,
                    source_stat.st_gid, stat.S_IMODE(source_stat.st_mode)
                )
            if first is not None:
                if q.exists() or q.is_symlink():
                    remove_path(q)
                os.link(first, q)
                row["hardlink"] = str(first.relative_to(target))
            elif same:
                inode_targets[inode] = q
                row["sha256"] = "unchanged-from-verified-warm-pass"
            else:
                if q.exists() or q.is_symlink():
                    remove_path(q)
                digest = hashlib.sha256()
                with p.open("rb") as src, q.open("xb") as dst:
                    while True:
                        block = src.read(1024 * 1024)
                        if not block:
                            break
                        dst.write(block)
                        digest.update(block)
                        copied += len(block)
                        pace()
                        now = time.monotonic()
                        if now - last_report >= 30:
                            print(f"progress volume={name} copied_bytes={copied}", flush=True)
                            last_report = now
                os.chown(q, source_stat.st_uid, source_stat.st_gid)
                shutil.copystat(p, q, follow_symlinks=False)
                source_hash = digest.hexdigest()
                target_digest = hashlib.sha256()
                with q.open("rb") as check:
                    while True:
                        block = check.read(1024 * 1024)
                        if not block:
                            break
                        target_digest.update(block)
                        verified += len(block)
                        pace_verification()
                if target_digest.hexdigest() != source_hash:
                    raise RuntimeError(f"{name}: target checksum mismatch")
                row["sha256"] = source_hash
                inode_targets[inode] = q
            row["file"] = True
        elif stat.S_ISSOCK(source_stat.st_mode) or stat.S_ISFIFO(source_stat.st_mode):
            if q.exists() or q.is_symlink():
                remove_path(q)
            row["runtime_only"] = "socket" if stat.S_ISSOCK(source_stat.st_mode) else "fifo"
        else:
            raise RuntimeError(f"{name}: refusing special file")
        rows[str(rel)] = row
        entries += 1

    for p in sorted(paths, reverse=True):
        if p.is_dir() and not p.is_symlink():
            q = target / p.relative_to(source)
            shutil.copystat(p, q, follow_symlinks=False)
            os.chown(q, p.stat().st_uid, p.stat().st_gid)
    root_stat = source.stat()
    os.chown(target, root_stat.st_uid, root_stat.st_gid)
    shutil.copystat(source, target)
    manifest[name] = rows
    print(f"volume complete={name} entries={len(rows)}", flush=True)


if sys.argv[1:] not in ([], ["--replace-staging"], ["--resume-staging"]):
    raise SystemExit("Usage: copy-mailserver.py [--replace-staging|--resume-staging]")
replace_staging = sys.argv[1:] == ["--replace-staging"]
resume_staging = sys.argv[1:] == ["--resume-staging"]

for volume_name, (source_path, target_path) in PAIRS.items():
    copy_volume(volume_name, source_path, target_path, replace_staging, resume_staging)

Path("/tmp/mailserver-warm-copy-manifest.json").write_text(
    json.dumps(manifest, separators=(",", ":"))
)
os.chmod("/tmp/mailserver-warm-copy-manifest.json", 0o600)
print(
    f"warm copy complete volumes={len(PAIRS)} entries={entries} "
    f"copied_bytes={copied} rate_limit_bytes_per_second={RATE}",
    flush=True,
)

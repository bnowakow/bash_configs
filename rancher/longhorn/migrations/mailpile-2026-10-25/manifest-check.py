"""Private manifest for a stopped Mailpile copy and its isolated NAS restore."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys


def describe(root):
    entries = {}
    inodes = {}
    for p in sorted(root.rglob('*')):
        rel = str(p.relative_to(root))
        s = p.lstat()
        record = {'mode': stat.S_IMODE(s.st_mode), 'uid': s.st_uid, 'gid': s.st_gid}
        if stat.S_ISLNK(s.st_mode):
            record.update(type='symlink', link=os.readlink(p))
        elif stat.S_ISREG(s.st_mode):
            value = hashlib.sha256()
            with p.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    value.update(block)
            record.update(type='file', size=s.st_size, sha256=value.hexdigest())
            key = (s.st_dev, s.st_ino)
            if key in inodes:
                record['hardlink_to'] = inodes[key]
            else:
                inodes[key] = rel
        elif stat.S_ISDIR(s.st_mode):
            record['type'] = 'directory'
        elif stat.S_ISFIFO(s.st_mode):
            record['type'] = 'fifo'
        elif stat.S_ISSOCK(s.st_mode):
            record['type'] = 'socket'
        else:
            raise RuntimeError('Unexpected special file; refusing cutover')
        entries[rel] = record
    s = root.stat()
    return {'root': [stat.S_IMODE(s.st_mode), s.st_uid, s.st_gid], 'entries': entries}


def verify(claim, expected):
    actual = describe(Path('/target') / claim)
    # ext4's empty filesystem recovery directory is not application data.
    for name in list(actual['entries']):
        if name not in expected['entries'] and (name == 'lost+found' or name.startswith('lost+found/')):
            del actual['entries'][name]
    if actual != expected:
        raise RuntimeError('Manifest/content/permissions mismatch for ' + claim)
    regular = sum(x['type'] == 'file' for x in actual['entries'].values())
    print(claim + ': ' + str(regular) + ' regular files matched SHA256, metadata and link relationships', flush=True)


manifest = Path('/evidence/manifest.json')
if '--copy' in sys.argv:
    records = {}
    for claim in ('data', 'keys'):
        source = Path('/source') / claim
        target = Path('/target') / claim
        subprocess.run(['cp', '-a', '--sparse=always', str(source) + '/.', str(target) + '/'], check=True)
        subprocess.run(['sync', '-f', str(target)], check=True)
        records[claim] = describe(source)
        verify(claim, records[claim])
    old_umask = os.umask(0o077)
    try:
        manifest.write_text(json.dumps(records))
    finally:
        os.umask(old_umask)
    print('Private stopped-copy manifest saved; no message/key contents printed', flush=True)
else:
    records = json.loads(manifest.read_text())
    for claim in ('data', 'keys'):
        verify(claim, records[claim])
    print('Both restored trees match the complete stopped-copy manifest', flush=True)

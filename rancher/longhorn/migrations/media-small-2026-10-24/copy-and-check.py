"""Copy all claims of a stopped app; verify bytes before checking target SQLite."""
import hashlib
from pathlib import Path
import sqlite3
import subprocess


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.digest()


for source in sorted(Path('/source').iterdir()):
    target = Path('/target') / source.name
    subprocess.run(['cp', '-a', str(source) + '/.', str(target) + '/'], check=True)
    subprocess.run(['sync'], check=True)
    count = 0
    for path in source.rglob('*'):
        if path.is_file() and not path.is_symlink():
            relative = path.relative_to(source)
            if digest(path) != digest(target / relative):
                raise RuntimeError(f'Checksum mismatch: {source.name}/{relative}')
            count += 1
    print(f'{source.name}: SHA256 verified {count} files including WAL/SHM', flush=True)

count = 0
for path in Path('/target').rglob('*'):
    if path.is_symlink() or not path.is_file() or path.suffix not in {'.db', '.sqlite', '.sqlite3'}:
        continue
    with path.open('rb') as stream:
        if stream.read(16) != b'SQLite format 3\x00':
            continue
    conn = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    try:
        if conn.execute('PRAGMA quick_check').fetchall() != [('ok',)]:
            raise RuntimeError(f'SQLite quick_check failed: {path.relative_to("/target")}')
    finally:
        conn.close()
    count += 1
    print(f'SQLite quick_check OK: {path.relative_to("/target")}', flush=True)
if not count:
    raise RuntimeError('No SQLite database verified; refusing cutover')
print(f'{count} SQLite databases verified', flush=True)

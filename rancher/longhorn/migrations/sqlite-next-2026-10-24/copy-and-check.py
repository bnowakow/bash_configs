"""Copy stopped application state and validate the copied SQLite databases."""
import hashlib
from pathlib import Path
import sqlite3
import subprocess

source = Path('/source')
target = Path('/target')
subprocess.run(['cp', '-a', str(source) + '/.', str(target) + '/'], check=True)
subprocess.run(['sync'], check=True)

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.digest()

checked = 0
for path in source.rglob('*'):
    if path.is_file() and not path.is_symlink():
        relative = path.relative_to(source)
        if digest(path) != digest(target / relative):
            raise RuntimeError(f'Copy checksum mismatch: {relative}')
        checked += 1
print(f'SHA256 verified for {checked} regular files, including any WAL/SHM sidecars', flush=True)

databases = 0
for path in target.rglob('*'):
    if path.is_symlink() or not path.is_file() or path.suffix not in {'.db', '.sqlite', '.sqlite3'}:
        continue
    with path.open('rb') as stream:
        if stream.read(16) != b'SQLite format 3\x00':
            continue
    connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    try:
        result = connection.execute('PRAGMA quick_check').fetchall()
        if result != [('ok',)]:
            raise RuntimeError(f'SQLite quick_check failed: {path.relative_to(target)}')
    finally:
        connection.close()
    print(f'SQLite quick_check: ok — {path.relative_to(target)}', flush=True)
    databases += 1
if databases == 0:
    raise RuntimeError('No SQLite databases found; refusing an unverified cutover')
print(f'Copy and {databases} SQLite database checks completed', flush=True)

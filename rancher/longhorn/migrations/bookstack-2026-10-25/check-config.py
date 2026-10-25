"""Check the stopped live config archive against source hashes and metadata."""
import hashlib,json,os,stat,sys
from pathlib import Path
root=Path(sys.argv[1]);manifest=json.load(sys.stdin)
for name,row in manifest.items():
 p=root/name;s=p.lstat()
 assert stat.S_IMODE(s.st_mode)==row['mode'],('mode',name)
 assert s.st_uid==row['uid'] and s.st_gid==row['gid'],('owner',name)
 if 'sha256' in row: assert hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==row['sha256'],('hash',name)
 elif 'link' in row: assert os.readlink(p)==row['link'],('link',name)
 else: assert p.is_dir(),('directory',name)
print('Config SHA256, ownership, modes and symlinks verified:',len(manifest),'entries')

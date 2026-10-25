"""Copy a stopped MariaDB directory at 4MiB/s, verifying file bytes/metadata."""
import hashlib,json,os,shutil,stat,time,sys
from pathlib import Path
source=Path('/source/db');target=Path('/target/db');manifest={};start=time.monotonic();copied=0
assert (source/'data/ibdata1').exists(),'Expected MariaDB source missing'
if any(p.name!='lost+found' for p in target.iterdir()):
 assert sys.argv[1:]==['--replace-staging'],'Target is not empty; inspect before retry'
 assert target==Path('/target/db') and target.is_mount(),'Expected staging PVC mount'
 for p in target.iterdir():
  if p.name=='lost+found':continue
  if p.is_dir() and not p.is_symlink():shutil.rmtree(p)
  else:p.unlink()
for p in sorted(source.rglob('*')):
 rel=p.relative_to(source);q=target/rel;s=p.lstat();row={'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid}
 if p.is_symlink():q.symlink_to(os.readlink(p));row['link']=os.readlink(p)
 elif p.is_dir():q.mkdir(exist_ok=True);row['directory']=True
 elif p.is_file():
  h=hashlib.sha256()
  with p.open('rb') as src,q.open('wb') as dst:
   while block:=src.read(1024*1024):
    dst.write(block);h.update(block);copied+=len(block);time.sleep(max(0,copied/(4*1024**2)-(time.monotonic()-start)))
  row['sha256']=h.hexdigest()
  with q.open('rb') as check:assert hashlib.file_digest(check,'sha256').hexdigest()==row['sha256'],f'Hash mismatch {rel}'
 else:raise RuntimeError(f'Special source file: {rel}')
 os.chown(q,s.st_uid,s.st_gid,follow_symlinks=False)
 if not p.is_symlink():shutil.copystat(p,q,follow_symlinks=False)
 manifest[str(rel)]=row
# Restore directory timestamps/modes after writing children.
for p in sorted(source.rglob('*'),reverse=True):
 if p.is_dir() and not p.is_symlink():shutil.copystat(p,target/p.relative_to(source))
s=source.stat();os.chown(target,s.st_uid,s.st_gid);shutil.copystat(source,target);os.sync()
Path('/tmp/database-manifest.json').write_text(json.dumps(manifest,indent=2))
print('Stopped MariaDB copy verified:',len(manifest),'entries,',copied,'bytes; 4MiB/s limit',flush=True)

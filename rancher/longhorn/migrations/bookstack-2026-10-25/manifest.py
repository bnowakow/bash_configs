"""Record quiesced target bytes, ownership, modes and symlink destinations."""
import hashlib,json,os,stat,sys,time
from pathlib import Path
root=Path(sys.argv[1]);result={};started=time.monotonic();read_bytes=0
for p in sorted(root.rglob('*')):
 if p.relative_to(root).parts[0]=='lost+found':continue
 s=p.lstat();row={'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid}
 if p.is_symlink():row['link']=os.readlink(p)
 elif p.is_file():
  h=hashlib.sha256()
  with p.open('rb') as stream:
   while block:=stream.read(1024*1024):
    h.update(block);read_bytes+=len(block);time.sleep(max(0,read_bytes/(4*1024**2)-(time.monotonic()-started)))
  row['sha256']=h.hexdigest()
 elif p.is_dir():row['directory']=True
 else:raise RuntimeError('Unexpected special file')
 result[str(p.relative_to(root))]=row
print(json.dumps(result,indent=2))

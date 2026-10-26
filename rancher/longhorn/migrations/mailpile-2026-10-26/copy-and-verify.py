"""Stopped-source sparse copy; complete byte hashes, ownership and links; no mail output."""
import hashlib,json,os,pathlib,shutil,stat,subprocess,sys,time,traceback
P=pathlib.Path
class Rate:
 def __init__(self,mib):self.rate=mib*1024**2;self.start=time.monotonic();self.count=0
 def account(self,n):
  self.count+=n;time.sleep(max(0,self.count/self.rate-(time.monotonic()-self.start)))
def record(p):
 s=p.lstat();r={'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid,'mtimeNs':s.st_mtime_ns}
 if stat.S_ISLNK(s.st_mode):r.update(type='symlink',link=os.readlink(p))
 elif stat.S_ISDIR(s.st_mode):r['type']='directory'
 elif stat.S_ISREG(s.st_mode):r.update(type='file',size=s.st_size)
 elif stat.S_ISFIFO(s.st_mode):r['type']='fifo'
 else:raise RuntimeError('Unsupported special source entry; inspect private diagnostics')
 return s,r
def ownerstat(src,dst,s):
 os.chown(dst,s.st_uid,s.st_gid,follow_symlinks=False);shutil.copystat(src,dst,follow_symlinks=False)
def describe(root,hashes=True,rate=None):
 result={};inodes={}
 for p in sorted(root.rglob('*')):
  rel=str(p.relative_to(root))
  if rel=='lost+found' or rel.startswith('lost+found/'):continue
  s,r=record(p)
  if r['type']=='file':
   key=(s.st_dev,s.st_ino)
   if key in inodes:r['hardlink_to']=inodes[key];r['sha256']=result[inodes[key]].get('sha256')
   else:
    inodes[key]=rel
    if hashes:
     h=hashlib.sha256()
     with p.open('rb') as f:
      while b:=f.read(1024**2):
       h.update(b)
       if rate:rate.account(len(b))
     r['sha256']=h.hexdigest()
  result[rel]=r
 s=root.stat();return {'root':[stat.S_IMODE(s.st_mode),s.st_uid,s.st_gid,s.st_mtime_ns],'entries':result}
def without_hashes(m):
 d=json.loads(json.dumps(m))
 for r in d['entries'].values():r.pop('sha256',None)
 return d
manifest=P('/tmp/mailpile-manifest.json');mode=sys.argv[1];claimnames=('data','keys')
try:
 if mode=='copy':
  records={};rate=Rate(4);total=0;last=time.monotonic();entrycount=0
  for claim in claimnames:
   src=P('/source')/claim;dst=P('/target')/claim
   assert src.is_mount() and dst.is_mount() and src!=dst
   # Only these unverified staging mounts are overwritten; source mounts are RO.
   for q in dst.iterdir():
    if q.name=='lost+found':continue
    if q.is_dir() and not q.is_symlink():shutil.rmtree(q)
    else:q.unlink()
   entries={};inodes={};paths=sorted(src.rglob('*'))
   for p in paths:
    rel=str(p.relative_to(src));q=dst/rel;s,r=record(p);entrycount+=1
    if r['type']=='directory':q.mkdir(exist_ok=True)
    elif r['type']=='symlink':q.symlink_to(r['link'])
    elif r['type']=='fifo':os.mkfifo(q)
    else:
     key=(s.st_dev,s.st_ino)
     if key in inodes:
      r['hardlink_to']=inodes[key];r['sha256']=entries[inodes[key]]['sha256'];os.link(dst/inodes[key],q)
     else:
      inodes[key]=rel;h=hashlib.sha256();check=hashlib.sha256()
      with p.open('rb',buffering=0) as f,q.open('w+b',buffering=0) as g:
       g.truncate(s.st_size);offset=0
       while block:=f.read(1024**2):
        rate.account(len(block));h.update(block)
        if block.strip(b'\0'):g.write(block)
        else:g.seek(len(block),1)
        copied=os.pread(g.fileno(),len(block),offset);check.update(copied)
        if copied!=block:raise RuntimeError('Copy byte verification failed')
        offset+=len(block);total+=len(block)
        if time.monotonic()-last>=30:
         print('COPY_PROGRESS verified_MiB=%d entries=%d rate_limit=4MiB/s'%(total//1024**2,entrycount),flush=True);last=time.monotonic()
      assert h.digest()==check.digest();r['sha256']=h.hexdigest()
      after=p.lstat();assert (after.st_ino,after.st_size,after.st_mtime_ns)==(s.st_ino,s.st_size,s.st_mtime_ns),'Source changed while copying'
    ownerstat(p,q,s);entries[rel]=r
    time.sleep(max(0,entrycount/150-(time.monotonic()-rate.start)))
   for p in reversed(paths):
    if p.is_dir() and not p.is_symlink():ownerstat(p,dst/p.relative_to(src),p.lstat())
   ownerstat(src,dst,src.stat());subprocess.run(['sync','-f',str(dst)],check=True)
   rootstat=src.stat();expected={'root':[stat.S_IMODE(rootstat.st_mode),rootstat.st_uid,rootstat.st_gid,rootstat.st_mtime_ns],'entries':entries};records[claim]=expected
   assert without_hashes(describe(src,False))==without_hashes(expected),'Source metadata changed during copy'
   assert without_hashes(describe(dst,False))==without_hashes(expected),'Target metadata/link mismatch'
   print('COPY_VERIFIED tree='+claim+' entries='+str(len(entries))+'; SHA256 source/target bytes, metadata, hardlinks and symlinks matched',flush=True)
  old=os.umask(0o077)
  try:manifest.write_text(json.dumps(records))
  finally:os.umask(old)
  print('COPY_COMPLETE verified_bytes='+str(total)+'; private manifest saved',flush=True)
 elif mode=='verify':
  records=json.loads(manifest.read_text());rate=Rate(8)
  for claim in claimnames:
   actual=describe(P('/target')/claim,True,rate);assert actual==records[claim],'Restored tree mismatch'
   print('RESTORE_VERIFIED tree='+claim+' entries='+str(len(actual['entries']))+'; complete SHA256/ownership/modes/timestamps/link match',flush=True)
 elif mode=='source-metadata':
  records=json.loads(manifest.read_text())
  for claim in claimnames:assert without_hashes(describe(P('/source')/claim,False))==without_hashes(records[claim]),'Stopped source tree changed'
  print('SOURCE_METADATA_UNCHANGED: both original trees still match stopped-copy inventory',flush=True)
 else:raise RuntimeError('Unsupported operation')
except BaseException:
 P('/tmp/mailpile-copy-private-error.txt').write_text(traceback.format_exc());print('VERIFICATION_FAILED: private diagnostics preserved in helper; no filenames/content printed',flush=True);sys.exit(1)

"""Stopped-source sparse copy; complete byte hashes, ownership and links; no mail output."""
import hashlib,json,os,pathlib,shutil,stat,subprocess,sys,time,traceback
P=pathlib.Path
last_metadata=0.0
last_pressure_message=0.0
def io_guard():
 global last_pressure_message
 while True:
  lines=P('/proc/pressure/io').read_text().splitlines();values={line.split()[0]:float(line.split()[1].split('=')[1]) for line in lines}
  try:external_pause=bool(json.loads(P('/tmp/mailpile-rate.json').read_text()).get('pause',False))
  except (OSError,ValueError,TypeError):external_pause=False
  if not external_pause and values.get('some',100)<=10 and values.get('full',100)<=2:return
  if time.monotonic()-last_pressure_message>=30:
   print('IO_PRESSURE_PAUSE some_avg10=%.2f full_avg10=%.2f external_pause=%s'%(values.get('some',100),values.get('full',100),external_pause),flush=True);last_pressure_message=time.monotonic()
  time.sleep(5)
class Rate:
 def __init__(self,mib,key='copyKiBps'):self.rate=mib*1024**2;self.key=key;self.start=time.monotonic();self.count=0;self.next=self.start
 def account(self,n):
  try:
   value=json.loads(P('/tmp/mailpile-rate.json').read_text()).get(self.key,self.rate/1024)
   if isinstance(value,(int,float)) and 64<=value<=16384 and value*1024!=self.rate:
    self.rate=value*1024;self.next=time.monotonic();print('RATE_LIMIT_CHANGED '+self.key+'='+str(value),flush=True)
  except (OSError,ValueError,TypeError):pass
  io_guard();self.count+=n;self.next=max(self.next,time.monotonic())+n/self.rate;time.sleep(max(0,self.next-time.monotonic()))
def record(p):
 global last_metadata
 io_guard();eps=40
 try:
  value=json.loads(P('/tmp/mailpile-rate.json').read_text()).get('metadataEntriesPerSecond',eps)
  if isinstance(value,(int,float)) and 5<=value<=500:eps=value
 except (OSError,ValueError,TypeError):pass
 time.sleep(max(0,last_metadata+1/eps-time.monotonic()));last_metadata=time.monotonic()
 s=p.lstat();r={'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid,'mtimeNs':s.st_mtime_ns}
 if stat.S_ISLNK(s.st_mode):r.update(type='symlink',link=os.readlink(p))
 elif stat.S_ISDIR(s.st_mode):r['type']='directory'
 elif stat.S_ISREG(s.st_mode):r.update(type='file',size=s.st_size)
 elif stat.S_ISFIFO(s.st_mode):r['type']='fifo'
 else:raise RuntimeError('Unsupported special source entry; inspect private diagnostics')
 return s,r
def ownerstat(src,dst,s):
 os.chown(dst,s.st_uid,s.st_gid,follow_symlinks=False);shutil.copystat(src,dst,follow_symlinks=False)
def describe(root,hashes=True,rate=None,total_bytes=None):
 result={};inodes={};paths=[p for p in sorted(root.rglob('*')) if str(p.relative_to(root))!='lost+found' and not str(p.relative_to(root)).startswith('lost+found/')];last_report=time.monotonic();hashed_bytes=0
 print('INVENTORY_START tree='+str(root)+' entries='+str(len(paths))+' hashing='+str(hashes),flush=True)
 for number,p in enumerate(paths,1):
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
       h.update(b);hashed_bytes+=len(b)
       if rate:rate.account(len(b))
       if time.monotonic()-last_report>=30:
        print('HASH_PROGRESS tree=%s checked_MiB=%d total_MiB=%d entries=%d/%d'%(root,hashed_bytes//1024**2,(total_bytes or 0)//1024**2,number,len(paths)),flush=True);last_report=time.monotonic()
     r['sha256']=h.hexdigest()
  result[rel]=r
  if time.monotonic()-last_report>=30:
   print('INVENTORY_PROGRESS tree=%s entries=%d/%d percent=%.1f'%(root,number,len(paths),100*number/max(1,len(paths))),flush=True);last_report=time.monotonic()
 print('INVENTORY_COMPLETE tree='+str(root)+' entries='+str(len(paths)),flush=True)
 s=root.stat();return {'root':[stat.S_IMODE(s.st_mode),s.st_uid,s.st_gid,s.st_mtime_ns],'entries':result}
def without_hashes(m):
 d=json.loads(json.dumps(m))
 for r in d['entries'].values():r.pop('sha256',None)
 return d
manifest=P('/tmp/mailpile-manifest.json');mode=sys.argv[1];claimnames=('data','keys')
try:
 if mode in ('copy','resume'):
  resume=mode=='resume';records={};rate=Rate(0.5);reuse_rate=Rate(8,'reuseKiBps');total=0;last=time.monotonic();entrycount=0;newentries=0;reusedbytes=0;reusedfiles=0;rechecked=0
  for claim in claimnames:
   src=P('/source')/claim;dst=P('/target')/claim
   assert src.is_mount() and dst.is_mount() and src!=dst
   # Only these unverified staging mounts are overwritten; source mounts are RO.
   if not resume:
    for q in dst.iterdir():
     if q.name=='lost+found':continue
     if q.is_dir() and not q.is_symlink():shutil.rmtree(q)
     else:q.unlink()
   entries={};inodes={};paths=sorted(src.rglob('*'))
   for p in paths:
    rel=str(p.relative_to(src));q=dst/rel;s,r=record(p);entrycount+=1;reused=False
    if q.exists() or q.is_symlink():
     retain=resume and ((r['type']=='directory' and q.is_dir() and not q.is_symlink()) or (r['type']=='file' and (s.st_dev,s.st_ino) not in inodes and q.is_file() and not q.is_symlink() and q.stat().st_nlink==1))
     if not retain:
      if q.is_dir() and not q.is_symlink():shutil.rmtree(q)
      else:q.unlink()
     elif r['type']=='directory':reused=True
    if r['type']=='directory':q.mkdir(exist_ok=True)
    elif r['type']=='symlink':q.symlink_to(r['link'])
    elif r['type']=='fifo':os.mkfifo(q)
    else:
     key=(s.st_dev,s.st_ino)
     if key in inodes:
      r['hardlink_to']=inodes[key];r['sha256']=entries[inodes[key]]['sha256'];os.link(dst/inodes[key],q)
     else:
      inodes[key]=rel;h=hashlib.sha256();check=hashlib.sha256()
      if resume and q.is_file() and q.stat().st_size==s.st_size:
       reused=True
       with p.open('rb',buffering=0) as f,q.open('rb',buffering=0) as g:
        while block:=f.read(1024**2):
         reuse_rate.account(len(block));rechecked+=len(block)
         if g.read(len(block))!=block:reused=False;break
         h.update(block)
         if time.monotonic()-last>=30:
          print('RESUME_VALIDATION rechecked_MiB=%d reused_files=%d rate_limit=%dKiB/s'%(rechecked//1024**2,reusedfiles,reuse_rate.rate/1024),flush=True);last=time.monotonic()
       if reused:total+=s.st_size;reusedbytes+=s.st_size;reusedfiles+=1;r['sha256']=h.hexdigest()
      if not reused:
       h=hashlib.sha256();check=hashlib.sha256()
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
          print('COPY_PROGRESS verified_MiB=%d entries=%d rate_limit=%dKiB/s'%(total//1024**2,entrycount,rate.rate/1024),flush=True);last=time.monotonic()
       assert h.digest()==check.digest();r['sha256']=h.hexdigest()
      after=p.lstat();assert (after.st_ino,after.st_size,after.st_mtime_ns)==(s.st_ino,s.st_size,s.st_mtime_ns),'Source changed while copying'
    ownerstat(p,q,s);entries[rel]=r
    if not reused:newentries+=1;time.sleep(max(0,newentries/5-(time.monotonic()-rate.start)))
   if resume:
    wanted={str(p.relative_to(src)) for p in paths}
    for q in sorted(dst.rglob('*'),key=lambda q:len(q.parts),reverse=True):
     rel=str(q.relative_to(dst))
     if rel=='lost+found' or rel.startswith('lost+found/') or rel in wanted:continue
     if q.is_dir() and not q.is_symlink():q.rmdir()
     else:q.unlink()
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
  if resume:print('RESUME_REUSED verified_bytes='+str(reusedbytes)+' files='+str(reusedfiles),flush=True)
 elif mode=='prepare-restore-roots':
  records=json.loads(manifest.read_text())
  for claim in claimnames:
   root=P('/target')/claim;assert root.is_mount(),'Expected scratch restore mount'
   s=root.stat();expected=records[claim]['root']
   assert [stat.S_IMODE(s.st_mode),s.st_uid,s.st_gid]==expected[:3],'Scratch restore root mode/owner mismatch'
   if s.st_mtime_ns!=expected[3]:
    os.utime(root,ns=(s.st_atime_ns,expected[3]))
    print('RESTORE_ROOT_MTIME_RESTORED tree='+claim+'; directory mode/ownership preserved; full tree verification still required',flush=True)
 elif mode=='verify':
  records=json.loads(manifest.read_text())
  for claim in claimnames:
   rate=Rate(1,'verifyKiBps');total_bytes=sum(r['size'] for r in records[claim]['entries'].values() if r['type']=='file' and 'hardlink_to' not in r)
   actual=describe(P('/target')/claim,True,rate,total_bytes)
   # Retain computed hashes privately so a mismatch can be audited without rereading.
   oldmask=os.umask(0o077)
   try:P('/tmp/mailpile-actual-'+claim+'.json').write_text(json.dumps(actual))
   finally:os.umask(oldmask)
   if actual!=records[claim]:
    expected=records[claim];fields={};missing=set(expected['entries'])-set(actual['entries']);extra=set(actual['entries'])-set(expected['entries'])
    for name in set(expected['entries']) & set(actual['entries']):
     left=expected['entries'][name];right=actual['entries'][name]
     for field in set(left)|set(right):
      if left.get(field)!=right.get(field):fields[field]=fields.get(field,0)+1
    print('MANIFEST_MISMATCH tree='+claim+' rootFields='+str([i for i,(a,b) in enumerate(zip(expected['root'],actual['root'])) if a!=b])+' entryFieldCounts='+json.dumps(fields,sort_keys=True)+' missing='+str(len(missing))+' extra='+str(len(extra)),flush=True)
    raise AssertionError('Restored tree mismatch; private computed manifest retained')
   print('RESTORE_VERIFIED tree='+claim+' entries='+str(len(actual['entries']))+'; complete SHA256/ownership/modes/timestamps/link match',flush=True)
 elif mode=='source-metadata':
  records=json.loads(manifest.read_text())
  for claim in claimnames:assert without_hashes(describe(P('/source')/claim,False))==without_hashes(records[claim]),'Stopped source tree changed'
  print('SOURCE_METADATA_UNCHANGED: both original trees still match stopped-copy inventory',flush=True)
 else:raise RuntimeError('Unsupported operation')
except BaseException:
 P('/tmp/mailpile-copy-private-error.txt').write_text(traceback.format_exc());print('VERIFICATION_FAILED: private diagnostics preserved in helper; no filenames/content printed',flush=True);sys.exit(1)

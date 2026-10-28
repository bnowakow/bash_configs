"""One-time guarded Mailpile copy/backup/restore/Fleet cutover; original sources retained."""
import json,pathlib,subprocess,sys,time,threading,traceback,datetime,os
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[2];PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');NS='apps-mailpile';HELPER='mailpile-transfer-20261026';K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml'];source_stopped='--source-stopped' in sys.argv;stopped=False;cutover=False;guard_stop=threading.Event();guard_error=PRIVATE/'writer-or-api-alert'
def run(args,data=None,capture=True):
 if args[0] in ('create','delete','patch','label','annotate','scale') or any(a in ('delete','label','scale','annotate') for a in args):log('RESOURCE ACTION: kubectl '+' '.join(args))
 return subprocess.run(K+args,input=data,stdout=subprocess.PIPE if capture else None,check=True).stdout
def obj(args):return json.loads(run(args+['-o','json']))
def ex(pod,container,argv,data=None,capture=True):return run(['-n',NS,'exec']+(['-i'] if data is not None else [])+[pod,'-c',container,'--']+argv,data=data,capture=capture)
def ready(pod):
 for _ in range(12):
  if subprocess.run(K+['-n',NS,'wait','--for=condition=Ready','pod/'+pod,'--timeout=55s']).returncode==0:return
 raise RuntimeError('Helper not Ready')
def wait_deleted(kind,name):
 for _ in range(8):
  if subprocess.run(K+['-n',NS,'wait','--for=delete',kind+'/'+name,'--timeout=55s']).returncode==0:return
 raise RuntimeError('Resource did not finish deletion')
def health():
 for extra in ([],['--server=https://10.0.0.72:6443']):assert subprocess.check_output(K+extra+['--request-timeout=10s','get','--raw=/readyz']).strip()==b'ok'
def guard():
 while not guard_stop.wait(5):
  try:
   d=json.loads(subprocess.check_output(K+['--request-timeout=10s','-n',NS,'get','deploy','mailpile','-o','json'],stderr=subprocess.PIPE));assert d['spec']['replicas']==0
   health()
  except BaseException:
   guard_error.write_text('Source writer restarted or API health could not be verified');log('GUARD ALERT: unexpected writer/API gap; cutover blocked');return
def no_alert():assert not guard_error.exists(),'Writer/API monitoring gap; revalidation required'
def targets_healthy():
 for c in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']:
  p=obj(['-n',NS,'get','pvc',c]);assert p['status']['phase']=='Bound';v=obj(['-n','longhorn-system','get','volumes.longhorn.io',p['spec']['volumeName']]);assert v['status']['robustness']=='healthy' and v['spec']['numberOfReplicas']==2
  if c.endswith('path1-longhorn-rwo'):assert int(p['status']['capacity']['storage'].removesuffix('Gi'))>=12
try:
 assert not (PRIVATE/'migration-started').exists(),'Existing run evidence: inspect before rerunning'
 health();ready(HELPER);targets_healthy();d=obj(['-n',NS,'get','deployment','mailpile']);assert (d['spec']['replicas']==0 and d['status'].get('replicas',0)==0) if source_stopped else (d['spec']['replicas']==1 and d['status'].get('availableReplicas')==1)
 old=json.loads((PRIVATE/'source-deployment.json').read_text());assert d['metadata']['labels'].get('helm.sh/chart')==old['metadata']['labels'].get('helm.sh/chart'),'Chart changed; refresh prepared configuration before continuing'
 assert d['spec']['template']['spec']['containers'][0]['image']==old['spec']['template']['spec']['containers'][0]['image'],'Image changed since preparation'
 for path,text in json.loads((PRIVATE/'source-repository-files.json').read_text()).items():assert (ROOT/path).read_text()==text,'Repository config changed; refresh preparation before continuing'
 assert {v.get('persistentVolumeClaim',{}).get('claimName') for v in d['spec']['template']['spec']['volumes']} >= {'mailpile-path1','mailpile-path2'}
 (PRIVATE/'source-deployment-final.json').write_text(json.dumps(d));(PRIVATE/'migration-started').touch()
 for c in ['mailpile-path1','mailpile-path2']:
  p=obj(['-n',NS,'get','pvc',c]);(PRIVATE/(c+'-source.json')).write_text(json.dumps(p));run(['-n',NS,'annotate','pvc',c,'helm.sh/resource-policy=keep','--overwrite']);run(['patch','pv',p['spec']['volumeName'],'--type=merge','-p','{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'])
 stopped=True;run(['-n',NS,'scale','deployment','mailpile','--replicas=0']);gone=False
 for _ in range(8):
  if subprocess.run(K+['-n',NS,'wait','--for=delete','pod','-l','app.kubernetes.io/instance=mailpile','--timeout=55s']).returncode==0:gone=True;break
 assert gone,'Source pod not gone';log('WRITER STOPPED: original Mailpile pod gone; original claims protected; starting sole-writer/API guard')
 threading.Thread(target=guard,daemon=True).start();no_alert()
 ex(HELPER,'transfer',['python','-u','-','resume' if '--resume-copy' in sys.argv else 'copy'],data=(HERE/'copy-and-verify.py').read_bytes(),capture=False);no_alert();log('COPY PASSED: every regular-file source/target byte verified, complete metadata/link inventories match')
 (PRIVATE/'manifest.json').write_bytes(ex(HELPER,'transfer',['cat','/tmp/mailpile-manifest.json']));(PRIVATE/'manifest.json').chmod(0o600)
 ex(HELPER,'keyring',['python','-'],data=(HERE/'check-keyring.py').read_bytes(),capture=False);log('KEYRING PASSED: unchanged app image parsed disposable GnuPG clone; no message/key content printed')
 group='mailpile-migration-20261026';label='recurring-job-group.longhorn.io/'+group;name='mailpile-migration-backup-20261026'
 recurring={'apiVersion':'longhorn.io/v1beta2','kind':'RecurringJob','metadata':{'name':name,'namespace':'longhorn-system'},'spec':{'name':name,'task':'backup','cron':'0 0 1 1 *','groups':[group],'retain':2,'concurrency':1,'labels':{},'parameters':{'full-backup-interval':'7'}}}
 f=PRIVATE/'recurring-job.json';f.write_text(json.dumps(recurring));run(['create','-f',str(f)]);volumes={}
 for key,c in [('data','mailpile-path1-longhorn-rwo'),('keys','mailpile-path2-longhorn-rwo')]:
  p=obj(['-n',NS,'get','pvc',c]);volumes[key]=p['spec']['volumeName'];run(['-n',NS,'label','pvc',c,label+'=enabled','--overwrite']);synced=False
  for _ in range(60):
   if obj(['-n','longhorn-system','get','volumes.longhorn.io',volumes[key]])['metadata'].get('labels',{}).get(label)=='enabled':synced=True;break
   time.sleep(2)
  assert synced,'Backup group not synchronized'
 for _ in range(60):
  if subprocess.run(K+['-n','longhorn-system','get','cronjob',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
  time.sleep(2)
 no_alert();job='mailpile-precutover-nas-20261026';run(['-n','longhorn-system','create','job','--from=cronjob/'+name,job]);completed=False
 for _ in range(30):
  if subprocess.run(K+['-n','longhorn-system','wait','--for=condition=complete','job/'+job,'--timeout=55s']).returncode==0:completed=True;break
  no_alert();j=obj(['-n','longhorn-system','get','job',job]);assert not j.get('status',{}).get('failed'),'NAS job failed'
 assert completed,'NAS job did not finish';no_alert();start=obj(['-n','longhorn-system','get','job',job])['status']['startTime'];backups=obj(['-n','longhorn-system','get','backups.longhorn.io'])['items'];summary=[];resources=[];claims=[];classes=[]
 for key,volume in volumes.items():
  bs=[b for b in backups if b.get('status',{}).get('volumeName')==volume and b['status'].get('state')=='Completed' and b['status'].get('backupCreatedAt','')>=start];assert bs,'Fresh NAS backup missing';b=max(bs,key=lambda b:b['status']['backupCreatedAt']);summary.append({'tree':key,'volume':volume,'backup':b['metadata']['name'],'created':b['status']['backupCreatedAt']})
  claim='mailpile-'+key+'-restore-20261026';sc='longhorn-'+claim;claims.append(claim);classes.append(sc)
  resources += [{'apiVersion':'storage.k8s.io/v1','kind':'StorageClass','metadata':{'name':sc},'provisioner':'driver.longhorn.io','reclaimPolicy':'Delete','allowVolumeExpansion':True,'volumeBindingMode':'WaitForFirstConsumer','parameters':{'numberOfReplicas':'1','dataLocality':'strict-local','fsType':'ext4','dataEngine':'v1','backupTargetName':'default','fromBackup':b['status']['url']}},{'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':claim,'namespace':NS},'spec':{'accessModes':['ReadWriteOnce'],'storageClassName':sc,'resources':{'requests':{'storage':'12Gi' if key=='data' else '256Mi'}}}}]
 log('NAS BACKUPS PASSED: '+json.dumps(summary));(PRIVATE/'backup-summary.json').write_text(json.dumps(summary,indent=2))
 pod=json.loads((HERE/'transfer-pod.json').read_text());pod['metadata']['name']='mailpile-restore-20261026';pod['spec']['nodeSelector']={'kubernetes.io/hostname':'proxmox3'};pod['spec']['volumes']=[{'name':'target-'+key,'persistentVolumeClaim':{'claimName':claim}} for key,claim in zip(['data','keys'],claims)]
 for c in pod['spec']['containers']:c['volumeMounts']=[m for m in c['volumeMounts'] if m['name'].startswith('target-')]
 resources.append(pod);f=PRIVATE/'restore-objects.json';f.write_text(json.dumps({'apiVersion':'v1','kind':'List','items':resources}));run(['create','-f',str(f)]);restore=pod['metadata']['name'];ready(restore);no_alert()
 for claim in claims:
  p=obj(['-n',NS,'get','pvc',claim]);v=obj(['-n','longhorn-system','get','volumes.longhorn.io',p['spec']['volumeName']]);assert v['spec']['numberOfReplicas']==1 and v['spec']['dataLocality']=='strict-local' and v['status']['currentNodeID']=='proxmox3'
 run(['-n',NS,'cp',str(PRIVATE/'manifest.json'),restore+':/tmp/mailpile-manifest.json','-c','transfer']);ex(restore,'transfer',['python','-u','-','prepare-restore-roots'],data=(HERE/'copy-and-verify.py').read_bytes(),capture=False);ex(restore,'transfer',['python','-u','-','verify'],data=(HERE/'copy-and-verify.py').read_bytes(),capture=False);no_alert();ex(restore,'keyring',['python','-'],data=(HERE/'check-keyring.py').read_bytes(),capture=False);log('INDEPENDENT RESTORE PASSED: complete manifest and cloned GnuPG checks; scratch replica confined to proxmox3')
 run(['-n',NS,'delete','pod',restore]);wait_deleted('pod',restore);run(['-n',NS,'delete','pvc']+claims);run(['delete','storageclass']+classes)
 ex(HELPER,'transfer',['python','-u','-','source-metadata'],data=(HERE/'copy-and-verify.py').read_bytes(),capture=False);no_alert();health();targets_healthy();assert obj(['-n',NS,'get','deploy','mailpile'])['spec']['replicas']==0
 for c in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']:run(['-n',NS,'label','pvc',c,label+'-'])
 run(['delete','-f',str(PRIVATE/'recurring-job.json')]);guard_stop.set();run(['-n',NS,'delete','pod',HELPER]);wait_deleted('pod',HELPER);no_alert();cutover=True
 prepared=json.loads((HERE/'prepared-fleet-files.json').read_text())
 for n,text in prepared.items():(ROOT/n).write_text(text)
 log('CUTOVER START: all copy/backup/restore/guard checks passed; applying both claim references through Fleet')
 subprocess.run([str(HERE/'../pilot-2026-10-24/apply-bundle.sh'),'mailpile','rancher/fleet/apps/mailpile'],check=True)
 arrived=False
 for _ in range(120):
  d=obj(['-n',NS,'get','deploy','mailpile']);refs={v.get('persistentVolumeClaim',{}).get('claimName') for v in d['spec']['template']['spec']['volumes']}
  if d['spec']['replicas']==1 and d['spec']['strategy']['type']=='Recreate' and refs >= {'mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'}:arrived=True;break
  time.sleep(2)
 assert arrived,'Target mounts not installed';available=False
 for _ in range(12):
  if subprocess.run(K+['-n',NS,'rollout','status','deployment/mailpile','--timeout=55s']).returncode==0:available=True;break
 assert available,'Target app not Ready';log('CUTOVER ROLLOUT PASSED: Mailpile Ready on both Longhorn claims; original local sources retained; final runtime/Fleet/Secret/HTTP validation required')
except BaseException as e:
 guard_stop.set();(PRIVATE/'private-error.txt').write_text(traceback.format_exc());log('MIGRATION STOPPED: '+type(e).__name__+'; private diagnostics saved; no success claimed')
 if stopped and not cutover:
  try:
   run(['-n',NS,'delete','pod',HELPER,'--ignore-not-found']);wait_deleted('pod',HELPER);run(['-n',NS,'scale','deployment','mailpile','--replicas='+('0' if source_stopped else '1')]);log('SOURCE RECOVERY REQUESTED: helper stopped; original Mailpile kept stopped' if source_stopped else 'SOURCE RECOVERY REQUESTED: helper stopped; original Mailpile replicas restored')
  except BaseException:log('SOURCE RECOVERY NOT CONFIRMED: inspect API/helper/source state before proceeding')
 raise SystemExit(1)

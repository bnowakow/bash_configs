"""Back up only quiesced BookStack targets, then test independent NAS restores."""
import json,pathlib,subprocess,time,sys
from action_log import log
def audit_exception(kind,error,trace):
 log("ABORTED: "+kind.__name__+" "+str(error))
 sys.__excepthook__(kind,error,trace)
sys.excepthook=audit_exception
here=pathlib.Path(__file__).resolve().parent;private=pathlib.Path('/tmp/longhorn-bookstack-originals');ns='apps-bookstack';k=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml'];helpers={'config':'bookstack-config-transfer-20261025','db':'bookstack-db-transfer-20261025'}
def run(args,*,data=None,capture=True):
 action=' '.join(args)
 if any(x in args for x in ['create','delete','label']):log('RESOURCE ACTION: kubectl '+action)
 try:r=subprocess.run(k+args,input=data,stdout=subprocess.PIPE if capture else None,check=True)
 except subprocess.CalledProcessError as error:
  log('FAILED: kubectl '+action+' exit='+str(error.returncode));raise
 return r.stdout
def obj(args):return json.loads(run(args))
def wait_ready(name):
 for _ in range(8):
  r=subprocess.run(k+['-n',ns,'wait','--for=condition=Ready','pod/'+name,'--timeout=55s'])
  if r.returncode==0:return
 raise RuntimeError('Pod not ready: '+name)
log('BACKUP/RESTORE START: validate holds, quiesced source and target manifests')
assert not (private/'migration-paused-for-control-plane').exists(),'Migration held for sudo-session control-plane recovery; coordinate before resuming'
assert (private/'database-copy-verified').exists(),'Database copy has not passed verification'
assert not (private/'concurrent-writer-detected').exists(),'Another writer invalidated this migration'
source_manifest=run(['-n',ns,'exec','-i',helpers['db'],'-c','transfer','--','python','-','/source/db'],data=(here/'manifest.py').read_bytes())
assert json.loads(source_manifest)==json.loads((private/'database-manifest.json').read_text()),'Source changed during/after copy; discard staging and recopy'
log('SOURCE VERIFIED: original database hashes/metadata match stopped copy')
existing=obj(['-n',ns,'get','pods','-o','json'])['items']
if not any(x['metadata']['name']==helpers['config'] for x in existing):run(['create','-f',str(here/'config-helper.json')],capture=False)
wait_ready(helpers['config'])
for key in ['config','db']:
 data=run(['-n',ns,'exec','-i',helpers[key],'-c','transfer','--','python','-','/target/'+key],data=(here/'manifest.py').read_bytes());(private/(key+'-backup-manifest.json')).write_bytes(data)
pvcs={p['metadata']['name']:p for p in obj(['-n',ns,'get','pvc','-o','json'])['items']};volumes={key:pvcs['bookstack-'+('config' if key=='config' else 'mariadb-data')+'-longhorn-rwo']['spec']['volumeName'] for key in ['config','db']}
label='recurring-job-group.longhorn.io/bookstack-migration-20261025'
for key,volume in volumes.items():
 claim='bookstack-'+('config' if key=='config' else 'mariadb-data')+'-longhorn-rwo'
 run(['-n',ns,'label','pvc',claim,label+'=enabled','--overwrite'],capture=False)
 synced=False
 for _ in range(30):
  v=obj(['-n','longhorn-system','get','volumes.longhorn.io',volume,'-o','json'])
  if v['metadata'].get('labels',{}).get(label)=='enabled':synced=True;break
  time.sleep(2)
 assert synced,'Temporary group label did not synchronize from PVC to volume'
log('TARGETS QUIESCED: manifests captured and temporary PVC backup-group labels synchronized')
job='bookstack-precutover-nas-20261025-retry';run(['-n','longhorn-system','create','job','--from=cronjob/bookstack-migration-backup-20261025',job],capture=False)
complete=False
for _ in range(12):
 r=subprocess.run(k+['-n','longhorn-system','wait','--for=condition=complete','job/'+job,'--timeout=55s'])
 if r.returncode==0:complete=True;break
 j=obj(['-n','longhorn-system','get','job',job,'-o','json'])
 if j.get('status',{}).get('failed',0):break
assert complete,'BookStack native NAS backup failed'
log('NAS JOB COMPLETE: require fresh Completed backups for both target volumes')
j=obj(['-n','longhorn-system','get','job',job,'-o','json']);start=j['status']['startTime'];backups=obj(['-n','longhorn-system','get','backups.longhorn.io','-o','json'])['items'];summary=[];items=[];scs=[];scratch=[]
for key,volume in volumes.items():
 matches=[b for b in backups if b.get('status',{}).get('volumeName')==volume and b['status'].get('state')=='Completed' and b['status'].get('backupCreatedAt','')>=start];assert matches,'Missing fresh backup: '+key
 b=max(matches,key=lambda b:b['status']['backupCreatedAt']);summary.append({'key':key,'volume':volume,'backup':b['metadata']['name'],'created':b['status']['backupCreatedAt']})
 claim='bookstack-'+key+'-nas-restore-20261025';sc='longhorn-'+claim;scs.append(sc);scratch.append(claim)
 items.extend([{'apiVersion':'storage.k8s.io/v1','kind':'StorageClass','metadata':{'name':sc},'provisioner':'driver.longhorn.io','allowVolumeExpansion':True,'reclaimPolicy':'Delete','volumeBindingMode':'Immediate','parameters':{'numberOfReplicas':'2','fsType':'ext4','dataEngine':'v1','backupTargetName':'default','fromBackup':b['status']['url']}},{'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':claim,'namespace':ns},'spec':{'accessModes':['ReadWriteOnce'],'storageClassName':sc,'resources':{'requests':{'storage':'256Mi' if key=='config' else '1Gi'}}}}])
pod=json.loads((here/'db-helper.json').read_text());pod['metadata']['name']='bookstack-nas-restore-20261025';pod['spec']['volumes']=[{'name':key,'persistentVolumeClaim':{'claimName':claim}} for key,claim in zip(['config','db'],scratch)]
for c in pod['spec']['containers']:
 c['volumeMounts']=[{'name':key,'mountPath':'/target/'+key} for key in (['config','db'] if c['name']=='transfer' else ['db'])]
items.append(pod);manifest={'apiVersion':'v1','kind':'List','items':items};(private/'nas-restore-objects.json').write_text(json.dumps(manifest));(private/'backup-summary.json').write_text(json.dumps(summary,indent=2));print('Fresh NAS backups:',summary,flush=True)
log('NAS BACKUPS VERIFIED: '+json.dumps(summary,sort_keys=True))
run(['create','-f',str(private/'nas-restore-objects.json')],capture=False);restore=pod['metadata']['name'];wait_ready(restore)
run(['-n',ns,'cp',str(here/'check-config.py'),restore+':/tmp/check-config.py','-c','transfer'])
for key in ['config','db']:
 run(['-n',ns,'exec','-i',restore,'-c','transfer','--','python','/tmp/check-config.py','/target/'+key],data=(private/(key+'-backup-manifest.json')).read_bytes(),capture=False)
log('NAS RESTORE FILES VERIFIED: config/database SHA256, modes, ownership and symlinks match quiesced target manifests')
run(['-n',ns,'cp',str(private/'bookstack-checksums.sql'),restore+':/tmp/bookstack-checksums.sql','-c','database'])
result=run(['-n',ns,'exec','-i',restore,'-c','database','--','sh','-s'],data=(here/'verify-database.sh').read_bytes());(private/'nas-restore-database-verification.txt').write_bytes(result);print(result.decode(),flush=True)
checks=run(['-n',ns,'exec',restore,'-c','database','--','cat','/tmp/database-checksums.txt']);assert checks==(private/'database-source-checksums.txt').read_bytes(),'NAS-restored database table checksums differ'
log('NAS RESTORE DATABASE VERIFIED: isolated startup, all-database checks, 41 source-matching table checksums and clean shutdown')
print('Independent NAS restores passed file metadata/hashes and MariaDB table checksums',flush=True)
run(['-n',ns,'delete','pod',restore,'--wait=true'],capture=False)
run(['-n',ns,'delete','pvc']+scratch,capture=False);run(['delete','storageclass']+scs,capture=False)
run(['-n',ns,'delete','pod',helpers['config'],'--wait=true'],capture=False)
for key,volume in volumes.items():
 claim='bookstack-'+('config' if key=='config' else 'mariadb-data')+'-longhorn-rwo'
 run(['-n',ns,'label','pvc',claim,label+'-'],capture=False)
run(['delete','-f',str(here/'migration-backup.json')],capture=False)
assert not (private/'concurrent-writer-detected').exists(),'Concurrent writer detected; refusing cutover'
source_manifest=run(['-n',ns,'exec','-i',helpers['db'],'-c','transfer','--','python','-','/source/db'],data=(here/'manifest.py').read_bytes())
assert json.loads(source_manifest)==json.loads((private/'database-manifest.json').read_text()),'Source changed before cutover'
ds=obj(['-n',ns,'get','deploy','bookstack','bookstack-mariadb','-o','json'])['items']
assert all(d['spec']['replicas']==0 for d in ds),'Writers restarted before cutover'
log('PRE-CUTOVER VERIFIED: no concurrent writer alert; original source still matches; app/DB replicas0; scratch cleanup completed')
(private/'migration-guard-release').touch()
log('CUTOVER GATE RELEASE: existing coordinator will remove DB helper, apply final Fleet values and wait for app/DB rollouts')
(private/'backup-and-restore-verified').touch();print('Backup/restore gate released for Fleet cutover',flush=True)

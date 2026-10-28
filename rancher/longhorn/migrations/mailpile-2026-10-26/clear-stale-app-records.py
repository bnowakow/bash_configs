"""Clear exact old deleting application Pod records only after pause-only cgroup proof."""
import datetime,json,pathlib,subprocess
from action_log import log
PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=10s']
targets=[('apps-cleanuparr','cleanuparr-74647f6df8-x544l'),('apps-jellyseerr','jellyseerr-54d7b9d8d-487tp'),('apps-prowlarr','prowlarr-794d9f8668-r484r'),('apps-sonarr','sonarr-56bdffd8d8-5hgsr'),('apps-uptime-kuma','uptime-kuma-6b849c54-4g6bt')];pods=[]
for ns,name in targets:
 r=subprocess.run(K+['-n',ns,'get','pod',name,'--ignore-not-found','-o','json'],stdout=subprocess.PIPE,check=True)
 if not r.stdout.strip():continue
 p=json.loads(r.stdout);m=p['metadata'];assert m.get('deletionTimestamp') and not m.get('finalizers') and p['spec']['nodeName']=='proxmox2-old';assert any(o['kind']=='ReplicaSet' for o in m.get('ownerReferences',[]));assert (datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat(m['deletionTimestamp'].replace('Z','+00:00'))).total_seconds()>60
 pods.append({'namespace':ns,'name':name,'uid':m['uid']})
code='''import pathlib,json
pods=PODS
out={p['uid']:[] for p in pods};errors=0;scanned=0
for proc in pathlib.Path('/proc').iterdir():
 if not proc.name.isdigit():continue
 try:cg=(proc/'cgroup').read_text();comm=(proc/'comm').read_text().strip();scanned+=1
 except FileNotFoundError:continue
 except PermissionError:errors+=1;continue
 for uid,row in out.items():
  if uid in cg or uid.replace('-','_') in cg:row.append({'pid':int(proc.name),'comm':comm})
print(json.dumps({'scanned':scanned,'permissionErrors':errors,'pods':out}))
'''.replace('PODS',repr(pods))
audit=json.loads(subprocess.check_output(['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=5','-i','/home/sup/.ssh/id_rsa','sup@10.0.0.72','python3','-'],input=code.encode(),timeout=30));assert audit['permissionErrors']==0;assert all(all(p['comm']=='pause' for p in ps) for ps in audit['pods'].values())
(PRIVATE/'stale-app-cgroup-audit.json').write_text(json.dumps({'records':pods,'audit':audit},indent=2))
for row in pods:
 p=json.loads(subprocess.check_output(K+['-n',row['namespace'],'get','pod',row['name'],'-o','json']));assert p['metadata']['uid']==row['uid'] and p['metadata'].get('deletionTimestamp')
 f=PRIVATE/'delete-stale-app-options.json';f.write_text(json.dumps({'apiVersion':'v1','kind':'DeleteOptions','gracePeriodSeconds':0,'preconditions':{'uid':row['uid']}}));f.chmod(0o600)
 log('STALE APP POD RECORD CLEAR: '+row['namespace']+'/'+row['name']+' UID='+row['uid']+'; already deleting >60s; exact old cgroup has only pause/no app processes; UID-preconditioned API deletion only')
 subprocess.run(K+['delete','--raw','/api/v1/namespaces/'+row['namespace']+'/pods/'+row['name'],'-f',str(f)],stdout=subprocess.DEVNULL,check=True)
 print('Cleared verified stale app record:',row['namespace']+'/'+row['name'])

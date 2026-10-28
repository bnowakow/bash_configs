"""Clear only preidentified deleted Pod API records with pause-only host cgroups."""
import json,pathlib,subprocess
from action_log import log
PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');pods=json.loads((PRIVATE/'stale-peer-pods.json').read_text());K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=10s']
assert {p['name'] for p in pods}=={'longhorn-manager-vr89r','longhorn-csi-plugin-sxzwn','instance-manager-d3fcafc43c01bde60d0358c3be85ac94'}
code='''import pathlib,json
pods=PODS
out={p['uid']:{'pod':p['name'],'processes':[]} for p in pods};errors=0;scanned=0;engines=[]
for proc in pathlib.Path('/proc').iterdir():
 if not proc.name.isdigit():continue
 try:cg=(proc/'cgroup').read_text();comm=(proc/'comm').read_text().strip();scanned+=1
 except FileNotFoundError:continue
 except PermissionError:errors+=1;continue
 if comm in ['longhorn','longhorn-engine','longhorn-replic'] or comm.startswith('instance-manag'):engines.append({'pid':proc.name,'comm':comm})
 for uid,row in out.items():
  if uid in cg or uid.replace('-','_') in cg:row['processes'].append({'pid':int(proc.name),'comm':comm})
print(json.dumps({'scanned':scanned,'permissionErrors':errors,'pods':out,'engineProcesses':engines}))
'''.replace('PODS',repr(pods))
audit=json.loads(subprocess.check_output(['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=5','-i','/home/sup/.ssh/id_rsa','sup@10.0.0.72','python3','-'],input=code.encode(),timeout=30))
assert audit['permissionErrors']==0 and not audit['engineProcesses']
assert all(all(p['comm']=='pause' for p in row['processes']) for row in audit['pods'].values())
(PRIVATE/'stale-peer-cgroup-audit-before-clear.json').write_text(json.dumps(audit,indent=2))
for row in pods:
 p=json.loads(subprocess.check_output(K+['-n','longhorn-system','get','pod',row['name'],'-o','json']))
 assert p['metadata']['uid']==row['uid'] and p['metadata'].get('deletionTimestamp') and p['spec']['nodeName']=='proxmox2-old' and not p['metadata'].get('finalizers')
 options={'apiVersion':'v1','kind':'DeleteOptions','gracePeriodSeconds':0,'preconditions':{'uid':row['uid']}}
 f=PRIVATE/'delete-stale-pod-options.json';f.write_text(json.dumps(options));f.chmod(0o600)
 log('STALE POD API RECORD CLEAR: '+row['name']+' UID='+row['uid']+'; normal deletion stuck; fresh exact-cgroup audit pause-only, no engine processes; UID-preconditioned grace0 API deletion only')
 subprocess.run(K+['delete','--raw','/api/v1/namespaces/longhorn-system/pods/'+row['name'],'-f',str(f)],stdout=subprocess.DEVNULL,check=True)
 print('Cleared verified stale record:',row['name'])

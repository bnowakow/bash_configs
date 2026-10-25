"""Read-only audit of externally coordinated Fleet rollout state transitions."""
import json,subprocess,time
from action_log import log
k=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s','-n','apps-bookstack'];last={};failed=False;deadline=time.monotonic()+3600
while time.monotonic()<deadline:
 try:ds=json.loads(subprocess.check_output(k+['get','deploy','bookstack','bookstack-mariadb','-o','json'],stderr=subprocess.PIPE))['items']
 except subprocess.CalledProcessError:
  if not failed:log('ROLLOUT AUDIT: API read failed; readiness cannot be established')
  failed=True;time.sleep(5);continue
 if failed:log('ROLLOUT AUDIT: API read recovered');failed=False
 complete=True
 for d in ds:
  name=d['metadata']['name'];claims=[v['persistentVolumeClaim']['claimName'] for v in d['spec']['template']['spec']['volumes'] if 'persistentVolumeClaim' in v];state={'desired':d['spec']['replicas'],'available':d['status'].get('availableReplicas',0),'updated':d['status'].get('updatedReplicas',0),'claims':claims}
  if last.get(name)!=state:log('WORKLOAD STATE '+name+': '+json.dumps(state,sort_keys=True));last[name]=state
  complete=complete and state['desired']==1 and state['available']==1 and state['updated']==1 and all(c.endswith('-longhorn-rwo') for c in claims)
 if complete:log('FLEET WORKLOAD ROLLOUT COMPLETE: both BookStack/MariaDB available on target claims; final mount/Secret/Fleet/HTTPS validation still required');break
 time.sleep(5)
else:raise SystemExit('Rollout audit deadline exceeded')

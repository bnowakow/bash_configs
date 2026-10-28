#!/usr/bin/python3
"""Restore maintenance workloads to applied Fleet manifests after migration success."""
import argparse,base64,datetime,gzip,json,pathlib,re,subprocess,time
import yaml
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s']

def obj(args):return json.loads(subprocess.check_output(K+args+['-o','json'],stderr=subprocess.PIPE,timeout=25))
def key(x):return (x['kind'].lower(),x.get('namespace',x.get('metadata',{}).get('namespace')),x.get('name',x.get('metadata',{}).get('name')))
def documents(text,namespace):
 out={}
 for d in yaml.safe_load_all(text):
  if not isinstance(d,dict) or d.get('kind') not in ['Deployment','StatefulSet','CronJob']:continue
  d.setdefault('metadata',{}).setdefault('namespace',namespace);out[key(d)]=d
 return out

def build_plan():
 maintenance=json.loads((HERE/'maintenance-plan.json').read_text())
 bds=obj(['get','bundledeployments','-A'])['items'];owners={}
 for bd in bds:
  for r in bd.get('status',{}).get('resources',[]):
   if r.get('kind') in ['Deployment','StatefulSet','CronJob']:owners[key(r)]=bd
 bundles={b['metadata']['name']:b for b in obj(['-n','fleet-local','get','bundles'])['items']};cache={};result=[]
 for original in maintenance['workloads']+maintenance['cronjobs']:
  if original['namespace']=='apps-mailpile' and original['name']=='mailpile':continue
  row=dict(original);field='suspend' if row['kind']=='cronjob' else 'replicas';bd=owners.get(key(row))
  if bd is None:
   if row['namespace'].startswith('apps-'):raise RuntimeError('No Fleet owner for '+row['namespace']+'/'+row['name'])
   row['basis']='Saved state: supporting service outside Fleet';result.append(row);continue
  name=bd['metadata']['name'];options=bd['spec'].get('options',{});namespace=options.get('defaultNamespace') or row['namespace']
  if bd['spec']['deploymentID']!=bd.get('status',{}).get('appliedDeploymentID'):raise RuntimeError('Fleet desired deployment not applied for '+name)
  if name not in cache:
   helm=options.get('helm',{})
   if helm.get('chart'):
    release=helm.get('releaseName') or name
    h=['helm','--kubeconfig','/etc/rancher/k3s/k3s.yaml','-n',namespace]
    status=json.loads(subprocess.check_output(h+['status',release,'-o','json'],stderr=subprocess.PIPE,timeout=25))
    if status['info']['status']!='deployed':raise RuntimeError('Fleet Helm release is not deployed for '+name)
    text=subprocess.check_output(h+['get','manifest',release],stderr=subprocess.PIPE,timeout=25).decode()
    cache[name]=documents(text,namespace)
   else:
    bundle=bundles[name]
    if bundle['spec'].get('kustomize'):raise RuntimeError('Render Kustomize before restoring '+name)
    docs={}
    for resource in bundle['spec'].get('resources',[]):
     text=resource.get('content','');encoding=resource.get('encoding','')
     if encoding:
      if encoding!='base64+gzip':raise RuntimeError('Unsupported resource encoding for '+name)
      text=gzip.decompress(base64.b64decode(text)).decode()
     if re.search(r'^apiVersion:',text,re.M):docs.update(documents(text,namespace))
    cache[name]=docs
  rendered=cache[name].get(key(row))
  if rendered is None:raise RuntimeError('Rendered Fleet workload missing: '+row['namespace']+'/'+row['name'])
  row[field]=rendered['spec'].get(field,False if field=='suspend' else 1)
  row['basis']='Fleet bundle '+name+' applied deployment '+bd['spec']['deploymentID'];row['bundle']=name;result.append(row)
 plan={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'workloads':result}
 (HERE/'fleet-restoration-plan.json').write_text(json.dumps(plan,indent=2)+'\n');return plan

def low_io():
 while True:
  local={r.split()[0]:float(r.split()[1].split('=')[1]) for r in pathlib.Path('/proc/pressure/io').read_text().splitlines()}
  peer=json.loads(subprocess.check_output(['/usr/bin/python3',str(HERE/'reclaim-free-blocks.py'),'--status'],stderr=subprocess.PIPE,timeout=30))
  if max(local['some'],peer['some'])<=10 and max(local['full'],peer['full'])<=2:return
  log('FLEET RESTORE WAIT: pressure above some10%/full2% on a host');time.sleep(15)

def apply(row):
 field='suspend' if row['kind']=='cronjob' else 'replicas';value=row[field]
 current=obj(['-n',row['namespace'],'get',row['kind'],row['name']])
 matches=current['spec'].get(field,False if field=='suspend' else 1)==value
 status=current.get('status',{})
 converged=(field=='suspend' or (value==0 and status.get('replicas',0)==0) or (status.get('availableReplicas',0)==value and status.get('updatedReplicas',0)==value and status.get('observedGeneration',0)>=current['metadata']['generation']))
 if matches and converged:
  log('FLEET RESTORED VERIFIED: '+row['namespace']+'/'+row['name']+' '+field+'='+str(value)+' (already converged; no patch)');return False
 low_io()
 ops=[{'op':'test','path':'/metadata/uid','value':current['metadata']['uid']},{'op':'add','path':'/spec/'+field,'value':value}]
 log('FLEET RESTORE ACTION: '+row['namespace']+'/'+row['name']+' '+field+'='+str(value)+'; '+row['basis'])
 subprocess.run(K+['-n',row['namespace'],'patch',row['kind'],row['name'],'--type=json','-p',json.dumps(ops)],stdout=subprocess.DEVNULL,check=True,timeout=25)
 if field=='replicas' and value>0:
  for _ in range(12):
   r=subprocess.run(['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','-n',row['namespace'],'rollout','status',row['kind']+'/'+row['name'],'--timeout=55s'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=65)
   if r.returncode==0:break
   time.sleep(5)
  else:raise RuntimeError('Restored workload not Ready: '+row['namespace']+'/'+row['name'])
 check=obj(['-n',row['namespace'],'get',row['kind'],row['name']]);assert check['spec'].get(field,False if field=='suspend' else 1)==value
 if field=='replicas' and value==0:assert check.get('status',{}).get('replicas',0)==0
 log('FLEET RESTORED VERIFIED: '+row['namespace']+'/'+row['name']+' '+field+'='+str(value));return True

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--plan',action='store_true');args=parser.parse_args()
 if not args.plan:
  if json.loads((HERE/'STATE.json').read_text())['phase']!='complete':raise RuntimeError('Migration must pass final validation first')
  subprocess.run(['/usr/bin/python3',str(HERE/'finalize.py')],check=True)
 plan=build_plan()
 if args.plan:
  for row in plan['workloads']:print(row['namespace'],row['name'],row.get('replicas',row.get('suspend')),row['basis'].split(' applied deployment ')[0])
  return
 def order(row):
  if row['kind']=='cronjob':return 4
  if row['namespace'].startswith('apps-') and any(s in row['name'] for s in ['postgresql','mariadb','mongodb']):return 0
  if row['namespace'].startswith('apps-'):return 1
  if row['namespace'].startswith('cattle-fleet-') and row['name'] in ['gitjob','helmops']:return 3
  return 2
 rows=sorted(plan['workloads'],key=lambda r:(order(r),r['namespace'],r['name']))
 for row in rows:
  if apply(row):time.sleep(5)
 # Accept only explicitly proven unchanged pre-maintenance CloudCasa runtime drift.
 # This is recorded, never presented as Fleet Ready or silently overwritten.
 exceptions=[]
 def unchanged_cloudcasa(b):
  if b['metadata']['name']!='cloudcasa' or b['spec']['deploymentID']!=b.get('status',{}).get('appliedDeploymentID'):return False
  saved=json.loads((PRIVATE/'deployments-before-quiesce.json').read_text())['items']
  old=next(d for d in saved if d['metadata']['namespace']=='cloudcasa-io' and d['metadata']['name']=='cloudcasa-kubeagent-manager')
  live=obj(['-n','cloudcasa-io','get','deployment','cloudcasa-kubeagent-manager'])
  return live['spec']['template']['spec']['containers']==old['spec']['template']['spec']['containers'] and live['spec']['replicas']==live.get('status',{}).get('availableReplicas')==1
 # Verify managed applications have converged, rather than accepting scale requests alone.
 names={r['bundle'] for r in rows if 'bundle' in r}
 for _ in range(60):
  bs=[b for b in obj(['get','bundledeployments','-A'])['items'] if b['metadata']['name'] in names]
  not_ready=[b for b in bs if not (b['spec']['deploymentID']==b.get('status',{}).get('appliedDeploymentID') and any(c['type']=='Ready' and c['status']=='True' for c in b.get('status',{}).get('conditions',[])))]
  if len(bs)==len(names) and all(unchanged_cloudcasa(b) for b in not_ready):
   exceptions=[{'bundle':b['metadata']['name'],'reason':'Pre-existing container-template drift; live template exactly matches pre-maintenance snapshot; one available replica; deployment ID applied','fleetReady':False} for b in not_ready];break
  time.sleep(5)
 else:raise RuntimeError('Some restored application bundles are not Fleet Ready')
 report={'completedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'restoredWorkloads':len(rows),'verifiedFleetBundles':sorted(names-{e['bundle'] for e in exceptions}),'preExistingFleetExceptions':exceptions}
 (HERE/'RESTORATION.json').write_text(json.dumps(report,indent=2)+'\n');log('FLEET RESTORATION COMPLETE: application scales match applied Fleet manifests; supporting services/schedules restored and rollouts verified; unchanged pre-existing Fleet exceptions='+str(len(exceptions)))

if __name__=='__main__':main()

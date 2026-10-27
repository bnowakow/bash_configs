"""Temporary maintenance shutdown and gradual restoration from saved replica counts."""
import datetime,json,pathlib,subprocess,sys,time,os
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent
PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
PLAN=HERE/'maintenance-plan.json'
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=12s']

def call(args):
 for attempt in range(6):
  extra=[] if attempt%2==0 else ['--server=https://10.0.0.72:6443']
  try:
   r=subprocess.run(K+extra+args,capture_output=True,timeout=20)
   if r.returncode==0:return r.stdout
  except subprocess.TimeoutExpired:pass
  time.sleep(2)
 raise RuntimeError('API action failed: '+' '.join(args[:5]))

def make_plan():
 if PLAN.exists():return json.loads(PLAN.read_text())
 items=[];kept=[]
 for kind in ['deployments','statefulsets']:
  for x in json.loads((PRIVATE/(kind+'-before-quiesce.json')).read_text())['items']:
   ns=x['metadata']['namespace'];name=x['metadata']['name']
   stop=(ns.startswith('apps-') and ns!='apps-adguard-home') or ns in ['cattle-capi-system','cattle-fleet-local-system','cattle-fleet-system','cattle-turtles-system','cloudcasa-io'] or (ns=='cattle-system' and name in ['rancher','system-upgrade-controller']) or (ns=='kube-system' and name=='metrics-server') or (ns=='longhorn-system' and name=='longhorn-ui')
   row={'namespace':ns,'kind':x['kind'].lower(),'name':name,'uid':x['metadata']['uid'],'replicas':x['spec'].get('replicas',1)}
   (items if stop else kept).append(row)
 jobs=[]
 for x in json.loads((PRIVATE/'cronjobs-complete-before-quiesce.json').read_text())['items']:
  jobs.append({'namespace':x['metadata']['namespace'],'kind':'cronjob','name':x['metadata']['name'],'uid':x['metadata']['uid'],'suspend':x['spec'].get('suspend',False)})
 plan={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'workloads':items,'kept':kept,'cronjobs':jobs}
 PLAN.write_text(json.dumps(plan,indent=2)+'\n');return plan

def mutate(row,value):
 field='suspend' if row['kind']=='cronjob' else 'replicas'
 ops=[{'op':'test','path':'/metadata/uid','value':row['uid']},{'op':'add','path':'/spec/'+field,'value':value}]
 log('MAINTENANCE ACTION: '+row['namespace']+'/'+row['kind']+'/'+row['name']+' '+field+'='+str(value))
 call(['-n',row['namespace'],'patch',row['kind'],row['name'],'--type=json','-p',json.dumps(ops)])

def controls(row):
 return row['namespace'].startswith('cattle-fleet-') or (row['namespace']=='cattle-system' and row['name']=='rancher') or row['namespace']=='apps-authelia'

def database(row):return any(s in row['name'] for s in ['postgresql','mariadb','mongodb'])

def wait_low_io():
 while True:
  try:
   r=subprocess.run([sys.executable,str(HERE/'reclaim-free-blocks.py'),'--status'],capture_output=True,timeout=30)
   m=json.loads(r.stdout)
   if m['some']<=10 and m['full']<=2:return
   log('MAINTENANCE RESTORE WAIT: peer PSI some=%.2f full=%.2f'%(m['some'],m['full']))
  except (subprocess.TimeoutExpired,ValueError):log('MAINTENANCE RESTORE WAIT: peer pressure unavailable')
  time.sleep(15)

def rollout(row):
 args=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','-n',row['namespace'],'rollout','status',row['kind']+'/'+row['name'],'--timeout=55s']
 for _ in range(12):
  if subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=65).returncode==0:return
  time.sleep(5)
 raise RuntimeError('Restored workload did not become ready: '+row['namespace']+'/'+row['name'])

plan=make_plan();mode=sys.argv[1]
if mode=='restore':
 # Latest user instruction: application scales come from Fleet, not saved live counts.
 os.execv('/usr/bin/python3',['/usr/bin/python3',str(HERE/'restore-fleet.py')])
if mode=='plan':
 print(json.dumps({'stop':[r['namespace']+'/'+r['name'] for r in plan['workloads'] if r['replicas']>0],'keep':[r['namespace']+'/'+r['name'] for r in plan['kept']]},indent=2))
elif mode=='stop':
 # Freeze Fleet before changing desired application scale.
 rows=sorted(plan['workloads'],key=lambda r:(0 if r['name']=='fleet-agent' else 1 if r['namespace'].startswith('cattle-fleet-') else 3 if database(r) else 2,r['namespace'],r['name']))
 for row in rows:
  if row['replicas']>0 and not database(row):mutate(row,0)
 # Give application processes time to close connections before stopping databases.
 time.sleep(30)
 for row in rows:
  if row['replicas']>0 and database(row):mutate(row,0)
 for row in plan['cronjobs']:mutate(row,True)
 log('MAINTENANCE SHUTDOWN REQUESTS ACCEPTED: '+str(sum(r['replicas']>0 for r in rows))+' workloads; '+str(len(plan['cronjobs']))+' CronJobs suspended; verify actual Pods gone before claiming shutdown complete')
elif mode in ['restore-controller','restore-agent','restore-control','restore-saved']:
 rows=[r for r in plan['workloads'] if r['replicas']>0 and r['name']!='mailpile' and (mode=='restore-saved' or (mode=='restore-control' and controls(r)) or (mode=='restore-controller' and r['name']=='fleet-controller') or (mode=='restore-agent' and r['name']=='fleet-agent'))]
 rows.sort(key=lambda r:(0 if database(r) else 1 if controls(r) else 2,r['namespace'],r['name']))
 donefile=PRIVATE/'maintenance-restored.json';done=set(json.loads(donefile.read_text())) if donefile.exists() else set()
 for row in rows:
  key=row['namespace']+'/'+row['kind']+'/'+row['name']
  if key in done:continue
  if row['name']=='fleet-agent':
   bundle=call(['-n','fleet-local','get','bundle','mailpile','-o','json']).decode()
   assert all(claim in bundle for claim in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']),'Do not restore Fleet agent while Mailpile still has old source bundle'
  wait_low_io();mutate(row,row['replicas']);rollout(row);done.add(key);donefile.write_text(json.dumps(sorted(done)))
  log('MAINTENANCE RESTORED READY: '+key+' replicas='+str(row['replicas']));time.sleep(5)
 if mode=='restore-saved':
  for row in plan['cronjobs']:mutate(row,row['suspend'])
  log('MAINTENANCE RESTORE COMPLETE: original replica counts restored gradually; original zero-replica workloads preserved; Mailpile managed by its migration')
else:raise SystemExit('Expected stop, restore-control or restore')

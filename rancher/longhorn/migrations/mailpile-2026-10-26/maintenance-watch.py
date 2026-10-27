"""Bridge the already-running migration to safe Fleet cutover and gradual restore."""
import fcntl,json,pathlib,subprocess,sys,time
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
lock=(PRIVATE/'maintenance-watch.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=10s']
def obj(args):return json.loads(subprocess.check_output(K+args+['-o','json'],stderr=subprocess.PIPE,timeout=15))
def restore(mode):
 log('MAINTENANCE WATCH: '+mode+' requested')
 subprocess.run([sys.executable,str(HERE/'quiesce-workloads.py'),mode],check=True)
baseline=PRIVATE/'maintenance-mailpile-bd-before.json'
while not baseline.exists():
 try:
  bs=obj(['get','bundledeployments','-A'])['items'];old=next(b for b in bs if b['metadata']['name']=='mailpile');baseline.write_text(json.dumps(old))
 except (subprocess.CalledProcessError,subprocess.TimeoutExpired,ValueError):
  log('MAINTENANCE WATCH WAIT: cannot yet save old deployment ID');time.sleep(15)
old=json.loads(baseline.read_text());controller=False;agent=False
log('MAINTENANCE WATCH STARTED: Fleet stays stopped during copy; controller resumes after copy verification, agent only after new target BundleDeployment; applications restored to Fleet desired state after migration completion')
while True:
 try:
  state=json.loads((HERE/'STATE.json').read_text());phase=state['phase']
  if phase in ['failed_requires_review','validation_requires_review','requires_review','deadline_reached']:
   log('MAINTENANCE WATCH HOLD: migration needs review; workloads remain quiesced, no unsafe Fleet/source restart');raise SystemExit(1)
  audit=(HERE/'ACTIONS.log').read_text()
  if not controller and 'COPY PASSED: every regular-file source/target byte verified' in audit:
   restore('restore-controller');controller=True
  if controller and not agent:
   bundle=obj(['-n','fleet-local','get','bundle','mailpile'])
   if all(c in json.dumps(bundle['spec']) for c in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']):
    bd=obj(['-n',old['metadata']['namespace'],'get','bundledeployment','mailpile'])
    if bd['spec']['deploymentID']!=old['spec']['deploymentID'] and not bd['spec'].get('paused') and not bd['spec'].get('waitingForValues'):
     restore('restore-agent');agent=True;log('MAINTENANCE WATCH: Fleet agent restored only after new target deploymentID observed; old source bundle was never reactivated')
  if phase=='complete':
   restore('restore');log('MAINTENANCE WATCH COMPLETE: applications restored to verified Fleet desired state after successful Mailpile migration; supporting services/schedules restored');break
 except (subprocess.CalledProcessError,subprocess.TimeoutExpired,ValueError,KeyError):
  log('MAINTENANCE WATCH WAIT: API/read/restore unavailable; preserving current safe state')
 time.sleep(15)

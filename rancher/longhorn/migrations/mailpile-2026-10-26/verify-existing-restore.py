"""Verify existing scratch restore only; never cut over or restore applications."""
import datetime,fcntl,json,pathlib,subprocess,sys
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
lock=(PRIVATE/'existing-restore-verification.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s'];NS='apps-mailpile';pod='mailpile-restore-20261026'
def obj(args):return json.loads(subprocess.check_output(K+args+['-o','json']))
def state(phase,detail):
 tmp=HERE/'STATE.restore.tmp';tmp.write_text(json.dumps({'phase':phase,'detail':detail,'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')},indent=2)+'\n');tmp.replace(HERE/'STATE.json')
assert obj(['-n',NS,'get','deploy','mailpile'])['spec']['replicas']==0
p=obj(['-n',NS,'get','pod',pod]);assert any(c['type']=='Ready' and c['status']=='True' for c in p['status']['conditions'])
assert p['spec']['nodeName']=='proxmox3'
refs={v.get('persistentVolumeClaim',{}).get('claimName') for v in p['spec']['volumes']}
assert refs>={'mailpile-data-restore-20261026','mailpile-keys-restore-20261026'}
for extra in ([],['--server=https://10.0.0.72:6443']):assert subprocess.check_output(K+extra+['get','--raw=/readyz']).strip()==b'ok'
state('restore_verification','Verifying existing independent restore only; prior API guard alert retained; no cutover or app restoration authorized by this stage')
log('INDEPENDENT RESTORE RECOVERY START: existing Ready scratch restore, source replicas0; old API alert retained; no data recopy/cutover')
subprocess.run(K+['-n',NS,'cp',str(PRIVATE/'manifest.json'),pod+':/tmp/mailpile-manifest.json','-c','transfer'],check=True)
try:
 with (PRIVATE/'coordinator-output.log').open('ab',buffering=0) as output:
  for container,script,argv in [('transfer','copy-and-verify.py',['prepare-restore-roots']),('transfer','copy-and-verify.py',['verify']),('keyring','check-keyring.py',[])]:
   subprocess.run(K+['-n',NS,'exec','-i',pod,'-c',container,'--','python','-u','-']+argv,input=(HERE/script).read_bytes(),stdout=output,stderr=output,check=True)
 state('requires_review','Independent restore hashes/keyring passed; original API alert requires fresh source revalidation and health checks before cutover')
 log('INDEPENDENT RESTORE RECOVERY PASSED: full manifest and keyring matched; apps remain stopped; original API guard not cleared')
except BaseException:
 state('validation_requires_review','Existing restore verification failed; apps remain stopped and all original claims retained');raise

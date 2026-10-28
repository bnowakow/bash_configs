"""Revalidate original source after the API gap; read-only, no cutover."""
import datetime,fcntl,json,pathlib,subprocess,threading,time
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');NS='apps-mailpile';POD='mailpile-transfer-20261026'
lock=(PRIVATE/'source-reverification.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s']
def run(args,**kw):return subprocess.run(K+args,check=True,**kw)
def obj(args):return json.loads(subprocess.check_output(K+args+['-o','json']))
def state(phase,detail):
 tmp=HERE/'STATE.source.tmp';tmp.write_text(json.dumps({'phase':phase,'detail':detail,'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')},indent=2)+'\n');tmp.replace(HERE/'STATE.json')
def healthy():
 assert obj(['-n',NS,'get','deploy','mailpile'])['spec']['replicas']==0
 for extra in ([],['--server=https://10.0.0.72:6443']):assert subprocess.check_output(K+extra+['get','--raw=/readyz']).strip()==b'ok'
assert 'INDEPENDENT RESTORE RECOVERY PASSED:' in (HERE/'ACTIONS.log').read_text()
healthy()
# No live pod may mount original claims or production target claims at this point.
claims={'mailpile-path1','mailpile-path2','mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'}
for p in obj(['-n',NS,'get','pods'])['items']:
 if p['status']['phase'] not in ['Succeeded','Failed']:
  assert not any(v.get('persistentVolumeClaim',{}).get('claimName') in claims for v in p['spec'].get('volumes',[]))
pod=json.loads((HERE/'transfer-pod.json').read_text());pod['spec']['volumes']=[{'name':'target-'+key,'persistentVolumeClaim':{'claimName':claim,'readOnly':True}} for key,claim in [('data','mailpile-path1'),('keys','mailpile-path2')]]
for c in pod['spec']['containers']:
 c['volumeMounts']=[dict(m,readOnly=True) for m in c['volumeMounts'] if m['name'].startswith('target-')]
f=PRIVATE/'source-reverification-pod.json';f.write_text(json.dumps(pod));f.chmod(0o600)
run(['create','-f',str(f)])
run(['-n',NS,'wait','--for=condition=Ready','pod/'+POD,'--timeout=5m'])
run(['-n',NS,'cp',str(PRIVATE/'manifest.json'),POD+':/tmp/mailpile-manifest.json','-c','transfer'])
# Start conservatively before the monitor attaches to this new helper UID.
cfg={'copyKiBps':256,'verifyKiBps':512,'reuseKiBps':1024,'metadataEntriesPerSecond':20,'pause':True}
run(['-n',NS,'exec','-i',POD,'-c','transfer','--','python','-c','import pathlib,sys;pathlib.Path("/tmp/mailpile-rate.json").write_bytes(sys.stdin.buffer.read())'],input=json.dumps(cfg).encode())
state('source_reverification','Full original-source hashes/metadata against copied manifest, RO mounts; prior API guard retained until this succeeds')
log('SOURCE REVERIFICATION START: original claims mounted read-only; full hash/metadata/link comparison; old API alert retained; no application startup')
stop=threading.Event();gap=threading.Event()
def guard():
 while not stop.wait(5):
  try:healthy()
  except BaseException:gap.set();log('SOURCE REVERIFICATION GUARD: source/API health gap; completion blocked');return
threading.Thread(target=guard,daemon=True).start()
try:
 with (PRIVATE/'coordinator-output.log').open('ab',buffering=0) as output:
  output.write(b'ORIGINAL_SOURCE_HASH_REVERIFICATION_START\n')
  run(['-n',NS,'exec','-i',POD,'-c','transfer','--','python','-u','-','verify'],input=(HERE/'copy-and-verify.py').read_bytes(),stdout=output,stderr=output)
 healthy();assert not gap.is_set(),'API/source guard gap during source revalidation'
 evidence={'completedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),'sourceClaims':sorted(claims-{'mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'}),'fullManifestMatched':True,'guardGap':False}
 (PRIVATE/'source-reverification-passed.json').write_text(json.dumps(evidence,indent=2)+'\n')
 log('SOURCE REVERIFICATION PASSED: original bytes/full metadata/links match verified-copy manifest; healthy source0/API monitoring; prior guard remains archived evidence until reviewed cutover')
 state('source_reverified','Original source fully matches copied manifest and independent restore; final target/Fleet/API review and guarded cutover remain')
except BaseException:
 state('validation_requires_review','Original source verification failed or health guard gap; apps remain stopped');raise
finally:stop.set()

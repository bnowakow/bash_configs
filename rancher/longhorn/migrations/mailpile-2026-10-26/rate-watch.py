"""Monitor both hosts during copy; pause and reduce the live cap on pressure."""
import argparse,datetime,fcntl,json,pathlib,subprocess,sys,time,os
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
lock=(PRIVATE/'rate-watch.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
parser=argparse.ArgumentParser();parser.add_argument('--cap',type=int,default=512);args=parser.parse_args();assert 64<=args.cap<=16384
cap=args.cap;applied=None;last_log=0;good=0;paused=False
try:last_documented_cap=json.loads((HERE/'RATE.json').read_text())['copyKiBps']
except (OSError,ValueError,KeyError):last_documented_cap=None
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=10s']
log('RATE MONITOR START: requested copy%dKiB/s; both hosts PSI guard some10%%/full2%%; high pressure pauses and lowers cap256, recovery requires3 low samples; backing pool20%%+2Gi floor'%cap)
while True:
 phase=json.loads((HERE/'STATE.json').read_text())['phase']
 audit=(HERE/'ACTIONS.log').read_text()
 if phase in ['complete','failed_requires_review','validation_requires_review','requires_review','deadline_reached'] or 'COPY PASSED: every regular-file source/target byte verified' in audit:
  log('RATE MONITOR STOP: copy finished or workflow requires review; native backup/restore retain their own controls');break
 try:
  local={r.split()[0]:float(r.split()[1].split('=')[1]) for r in pathlib.Path('/proc/pressure/io').read_text().splitlines()}
  peer=json.loads(subprocess.check_output([sys.executable,str(HERE/'reclaim-free-blocks.py'),'--status'],stderr=subprocess.PIPE,timeout=30))
  high=max(local['some'],peer['some'])>10 or max(local['full'],peer['full'])>2 or peer['free']<int(peer['size']*.2)+2*1024**3
  if high:paused=True;cap=256;good=0
  else:
   good+=1
   if good>=3:paused=False
  metrics={'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),'pid':os.getpid(),'copyKiBps':cap,'paused':paused,'localPSI':local,'peerPSI':{'some':peer['some'],'full':peer['full']},'peerFreeGiB':peer['free']/1024**3}
  tmp=HERE/'RATE.tmp';tmp.write_text(json.dumps(metrics,indent=2)+'\n');tmp.replace(HERE/'RATE.json')
  if time.monotonic()-last_log>=60 or applied!= (cap,paused):
   log('RATE MONITOR: capKiBps=%d pause=%s localPSI=%.2f/%.2f peerPSI=%.2f/%.2f peerFreeGiB=%.2f'%(cap,paused,local['some'],local['full'],peer['some'],peer['full'],peer['free']/1024**3));last_log=time.monotonic()
 except (subprocess.SubprocessError,ValueError,OSError):
  paused=True;cap=256;good=0;log('RATE MONITOR: telemetry unavailable; requesting conservative pause')
 if applied!=(cap,paused):
  cfg=json.dumps({'copyKiBps':cap,'verifyKiBps':512,'pause':paused}).encode()
  code='import pathlib,sys;p=pathlib.Path("/tmp/mailpile-rate.json");t=p.with_suffix(".tmp");t.write_bytes(sys.stdin.buffer.read());t.replace(p)'
  try:
   subprocess.run(K+['-n','apps-mailpile','exec','-i','mailpile-transfer-20261026','-c','transfer','--','python','-c',code],input=cfg,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,check=True,timeout=20);applied=(cap,paused)
   log('RATE LIMIT APPLIED: copyKiBps=%d verifyKiBps=512 pause=%s'%(cap,paused))
   if cap!=last_documented_cap:
    stamp=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds');reason='Automatic safety reduction: pressure/headroom/telemetry guard' if cap==256 else 'User-requested monitored cap trial'
    with (HERE/'TRANSFER-CAPS.md').open('a') as f:
     f.write('| '+stamp+' | '+str(last_documented_cap or 'unknown')+' → '+str(cap)+' KiB/s | '+reason+'; pause='+str(paused)+'. See contemporaneous RATE MONITOR samples in ACTIONS.log. |\n');f.flush();os.fsync(f.fileno())
    last_documented_cap=cap
  except subprocess.SubprocessError:log('RATE MONITOR: live limit update not yet accepted; retry next sample')
 time.sleep(15)

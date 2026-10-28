"""Supervise the existing orphaned coordinator without restarting its worker."""
import datetime,fcntl,json,pathlib,subprocess,sys,time
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent
PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
lock=(PRIVATE/'recovery-supervisor.lock').open('w')
fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
pid=1200585
cmd=pathlib.Path(f'/proc/{pid}/cmdline')
assert cmd.exists() and b'/mailpile-2026-10-26/migrate.py' in cmd.read_bytes()
log('RECOVERY SUPERVISOR: attached to surviving coordinator; no worker restart; final validation required before Fleet application restoration')
while cmd.exists():
 try:
  if b'/mailpile-2026-10-26/migrate.py' not in cmd.read_bytes():break
 except FileNotFoundError:break
 time.sleep(15)
audit=(HERE/'ACTIONS.log').read_text()
def state(phase,detail):
 tmp=HERE/'STATE.recovery.tmp'
 tmp.write_text(json.dumps({'phase':phase,'detail':detail,'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')},indent=2)+'\n')
 tmp.replace(HERE/'STATE.json');log('RECOVERY SUPERVISOR: '+phase+' '+detail)
if 'CUTOVER ROLLOUT PASSED: Mailpile Ready on both Longhorn claims' not in audit:
 state('failed_requires_review','Surviving coordinator exited without confirmed target rollout; applications remain stopped');sys.exit(1)
state('rollout_complete','Recovered coordinator completed target rollout; running final independent validation')
result=subprocess.run(['/usr/bin/python3',str(HERE/'finalize.py')])
if result.returncode:
 state('validation_requires_review','Final validation failed; applications remain stopped');sys.exit(1)
state('complete','Mailpile migration and final checks passed; maintenance watcher may restore Fleet desired state')

"""Read-only final runtime validation and completion records after successful cutover."""
import csv,datetime,hashlib,io,json,pathlib,subprocess,sys,time
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[2];PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=20s'];NS='apps-mailpile'
def obj(args):return json.loads(subprocess.check_output(K+args+['-o','json']))
try:
 d=obj(['-n',NS,'get','deploy','mailpile']);assert d['spec']['replicas']==d['status'].get('availableReplicas')==1 and d['spec']['strategy']['type']=='Recreate';old=json.loads((PRIVATE/'source-deployment-final.json').read_text());a=d['spec']['template']['spec']['containers'][0];b=old['spec']['template']['spec']['containers'][0];assert a['image']==b['image'] and a.get('env')==b.get('env'),'Image/env changed'
 pods=obj(['-n',NS,'get','pods','-l','app.kubernetes.io/instance=mailpile'])['items'];pods=[p for p in pods if p['status']['phase']=='Running' and not p['metadata'].get('deletionTimestamp')];assert len(pods)==1;refs={v.get('persistentVolumeClaim',{}).get('claimName') for v in pods[0]['spec']['volumes']};assert refs >= {'mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'} and not refs.intersection({'mailpile-path1','mailpile-path2'})
 replicas=obj(['-n','longhorn-system','get','replicas.longhorn.io'])['items']
 for claim in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']:
  p=obj(['-n',NS,'get','pvc',claim]);assert p['status']['phase']=='Bound';v=obj(['-n','longhorn-system','get','volumes.longhorn.io',p['spec']['volumeName']]);assert v['status']['robustness']=='healthy' and v['spec']['numberOfReplicas']==2;nodes={r['spec']['nodeID'] for r in replicas if r['spec']['volumeName']==v['metadata']['name'] and r['status']['currentState']=='running'};assert len(nodes)==2
 for claim in ['mailpile-path1','mailpile-path2']:
  p=obj(['-n',NS,'get','pvc',claim]);assert p['status']['phase']=='Bound' and p['metadata']['annotations'].get('helm.sh/resource-policy')=='keep';pv=obj(['get','pv',p['spec']['volumeName']]);assert pv['spec']['persistentVolumeReclaimPolicy']=='Retain'
 def opaque(j):return {x['metadata']['name']:x.get('data',{}) for x in j['items'] if x.get('type')=='Opaque'}
 assert opaque(obj(['-n',NS,'get','secrets']))==opaque(json.loads((PRIVATE/'source-secrets.json').read_text())),'Opaque Secret data changed'
 ready=False
 for _ in range(60):
  bs=[b for b in obj(['get','bundledeployments','-A'])['items'] if b['metadata']['name'] in ['mailpile','longhorn-mailpile-storage']]
  if len(bs)==2 and all(b['status'].get('appliedDeploymentID')==b['spec']['deploymentID'] and any(c['type']=='Ready' and c['status']=='True' for c in b['status'].get('conditions',[])) for b in bs):ready=True;break
  time.sleep(5)
 assert ready,'Fleet readiness not verified'
 for suffix in ['tailscale','localdomain']:
  code=subprocess.check_output(['curl','-fsSL','--connect-timeout','10','--max-time','30','-o','/dev/null','-w','%{http_code}','https://mailpile.rancher.'+suffix+'.bnowakowski.pl/']).decode();assert code=='200','HTTPS validation failed'
 summary=json.loads((PRIVATE/'backup-summary.json').read_text())
 for r in summary:
  b=obj(['-n','longhorn-system','get','backups.longhorn.io',r['backup']]);assert b['status']['state']=='Completed' and b['status']['volumeName']==r['volume']
 manifest=json.loads((PRIVATE/'manifest.json').read_text());logical=sum(r['size'] for r in manifest['data']['entries'].values() if r['type']=='file' and 'hardlink_to' not in r);digest=hashlib.sha256((PRIVATE/'manifest.json').read_bytes()).hexdigest();stamp=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')
 text=f'''# Mailpile migration completed — {stamp}

Mailpile now runs on **12Gi data +256Mi keys**, RWO with **two healthy replicas
on distinct hosts**. One app instance, Recreate. Current chart/image/env and
Opaque Secret data were preserved. Actual pod target mounts, Fleet deployment
IDs/Ready, both HTTPS endpoints (200 after redirects) and original source
keep/Retain protection passed final checks.

Stopped-copy logical data: **{logical:,} bytes**; data entries:
**{len(manifest['data']['entries']):,}**. Every copied regular-file chunk was read
back and source/target SHA256 compared. Full metadata, ownership, modes,
timestamps, sparse content, symlinks and hardlink relationships were preserved.
An API readiness gap blocked the initial cutover. A fresh full original-source
hash/metadata/link recheck passed before recovered cutover. Scratch restore root
timestamps were restored to the expected manifest values; strict full restore
verification and cloned keyring checks then passed.

Quiesced native NAS backups of both targets were independently restored and
verified against the complete manifest; cloned GnuPG parsing passed using the
unchanged app image. No messages were decrypted/sent in isolated checks.
The disposable restore used one strict-local replica on proxmox3 only, to avoid
extra peer-pool pressure. Production retained two replicas. Scratch restore
claims/classes/helpers and temporary backup membership were cleaned up.

File transfer started at **256KiB/s**, then resumed with verified file reuse
and live cap adjustments at user request; hashing caps were adjusted live under
both-host pressure monitoring.
Every cap change and observed outcome is recorded in **TRANSFER-CAPS.md**.
The rate monitor watches both hosts, pauses under pressure and reduces the copy
cap to256KiB/s if necessary; ACTIONS.log records actual adjustments.
high host PSI pauses work without catch-up bursts. Native backup/restore and
rebuild concurrency were temporarily limited to one. Those global limits
remain at one for now; previous values are recorded privately for an operator
to restore after stability review. Peer manager recovery, unverified staging
replacement and bounded free-block reclamation are recorded in ACTIONS.log.
No storage finalizer was forced. Only a confirmed stale manager Pod record was
force-deleted after normal deletion failed and its daemon was absent.

Private stopped-copy manifest SHA256: `{digest}`. Its filenames and all Secret/
mail/key contents remain outside Git under `/tmp/longhorn-mailpile-20261026`.
Original local source PVCs/PVs are retained as stale rollback copies. Do not
return to them without stopping target writers and reconciling later mail.

Login, mail reading/indexing and normal fetch behavior still require user
functional testing. The underlying peer NVMe/I/O reliability problem is not
claimed repaired by this migration. See [actions](ACTIONS.log), [handoff](HANDOFF.md)
and [procedure](README.md).

## NAS backup records

'''.replace('+256Mi','+ 256Mi')
 for r in summary:text+='- '+r['tree']+': `'+r['backup']+'`, created `'+r['created']+'`, source volume `'+r['volume']+'`.\n'
 (HERE/'RESULTS.md').write_text(text)
 p=ROOT/'longhorn/local-pvc-usage-2026-10-24.csv';rows=list(csv.DictReader(io.StringIO(p.read_text())));fields=list(rows[0])
 for r in rows:
  if r['namespace']==NS:r['migration_wave']='completed-mailpile-rwo';r['remaining_size_rank']=''
 out=io.StringIO(newline='');w=csv.DictWriter(out,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows);p.write_text(out.getvalue());done=[r for r in rows if r['migration_wave'].startswith('completed')];total=sum(float(r['suggested_GiB']) for r in done)
 notice=f'''\n**Mailpile completed — {stamp}:** final planned migration finished last.
Mailpile uses12Gi data +256Mi keys on Longhorn RWO/two replicas. Planned inventory
now records **{len(done)} completed claims / {total:g}Gi requested**. No planned
application remains on active local-path storage; Mailpile's two original local
claims are retained unused rollback copies, not live mounts. Earlier pending/
staging and active-local statements below are historical, superseded by this
completion. See [results](migrations/mailpile-2026-10-26/RESULTS.md) and
[action log](migrations/mailpile-2026-10-26/ACTIONS.log). User functional tests
remain; no default replica policy or general migration cap was changed.\n\n'''.replace('uses12Gi','uses 12Gi').replace('+256Mi','+ 256Mi')
 for name in ['current-app-storage-summary-2026-10-24.md','remaining-migration-priority-2026-10-24.md']:
  p=ROOT/'longhorn'/name;s=p.read_text();a=s.index('\n')+1;p.write_text(s[:a]+notice+s[a:])
 with (HERE/'HANDOFF.md').open('a') as f:f.write('\n## COMPLETED '+stamp+'\n\nFinal runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.\n')
 log('FINAL VALIDATION AND DOCUMENTATION PASSED: Mailpile Ready on targets, Fleet Ready, identical image/env/Opaque Secrets, healthy two-host replicas, retained originals, both HTTPS200, NAS backups/restores verified; inventory complete claims='+str(len(done))+' Gi='+str(total))
except BaseException as e:
 log('FINAL VALIDATION FAILED: '+type(e).__name__+'; target already cut over, no blind rollback');raise

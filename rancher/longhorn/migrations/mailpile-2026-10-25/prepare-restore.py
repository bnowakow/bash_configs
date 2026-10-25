"""Build scratch restores from this run's quiesced native backups."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent
backups = json.load(open('/tmp/mailpile-backups.json'))['items']
pvcs = json.load(open('/tmp/mailpile-backup-pvcs.json'))['items']
start = json.load(open('/tmp/mailpile-backup-job.json'))['status']['startTime']
prepared = json.loads((here / 'prepared-fleet-files.json').read_text())
# The application image is recorded independently from the current source object.
live = json.load(open('/tmp/mailpile-preflight.json'))['items']
image = next(d for d in live if d['kind'] == 'Deployment' and d['metadata']['name'] == 'mailpile')['spec']['template']['spec']['containers'][0]['image']
items, volumes, mounts, summary = [], [], [], []
for claim, size, name in [('mailpile-path1', '9Gi', 'data'), ('mailpile-path2', '256Mi', 'keys')]:
    pvc = next(p for p in pvcs if p['metadata']['name'] == claim + '-longhorn-rwo')
    volume = pvc['spec']['volumeName']
    matches = [b for b in backups if b.get('status', {}).get('volumeName') == volume and b['status']['state'] == 'Completed' and b['status'].get('backupCreatedAt', '') >= start]
    if not matches:
        raise RuntimeError('No fresh completed backup for ' + claim)
    backup = max(matches, key=lambda b: b['status']['backupCreatedAt'])
    summary.append({'source': claim, 'claim': pvc['metadata']['name'], 'volume': volume, 'backup': backup['metadata']['name']})
    n = claim + '-restore-20261025'
    sc = 'longhorn-' + n
    items.append({'apiVersion': 'storage.k8s.io/v1', 'kind': 'StorageClass', 'metadata': {'name': sc}, 'provisioner': 'driver.longhorn.io', 'allowVolumeExpansion': True, 'reclaimPolicy': 'Delete', 'volumeBindingMode': 'Immediate', 'parameters': {'numberOfReplicas': '2', 'fsType': 'ext4', 'dataEngine': 'v1', 'backupTargetName': 'default', 'fromBackup': backup['status']['url']}})
    items.append({'apiVersion': 'v1', 'kind': 'PersistentVolumeClaim', 'metadata': {'name': n, 'namespace': 'apps-mailpile'}, 'spec': {'accessModes': ['ReadWriteOnce'], 'storageClassName': sc, 'resources': {'requests': {'storage': size}}}})
    volumes.append({'name': name, 'persistentVolumeClaim': {'claimName': n, 'readOnly': True}})
    mounts.append({'name': name, 'mountPath': '/target/' + name, 'readOnly': True})
volumes.append({'name': 'evidence', 'persistentVolumeClaim': {'claimName': 'mailpile-migration-evidence-20261025', 'readOnly': True}})
mounts.append({'name': 'evidence', 'mountPath': '/evidence', 'readOnly': True})
items.append({'apiVersion': 'batch/v1', 'kind': 'Job', 'metadata': {'name': 'mailpile-isolated-restore-20261025', 'namespace': 'apps-mailpile'}, 'spec': {'backoffLimit': 0, 'activeDeadlineSeconds': 2400, 'template': {'spec': {'restartPolicy': 'Never', 'automountServiceAccountToken': False, 'initContainers': [{'name': 'verify-manifest', 'image': 'python:3.13-slim', 'command': ['python', '-u', '-c', (here / 'manifest-check.py').read_text()], 'volumeMounts': mounts, 'resources': {'requests': {'cpu': '50m', 'memory': '64Mi'}, 'limits': {'cpu': '500m', 'memory': '2Gi'}}}], 'containers': [{'name': 'keyring-check', 'image': image, 'command': ['python', '-c', (here / 'check-keyring.py').read_text()], 'volumeMounts': [m for m in mounts if m['name'] == 'keys'], 'securityContext': {'runAsUser': 0, 'runAsGroup': 0, 'allowPrivilegeEscalation': False}, 'resources': {'requests': {'cpu': '50m', 'memory': '64Mi'}, 'limits': {'cpu': '500m', 'memory': '512Mi'}}}], 'volumes': volumes}}}})
json.dump({'apiVersion': 'v1', 'kind': 'List', 'items': items}, open('/tmp/mailpile-isolated-restore.json', 'w'), indent=2)
json.dump(summary, open('/tmp/mailpile-backup-summary.json', 'w'), indent=2)
print('Two fresh quiesced backups selected; isolated restore prepared')

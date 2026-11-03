# Piwigo (cycuszki): security considerations and TODO

Piwigo holds sensitive photos. Goal: **no photo, thumbnail or photo metadata is
ever stored unencrypted**, and nothing is visible without a login. This file
records what protects that, where the gaps are, and what still has to be done
or re-checked. Deployment details: `fleet/apps/piwigo/README.md`; encrypted
storage: `fleet/infrastructure/longhorn-crypto-storage/README.md`; k3s
Secrets encryption: `doc/k3s-secrets-encryption.md`.

## TODO

Open items. Tick them off with the date and how it was verified.

### Must do

- [ ] **Store the disk-encryption passphrase outside the cluster** (password
  manager). Without it the volumes and their NAS backups cannot be restored.
  `kubectl -n longhorn-system get secret longhorn-crypto -o jsonpath='{.data.CRYPTO_KEY_VALUE}' | base64 -d; echo`
- [ ] **Change the Piwigo admin password** (user `sup`, Profile in Piwigo).
  The initial one is also in plain text in the Deployment's `postStart`
  command, which is not encrypted at rest.
- [ ] **CloudCasa: exclude `apps-piwigo`** from every backup definition in the
  CloudCasa portal (Protection, then backup definitions). See
  [CloudCasa](#cloudcasa).
- [ ] **CloudCasa: exclude `longhorn-system`** (or at least its Secrets), so the
  `longhorn-crypto` passphrase is never uploaded.
- [ ] **CloudCasa: check the remaining definitions** for "copy to CloudCasa
  storage" or file-level backup, and note which namespaces they cover.
- [ ] **Store the k3s server token outside the cluster.** With Secrets
  encryption on, an etcd snapshot restore needs the token to decrypt the
  bootstrap data, which holds the encryption key.
  `sudo cat /var/lib/rancher/k3s/server/token`
- [ ] **Commit the README update** in `fleet/apps/piwigo/README.md`, with the
  commands for reading the secrets and the validation notes. It is not pushed
  yet.

### Verify soon

- [ ] **First NAS backups of the three Piwigo volumes** after the
  `nas-daily-backup` run at 01:00 (retain 14): check
  `kubectl -n longhorn-system get backups.longhorn.io` for
  `pvc-39befa94…` (photos), `pvc-9b96ea49…` (config) and `pvc-6cbf25ee…` (database).
- [ ] **Test a restore** of one encrypted NAS backup into a scratch PVC with
  `longhorn-crypto-2replicas`, mount it and read a file. This proves that the
  passphrase and backups together are recoverable, and that the backup is
  unreadable without them. Follow the PVC migration rules in `AGENTS.md` if
  this turns into a migration.
- [ ] **Upload a test photo** and confirm it lands in `/gallery/upload/…`,
  thumbnails in `/config/www/_data/i/…`, and nothing new under the container's
  root filesystem:
  `kubectl -n apps-piwigo exec deploy/piwigo -- find / -xdev -newer /config/POSTSETUP -type f 2>/dev/null | grep -v -E '^/(proc|sys)'`
  (`-xdev` keeps it on the unencrypted root filesystem).

### On every Piwigo chart or image upgrade

- [ ] `helm template` the new chart version with `fleet/apps/piwigo/values.yaml`
  and check that no new PVC, `hostPath` or disk-backed `emptyDir` holds data,
  and that `/tmp` is still `medium: Memory`.
- [ ] The pod log still shows `[require-login] $conf['guest_access'] = false;`,
  and an anonymous `curl https://cycuszki.rancher.tailscale.bnowakowski.pl/`
  still redirects to `identification.php`.
- [ ] `allow_user_registration` is still `false` in `piwigo_config`.
- [ ] Re-check where the image keeps upload temp files (PHP `upload_tmp_dir`,
  nginx `client_body_temp_path`); both are `/tmp` in 16.4.0.

### Later / optional

- [ ] **Cluster stability:** k3s crashed during the Piwigo redeploy (2026-11-03
  00:14, I/O pressure 37%) and several times before. Consider a third etcd
  member (NAS, planned in `ansible/inventory/hosts.ini`) and moving
  `nas-daily-backup` off 01:00. This doesn't affect encryption, but every crash
  stalls the whole cluster.
- [ ] **Authelia / 2FA** in front of Piwigo (not wanted for now; it would break
  Piwigo's API and mobile apps).
- [ ] If a Piwigo mobile app or the API (`ws.php`) is used later, review the
  API keys and sessions it creates.
- [ ] Rotating the disk passphrase is not supported for existing volumes. If
  it ever leaks, create a new Secret and StorageClass and copy the data to new
  volumes.

## Considerations

### Where the data is

| Data | Location | Protection |
| --- | --- | --- |
| Original photos | `/gallery` (PVC `piwigo-gallery-longhorn-crypto`, 10Gi) | LUKS (dm-crypt) |
| Thumbnails, resized copies (`www/_data`), config, plugins | `/config` (PVC `piwigo-config-longhorn-crypto`, 5Gi) | LUKS |
| Database: titles, tags, EXIF incl. GPS, users | MariaDB (PVC `piwigo-mariadb-data-longhorn-crypto`, 2Gi) | LUKS |
| Uploads in transit (PHP temp, sessions, nginx buffers) | `/tmp` | RAM only (tmpfs, 1Gi) |
| Longhorn replicas and snapshots on node disks | `/var/lib/longhorn` | Ciphertext only |
| Longhorn NAS backups (`nas-daily-backup`) | NAS | Ciphertext only; restore needs the passphrase |

Validated 2026-11-03: all three data mounts are `/dev/mapper/pvc-…` (dm-crypt),
and `/tmp` is tmpfs.

### What the encryption protects against, and what it doesn't

It protects data at rest: stolen or discarded node disks, copied Longhorn
replicas, and NAS backups. It does **not** protect against anyone with
cluster-admin rights: they can read the passphrase Secret, `exec` into the pod,
or mount the volume. A volume is unlocked automatically when it attaches, so
Piwigo comes back by itself after a reboot, and the data is readable while the
cluster runs.

### Keys and secrets

- The passphrase is the Secret `longhorn-system/longhorn-crypto`. k3s Secrets
  encryption (enabled 2026-11-02) keeps it encrypted in etcd and its snapshots.
- The API always returns Secrets decrypted, so any tool that backs up
  Kubernetes resources through the API (CloudCasa, Velero, `kubectl get -o
  yaml` dumps) gets the plain passphrase.
- Only Secrets are encrypted at rest. ConfigMaps and Deployment specs are not,
  which is why the chart's initial admin password (in `postStart`) must be
  changed.

### CloudCasa

CloudCasa's agent is Velero-based. Which namespaces it backs up, and how, is
configured in the CloudCasa portal and is not visible from the cluster (it
deletes its job objects after each run). A CloudCasa snapshot of
`apps-mailpile` from 2026-10-29 shows that backups are active.

| CloudCasa mode | What it stores | Photos encrypted with our key? |
| --- | --- | --- |
| Snapshot only | Longhorn snapshot in the cluster | Yes (ciphertext blocks) |
| Snapshot + copy to CloudCasa storage | Mounts the snapshot through dm-crypt and uploads the files | **No.** Plain files, encrypted only with CloudCasa's own keys in its cloud. |
| File-level backup of running pods | Files read inside the pod | **No** |
| Kubernetes resources (every mode) | All objects including Secrets, decrypted | **No.** It includes the passphrase if `longhorn-system` is covered. |

The passphrase plus the volume blocks is everything needed to decrypt the
photos, so CloudCasa must cover neither `apps-piwigo` nor `longhorn-system`'s
Secrets.

### Access

- Only reachable on the private hostnames
  `cycuszki.rancher.tailscale.bnowakowski.pl` (Tailscale) and
  `cycuszki.rancher.localdomain.bnowakowski.pl` (home network). Both are
  HTTPS-only with Let's Encrypt certificates; plain HTTP returns 404.
- `$conf['guest_access'] = false;` is set by a start-up script on every start:
  every anonymous request redirects to the login page, and `ws.php` returns 401.
- Self-registration is off (`allow_user_registration = false`, set once in the
  database).
- No Authelia in front, by choice.

### Host-level leaks

- **Swap:** none on proxmox3 or proxmox2-old (checked 2026-11-03), so RAM
  holding decrypted photos (`/tmp`, page cache) is never written to disk. If
  swap is ever added to a node, it must be encrypted too.
- **Container root filesystem:** on the node's unencrypted disk. Nothing in
  Piwigo writes photo data there (see the upload test in the TODO).
- **Logs:** nginx and PHP write their logs to `/config/log/` (checked
  2026-11-03), which is on the encrypted config volume. They can contain file
  names, album titles and visitor IPs, but no photo content. Only the
  container's start-up output (s6 init) goes to the node's container log.

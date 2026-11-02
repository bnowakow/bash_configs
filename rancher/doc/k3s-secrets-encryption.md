# k3s Secrets encryption at rest

Enabled on 2 November 2026 (23:43–23:47 CET) on both servers, proxmox3 and
proxmox2-old, so that Kubernetes Secrets are stored encrypted in etcd and in
etcd snapshots. It was enabled first because the Longhorn volume-encryption
passphrase (`longhorn-system/longhorn-crypto`) is a Secret.

Current state (`sudo k3s secrets-encrypt status`):

```
Encryption Status: Enabled
Current Rotation Stage: reencrypt_finished
Server Encryption Hashes: All hashes match
Active key: AES-CBC aescbckey-2026-11-02T23:44:48+01:00
```

The key is in `/var/lib/rancher/k3s/server/cred/encryption-config.json` on
each server (identical on both). k3s keeps it in its bootstrap data, which is
encrypted with the server token, so restoring an etcd snapshot needs the token.

## What was done

Procedure for an existing multi-server cluster with embedded etcd
(https://docs.k3s.io/cli/secrets-encrypt; needs k3s ≥ v1.33.10/v1.34.6/v1.35.3):

1. `sudo k3s etcd-snapshot save --name pre-secrets-encryption`
   (snapshot `pre-secrets-encryption-proxmox3-1793659383`).
2. `sudo k3s secrets-encrypt enable` on proxmox3. The status command then
   fails with `secret-encrypt error ID 10249: missing annotation on node`
   until the servers restart; this is expected.
3. Added `secrets-encryption: true` to `/etc/rancher/k3s/config.yaml` on both
   servers and restarted k3s one server at a time (proxmox3, then proxmox2-old),
   waiting for the API and the node to be Ready in between.
4. `sudo k3s secrets-encrypt rotate-keys`: re-encrypted all 369 Secrets in
   about 1 second (stage `reencrypt_finished`).
5. Restarted both servers again, one at a time.
6. Status reported `hash does not match` for a short while after the last
   restart, until proxmox2-old updated its `k3s.io/encryption-config-hash`
   node annotation; then `All hashes match`.

All workloads recovered after each restart. With only two etcd members, every
k3s restart stalls the API until that server is back (about 10–30 seconds
here).

## Rules from now on

- Every server must run with `secrets-encryption: true`. It is in the
  config templates in `ansible/site.yml`; a new server joining the cluster needs
  it too.
- Rotate the key only with `k3s secrets-encrypt rotate-keys` and then restart
  all servers. The k3s docs warn that a wrong procedure can corrupt the
  cluster permanently.
- Only Secrets are encrypted. ConfigMaps and Deployment specs (including env
  values and commands) are not, so keep sensitive values in Secrets.

# Encrypted Longhorn storage

`longhorn-crypto-2replicas` is the same as `longhorn-rwo-2replicas` (two
replicas, Retain, ext4) but every volume is LUKS-encrypted with dm-crypt.
Longhorn replicas, snapshots and NAS backups hold only ciphertext; data is
decrypted only on the node where the volume is attached, inside the pod.

Use it for sensitive data. First user: Piwigo (`apps/piwigo`).

## The passphrase Secret

All volumes of this class use one passphrase, in the Secret
`longhorn-system/longhorn-crypto`. It is **not in git**: create it once by hand,
before the first PVC of this class:

```sh
kubectl -n longhorn-system create secret generic longhorn-crypto \
  --from-literal=CRYPTO_KEY_VALUE="$(openssl rand -base64 48)" \
  --from-literal=CRYPTO_KEY_PROVIDER=secret \
  --from-literal=CRYPTO_KEY_CIPHER=aes-xts-plain64 \
  --from-literal=CRYPTO_KEY_HASH=sha256 \
  --from-literal=CRYPTO_KEY_SIZE=256 \
  --from-literal=CRYPTO_PBKDF=argon2i
```

Then store a copy of the passphrase **outside the cluster** (password
manager). Without it, the volumes and their NAS backups cannot be restored:

```sh
kubectl -n longhorn-system get secret longhorn-crypto \
  -o jsonpath='{.data.CRYPTO_KEY_VALUE}' | base64 -d; echo
```

Never change or delete this Secret while volumes use it: existing volumes
stay locked with the old passphrase.

## Protection and limits

- k3s encrypts Secrets at rest in etcd (enabled 2026-11-02, see
  `doc/k3s-secrets-encryption.md`), so the passphrase is not stored in plain
  text in etcd or its snapshots.
- Protects against stolen disks, copied Longhorn replicas and NAS backups.
- Does not protect against a cluster admin: whoever can read Secrets or exec
  into the pod can read the data. A volume is unlocked automatically when it
  is attached, so apps come back by themselves after a reboot.
- Restoring a backup of an encrypted volume needs a StorageClass that points
  to the same passphrase Secret.

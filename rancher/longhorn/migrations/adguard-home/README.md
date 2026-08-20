# AdGuard Home: local-path to Longhorn migration

Use `migrate.sh` from the repository root. It supports separate phases:

```bash
longhorn/migrations/adguard-home/migrate.sh --phase prepare --yes
longhorn/migrations/adguard-home/migrate.sh --phase copy --yes
longhorn/migrations/adguard-home/migrate.sh --phase cutover --yes
```

Use `--phase all --yes` to run all phases. Use `--dry-run` to validate the
Kubernetes/Helm operations without changing the cluster.

The migration moves both RWO claims in `apps-adguard-home`:

| Purpose | Current claim | New claim | New size |
| --- | --- | --- | --- |
| Configuration | `adguard-home-config` | `adguard-home-config-longhorn` | 100Mi |
| Working data | `adguard-home-data` | `adguard-home-data-longhorn` | 10Gi |

The old claims remain in place for rollback. Do not delete them until the new
Longhorn volumes and backups have been verified.

If larger target PVCs were already created, they must be deleted and recreated
at these sizes; PVC storage requests cannot be reduced in place. Confirm the
failed target volumes contain no copied data before removing their retained
Longhorn volume objects.

The copy phase also changes the old PVCs to `helm.sh/resource-policy: keep` and
their PV reclaim policies to `Retain`, protecting the rollback data during the
Helm cutover.

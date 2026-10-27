# PVC migration requirement

For **any PVC migration in this cluster**, first temporarily scale application
workloads across the cluster to **zero replicas**, including applications not
being migrated. Stopping only the source application is insufficient. This is
a standing user instruction, established on 27 October 2026.

The cluster has repeatedly experienced severe I/O pressure spikes, etcd/API
failures and k3s restarts when PVC migrations ran alongside other applications.
The underlying cause is unknown. Scaling applications down is the required
mitigation; do not describe it as a proven hardware or storage repair.

Save replica counts and schedule states, prevent reconciliation from restarting
applications, and verify the workloads have actually stopped before copying.
Keep services required for Kubernetes, DNS/networking, admission, Longhorn/CSI,
and the migration itself running. After migration validation, restore the saved
application replica counts gradually; preserve applications already at zero.
Log the shutdown, migration and restoration, and update migration documentation.

Follow [the PVC migration maintenance procedure](longhorn/README-5-pvc-migration-maintenance.md).

Document every transfer-cap change, including automatic safety reductions:
record the time, previous/new limits, reason, observed I/O pressure and outcome
in the migration's cap-change record and action log. Verify the live worker
applied the limit; distinguish a requested limit from a confirmed change.

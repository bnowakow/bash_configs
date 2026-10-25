# Mailpile storage — migration pending

Mailpile currently runs from the original **local-path** `mailpile-path1` (20Gi)
and `mailpile-path2` (1Gi), mounted at `/root/.local/share/Mailpile` and
`/root/.gnupg`. It was restored to one available replica after the interrupted
migration; app Fleet definitions still reference those originals.

`longhorn-mailpile-storage` has provisioned 9Gi/256Mi RWO targets with two storage
replicas, but these contain **unverified staging data** and are not mounted by
the live app. Do not treat them as a completed migration. Keep source claims
and original data protected while control-plane/copy failures are investigated.

See the [handoff](../../../longhorn/migrations/mailpile-2026-10-25/HANDOFF.md)
and [current status](../../../longhorn/migrations/mailpile-2026-10-25/RESULTS.md).

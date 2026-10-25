# Mailpile migration status — blocked, not completed

Mailpile remains on its **original local-path claims**. The original service was
restored to one available replica and HTTPS 200 after recurring k3s/API outages
interrupted the copy. The copy Job failed and was removed; no complete manifest,
Mailpile backup/restore validation or target cutover occurred.

The two new Longhorn claims reserve 9.25Gi per host but are **unverified staging**,
not production Mailpile state. Original data remains protected and unchanged by
the copy. Completion counts remain 26 migrated apps/36 production RWO claims.

See the [recovery state, incident evidence and sudo-session handoff](HANDOFF.md).
Do not activate target references or blindly rerun the current copy over partial
staging data. Host storage/etcd stability and the copy failure need diagnosis.
No commit or push was made.

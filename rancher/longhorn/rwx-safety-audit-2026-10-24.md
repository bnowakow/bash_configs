# RWX safety audit — 2026-10-24

Read-only investigation of ddclient, DuckDNS and FlareSolverr, plus clarification
of the completed Homer/Smokeping pilot. No PVCs, replica counts or workloads
were changed. RWX mountability and safe shared application state are different
questions. This audit does not certify active-active shared writers merely
because no SQLite files were found, and did not stress-test concurrent writers.

## Candidate findings

| Application | Observed live state | One instance on RWX | Multiple instances sharing its state | Recommended action |
| --- | --- | --- | --- | --- |
| ddclient | One replica; `/config` contains only `ddclient.conf` (9,682 bytes). Installed startup script reads it and puts its cache at `/run/ddclient-cache/ddclient.cache`, outside the PVC. | No database-specific blocker found for the config file, assuming expected NFS permissions. Not exercised on RWX in this audit. | Sharing immutable configuration is feasible; shared config editing/startup permission changes are not certified safe. Separate caches do not coordinate DNS-provider updates; multiple updaters for the same records can compete or duplicate requests. | Keep one updater. Prefer a Secret-mounted config with local ephemeral cache, after checking the image's config initialization requirements; otherwise a small RWO claim. No useful active-active shared-writer use established. |
| DuckDNS | One replica; `/config` contains only `logrotate.conf` (61 bytes). Fleet sets `LOG_FILE: false`; installed script writes logs to `/dev/null` in that mode. | No persistent DB blocker found with logging disabled. Not exercised on RWX in this audit. | No reason to share persistent data in this configuration. Enabling logging introduces a shared log and rotation-state file with no cross-pod coordination established. Multiple DNS updaters can still compete independently of storage. | Keep one updater. Consider removing the legacy PVC, retaining a writable ephemeral `/config` if startup needs it. Do not introduce RWX just for the unused logging config. |
| FlareSolverr | One replica; `/config` empty. Installed v3.5.2 uses per-process browser sessions; inspected runtime code uses temporary directories for proxy extensions. | No useful persistent state on this PVC to migrate. | Sharing the empty PVC does not share sessions/browser state or create application HA. No shared persistent profile was observed or configured; do not configure a common writable Chromium profile for concurrent processes. | Consider removing the unused claim. Keep browser/temp state isolated per pod. If scaling later, use session-aware routing or stateless requests as appropriate; this is separate from storage. |

All three can remain outside the **confirmed embedded-database** subgroup, but
none is approved here as an early **shared-writer RWX** migration. ddclient and
DuckDNS have single-updater operational constraints. Under the user's rule,
keep shared-writer use unapproved/final until deliberately redesigned; a
persistence-removal audit can happen earlier without representing an RWX migration.
Empty or nearly empty contents are observations, not permission to delete PVCs.
Any removal must preserve secrets and validate startup/update behavior first.

Sources and scope:

- Installed images: `ghcr.io/linuxserver/ddclient:4.0.0`,
  `ghcr.io/linuxserver/duckdns:latest` pinned by digest in the running workload,
  `ghcr.io/flaresolverr/flaresolverr:v3.5.2`. Filename/size and startup-script
  checks were performed inside running pods without printing config secrets.
- [LinuxServer ddclient docs](https://docs.linuxserver.io/images/docker-ddclient/)
  describe `/config` and initialization/read-only-operation requirements. The
  cache path above was verified against the installed service run script.
- [DuckDNS update script](https://raw.githubusercontent.com/linuxserver/docker-duckdns/master/root/app/duck.sh)
  shows the `LOG_FILE` branch, `/config/duck.log` and logrotate state;
  [image docs](https://docs.linuxserver.io/images/docker-duckdns/) explain its configuration.
- [FlareSolverr session storage](https://github.com/FlareSolverr/FlareSolverr/blob/v3.5.2/src/sessions.py)
  uses a process-local session dictionary;
  [browser setup](https://github.com/FlareSolverr/FlareSolverr/blob/v3.5.2/src/utils.py)
  shows temporary proxy-extension creation. An empty shared `/config` does not
  convert those sessions into distributed storage.

## Already migrated pilot: not a multi-writer RWX demonstration

| Application | Actual migrated mode | Shared-writer RWX conclusion |
| --- | --- | --- |
| Homer | RWO, one application pod with editor; original config also read by the sanitising copy job | Static assets can be shared as readers. Concurrent editor writes and configuration updates are not certified safe. Keep controlled writers and explicit co-location. |
| Homer-without-auth | Separate RWO claim, one app/editor pod; config-copy job writes assets from Homer | Same restrictions. The copy job and editor are existing file writers, so preserve their coordination; do not assume RWX makes simultaneous edits conflict-free. |
| Smokeping | RWO config and RRD data; one poller | Do not run independent pollers writing the same RRD files. Treat this as single-writer state under the final-group rule for any future redesign. Its completed RWO migration is not rolled back by a change in ordering. |

The pilot remains deployed as recorded in
[migration results](migrations/pilot-2026-10-24/RESULTS.md). Two Longhorn storage
replicas are copies of one volume, not two application writers. No conversion
to RWX or application replica increase was performed or recommended here.

## Subsequent approved implementation

The user subsequently approved singleton RWO migration for ddclient, DuckDNS
and FlareSolverr. It completed with two replicas per 256Mi volume, keeping each
app at one instance and retaining original claims. See
[second-batch results](migrations/dns-proxy-2026-10-24/RESULTS.md). The findings
above describe the earlier read-only audit; no claim of active-active RWX safety
has been added.

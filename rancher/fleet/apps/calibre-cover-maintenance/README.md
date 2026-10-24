# Daily Calibre cover maintenance

Runs at **03:00 Europe/Warsaw** (`0 3 * * *`). Fleet installs this bundle after
Calibre, Calibre Web, Kavita and the Longhorn storage bundle. A single CronJob performs two sequential steps:

1. Extract missing embedded covers using the same pinned Calibre image and its
   library API. Existing covers are preserved. Only books already in `/library`
   are processed; the job does not import NAS files or download cover art.
2. Refresh missing/outdated thumbnails using Calibre Web's installed thumbnail
   task implementation. The library remains read-only in this step. Thumbnail
   metadata and files are stored on the Calibre Web config PVC, using
   `CACHE_DIRECTORY=/config/thumbnail-cache` in both the Job and web deployment.

When no covers are missing, Calibre stays running. If extraction is needed, the
Job saves Calibre's replica count, scales the desktop to zero, waits for its pods
to exit, writes the missing covers, then restores the replica count in a `finally`
block before refreshing thumbnails. This briefly disconnects desktop sessions;
avoid scheduling imports/conversions during this maintenance window. Calibre Web
stays online. Ordinary errors and termination signals restore the replica count;
a node failure or forced kill during extraction may require manually restoring
Calibre to one replica.

The service account can only get/patch the `calibre` deployment's scale resource
and list pods in `apps-calibre`. It cannot change other deployments or read
Secrets through the API. Concurrent CronJob runs are forbidden, and failed Jobs
are retained for diagnosis without automatic retries.

The image digests match the current app charts. Review both Job images and the
thumbnail bootstrap code when upgrading Calibre or Calibre Web, because the
thumbnail task is an internal application API.

Run immediately:

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-calibre \
  create job --from=cronjob/calibre-cover-maintenance calibre-cover-maintenance-manual
```

Use a fresh Job name for each manual invocation and avoid overlapping a scheduled
run. Inspect both `extract-missing-covers` and `refresh-thumbnails` container logs.

## Initial verification

Extraction was tested against a temporary Calibre library with a synthetic EPUB:
it saved the embedded cover, updated the database flag, and left the existing
cover unchanged on a second pass. The live library initially had covers for all
nine books, so its extraction step did not stop the desktop.

The first full test detected an incorrect Calibre Web split-library setting:
`metadata.db` was read from `/library` but book/cover files were looked up under
`/books`. All nine actual `cover.jpg` files were under `/library`. Split-library
mode was disabled and Calibre Web restarted so it reads both database and files
from `/library`. The refresh script validates both paths to catch regressions.

The corrected live run completed both steps and verified all 27 thumbnail files
(three resolutions for each of nine books) on the shared persistent cache. The
extractor runs as UID/GID 568, matching the Calibre desktop's library ownership.

## Storage placement

The Job uses `calibre-library-longhorn-rwo` (1Gi) and
`calibre-web-config-longhorn-rwo` (256Mi). It shares explicit proxmox2-old
placement with Calibre, Calibre Web and Kavita so shared RWO mounts stay on one
node. Suspend this CronJob before a grouped storage/placement move; update every
consumer together and resume only after the app mounts and rollouts validate.
Original local claims remain rollback copies, not active maintenance mounts.

# Authelia

Installs the [TrueCharts Authelia chart](https://truecharts.org/charts/stable/authelia/)
at https://authelia.rancher.tailscale.bnowakowski.pl and
https://authelia.rancher.localdomain.bnowakowski.pl using Traefik and the existing
`letsencrypt` ClusterIssuer. Chart 32.19.4 requires Kubernetes 1.33 or newer.

Before Fleet starts the pod, create two external Secrets in `apps-authelia`:

- `authelia-secrets`: keys `session-secret`, `jwt-secret`, and
  `storage-encryption-key`, each containing an independently generated random
  secret of at least 64 characters. Retain the encryption key across upgrades
  and restores; changing it makes existing encrypted database records unreadable.
- `authelia-users`: key `users_database.yaml` containing an Authelia
  [file user database](https://www.authelia.com/configuration/first-factor/file/)
  with password hashes, display names, and email addresses. This Secret seeds
  `/config/users_database.yaml` on the PVC only when that file does not exist.
  Later changes to the Secret do not overwrite the persistent user database.

Do not commit these Secrets. Generate password hashes with Authelia's
`authelia crypto hash generate argon2` command.

One replica uses a 1Gi local-path PVC for the writable user database, SQLite,
and notification output. The init container copies the initial user database
atomically with owner-only permissions, using the same image and user as Authelia.
Password changes through Settings → Security are saved to the PVC and survive
pod restarts and Fleet upgrades. On the first rollout of this configuration,
the current Secret supplies the initial password; change it again in Settings
after the rollout if an earlier change was lost.
Sessions are held in memory and reset when the pod restarts. Back up the PVC
and the Secrets together. Password resets remain disabled; authenticated password
changes are supported. Manage subsequent user additions and edits in the PVC's
user database rather than in the seed Secret.

When the Identity Verification dialog says a One-Time Code was sent to your email,
the filesystem notifier writes it to `/config/notification.txt` instead. This is
a verification code, not your password. Retrieve the notification with:

```sh
kubectl -n apps-authelia exec deploy/authelia -- cat /config/notification.txt
```

Keep the dialog open while retrieving and entering the code; closing it or
selecting Cancel invalidates the code. Configure an SMTP notifier for email delivery.

The access policy requires two factors for `*.rancher.tailscale.bnowakowski.pl`
and `*.rancher.localdomain.bnowakowski.pl`, with a separate session cookie for
each domain, and denies other domains. Adding this bundle alone does not protect existing apps:
attach an Authelia forward-auth middleware to selected app ingresses separately.
Never attach that middleware to Authelia's own ingress.

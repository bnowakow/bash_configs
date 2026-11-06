# Radarr reverse-proxy repair — 6 November 2026

Radarr directly returned HTTP 200, but HTTPS requests redirected to an HTTP login URL and then Traefik returned 404. Its TrustedNetworks was empty, so forwarded HTTPS headers were not trusted. Fleet values now set `RADARR__SERVER__TRUSTEDNETWORKS` to the observed pod CIDRs `10.42.0.0/24,10.42.2.0/24` and explicitly keep `RADARR__AUTH__REQUIRED=Enabled`. This list must be reviewed if node pod CIDRs change or Traefik changes to host networking.

Native Fleet apply changed only the Radarr bundle, preserving GitRepo ownership and targeting. Fleet Bundle/current BundleDeployment readiness, workload rollout, unchanged PVC UID/PV binding, both HTTPS login paths (without an HTTP downgrade), and unauthenticated API rejection passed. Report: `radarr-proxy-repair-20261106-155034/report.txt`. No PVC copying, authentication disabling or credential rotation occurred. No commit or push was performed.

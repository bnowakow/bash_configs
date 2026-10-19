# OpenBooks

TrueCharts chart `9.0.0` deploys into `apps-openbooks`, with Europe/Warsaw timezone
and local-path PVCs for books (5Gi at `/books/books`) and logs (1Gi at `/books/logs`).

- https://openbooks.rancher.tailscale.bnowakowski.pl/
- https://openbooks.rancher.localdomain.bnowakowski.pl/

The chart's default IRC server is `irc.irchighway.net:6697`, with TLS enabled.
This app uses its own persistent download storage; the NAS Books mount is only
configured for Calibre Web.

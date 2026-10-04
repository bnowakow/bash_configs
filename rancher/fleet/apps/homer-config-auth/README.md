# Homer authentication

Fleet installs this bundle after `homer` and `authelia` are ready. It requires
Authelia authentication for every path on both
`homer.rancher.tailscale.bnowakowski.pl` and
`homer.rancher.localdomain.bnowakowski.pl`, including `/` and
`/assets/config.yml`. Priority 1000 overrides Homer's chart ingress.
The routes reuse Homer's existing service and TLS Secrets.

Visitors complete Authelia login and two-factor verification before Homer loads.
This allows its background configuration request to succeed without a login
redirect. Authenticated users can still read API keys in the configuration.

The bundle and resource names retain `config` for Fleet upgrade continuity.
This bundle covers the two main Homer HTTPS hostnames. The editor, other Homer
instances, and direct service access need their own access controls.
Authelia's own ingress must remain accessible without this middleware.

After pushing and Fleet reconciliation, check without session cookies:

```sh
curl -I https://homer.rancher.tailscale.bnowakowski.pl/
curl -I https://homer.rancher.localdomain.bnowakowski.pl/
curl -I https://homer.rancher.tailscale.bnowakowski.pl/assets/config.yml
curl -I https://homer.rancher.localdomain.bnowakowski.pl/assets/config.yml
```

Each request should redirect to the corresponding Authelia portal. In a browser,
complete login and confirm Homer loads normally afterward.

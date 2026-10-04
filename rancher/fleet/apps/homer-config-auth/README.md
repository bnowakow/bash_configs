# Homer configuration authentication

Fleet installs this bundle after `homer` and `authelia` are ready. It requires
Authelia authentication for `/assets/config.yml` and `/assets/config.yaml` on
both `homer.rancher.tailscale.bnowakowski.pl` and
`homer.rancher.localdomain.bnowakowski.pl`. Prefix matching also covers suffixes
and trailing slashes. Priority 1000 overrides Homer's public catch-all ingress.
The routes reuse Homer's existing services and TLS Secrets.

The dashboard shell remains public. Its configuration request requires a login;
open `/assets/config.yml` directly, complete Authelia login, then reload Homer.
Background login redirects may fail because of browser CORS restrictions.
Authenticated users can read any API keys in the configuration.

This bundle covers the two main Homer HTTPS hostnames. The editor, alternate
configuration files, other Homer instances, and direct service access need their
own access controls.

After pushing and Fleet reconciliation, check without session cookies:

```sh
curl -I https://homer.rancher.tailscale.bnowakowski.pl/assets/config.yml
curl -I https://homer.rancher.localdomain.bnowakowski.pl/assets/config.yml
curl -I https://homer.rancher.tailscale.bnowakowski.pl/assets/config.yaml
curl -I https://homer.rancher.localdomain.bnowakowski.pl/assets/config.yaml
```

Each request should redirect to the corresponding Authelia portal rather than
serve the file. `/` should remain public. After login, `/assets/config.yml`
should load normally.

# Traefik for Transmission

This host runs transmission-daemon on port 9091, without Proxmox VE or PBS.
Traefik serves https://transmission.localdomain.bnowakowski.pl/transmission/web/
and forwards requests to http://127.0.0.1:9091. HTTP redirects to HTTPS.
Only clients in 10.0.0.0/8 and loopback are allowed; adjust this range if the LAN
uses another subnet. No Tailscale hostname or client range is configured because
Tailscale currently does not work alongside NordVPN with its kill switch here.

## Source and symbolic links

These files reuse the native service design from
/home/sup/code/bash_configs/proxmox/traefik (relative path:
[../../proxmox/traefik](../../proxmox/traefik)). That directory's deployment
claims describe its Proxmox configuration, not this Transmission host.

- traefik.env.template links to ../../proxmox/traefik/traefik.env.template,
  sharing the Cloudflare credential-file setting.
- dynamic/transmission.yml links to transmission.yml.template in the same
  directory, so the documented route is also the active file-provider input.
- traefik.yml.template and traefik.service are adapted copies because their
  file paths and service description differ from the Proxmox versions.
- The dynamic route derives from the PBS template, with one Transmission
  hostname, an HTTP upstream, and no backend TLS transport.

Keep the relative directory layout intact so the shared symlink resolves.
The ignored traefik.yml uses the ACME contact email from the existing Proxmox
configuration. Credentials and certificates remain outside the repository.

## Deployment

Traefik v3.7.13 was installed from the official release after SHA256
verification, and traefik.service is enabled and running. python3-yaml was
installed and all YAML inputs and route references were verified. Use one native Traefik service for ports 80 and 443. The service here
selects /home/sup/code/bash_configs/transmission/traefik/traefik.yml.
The shared installation guide is
[PROXMOX_VE_TRAEFIK_INSTALL.md](../../proxmox/traefik/PROXMOX_VE_TRAEFIK_INSTALL.md);
reuse its native installation and Cloudflare credential instructions, using this
directory's service and configuration instead of the Proxmox routes.

Before deployment, confirm ports 80/443 are free or already owned by the service
being replaced. Point the hostname's DNS record to this host's LAN address.
Cloudflare must host the authoritative DNS zone for DNS-01 certificate issuance;
no public inbound port is required for the challenge. NordVPN's kill switch must
permit LAN access and Traefik's outbound DNS, Cloudflare API, and ACME requests.
The configuration does not change VPN or firewall settings.

Keep Transmission RPC authentication enabled. With passHostHeader enabled,
Transmission's RPC host allow-list must permit
transmission.localdomain.bnowakowski.pl. Its RPC IP allow-list must permit the
loopback proxy connection. Prefer a loopback RPC bind address if remote direct
access to port 9091 is unnecessary. Transmission setting names vary by version;
consult its installed version's configuration documentation. Stop the daemon
before directly editing settings so it does not overwrite your changes.

After deploying, check systemctl is-active traefik and visit
https://transmission.localdomain.bnowakowski.pl/transmission/web/ from the LAN.
Confirm HTTPS certificate validity, Transmission login, and the ability to view
and control torrents through its RPC endpoint.

The Cloudflare token was copied from the existing Proxmox source file into
/etc/traefik/credentials/cloudflare-dns-api-token with mode 0600. The service
reads only that protected copy. Transmission settings, its listener on port
9091, and VPN/firewall configuration remain unchanged.

DNS challenge propagation uses disableANSChecks: true and requireAllRNS: true
because direct authoritative DNS queries returned REFUSED on this host. Both
configured recursive resolvers must observe the TXT record; Let’s Encrypt
still validates the DNS challenge independently. See
https://doc.traefik.io/traefik/v3.3/https/acme/ for these options.

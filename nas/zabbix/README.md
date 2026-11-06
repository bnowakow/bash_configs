# NAS Zabbix agent

The NAS runs `zabbix-agent2` with `/etc/zabbix/zabbix_agent2.conf`. The
repository copy is `~/code/homelab/zabbix/zabbix_agent2.conf`. Custom item keys
are defined in the repository's `*/zabbix/zabbix*.conf` files, including
`nas/zabbix/zabbix-nas.conf`. The agent loads installed copies from
`/etc/zabbix/zabbix_agent2.d/*.conf`.

## Repair configuration drift

On 2026-11-05, the Zabbix server pod's request to NAS `10.0.0.20:10050` failed
with `Connection reset by peer`. The installed agent config was the 2025 stock
file with `Server=127.0.0.1`, so it rejected the server pod. After the server
allowlist was restored, the item
`bnowakow.nas.truenas.is-truenas-up-to-date` reported `Unknown metric` because
there were no top-level UserParameter files in
`/etc/zabbix/zabbix_agent2.d/`.

On the NAS, install both the agent config and the UserParameter files using the
existing update script. Run the command as one line:

```bash
sudo bash ~/code/homelab/zabbix/update-zabbix-metadata.sh
```

This copies the repository's agent config and `zabbix*.conf` files into
`/etc/zabbix`, then restarts `zabbix-agent2`. Validate the installed config and
the service:

```bash
sudo zabbix_agent2 -T
systemctl is-active zabbix-agent2
grep '^Server=' /etc/zabbix/zabbix_agent2.conf
ls /etc/zabbix/zabbix_agent2.d/zabbix-nas.conf
```

From proxmox3, test the same path used by the Zabbix server pod:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n apps-zabbix exec deploy/zabbix-zabbix-server -c zabbix-server -- zabbix_get -s 10.0.0.20 -p 10050 -k agent.ping
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n apps-zabbix exec deploy/zabbix-zabbix-server -c zabbix-server -- zabbix_get -s 10.0.0.20 -p 10050 -k bnowakow.nas.truenas.is-truenas-up-to-date
```

On 2026-11-05, these returned `1` and `true`, respectively. The NAS
`ansible/zabbix-agent2_playbook.yml` also installs the config and metadata files
for managed redeployments.

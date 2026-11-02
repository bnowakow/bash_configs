# Incident 2026-11-02: Services between pods on the same node stopped working

## Summary

At 14:37 CET on 2 November 2026 the unattended Proxmox upgrade (`pve-manager`
9.2.24 → 9.2.25, `pve-cluster`, `qemu-server`, …) ran on **both** k3s nodes,
proxmox3 and proxmox2-old. It restarted `systemd-sysctl`, which re-applied
Proxmox's `/usr/lib/sysctl.d/10-pve.conf`:

```
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
```

k3s sets `net.bridge.bridge-nf-call-iptables = 1` only when k3s starts, so the
value silently went back to 0 while k3s kept running.

With it at 0, traffic between two pods on the **same node** crosses the `cni0`
bridge without passing through iptables. A pod connecting to a ClusterIP
Service gets DNATed to the backend pod, but the backend's reply is bridged
straight back without the reverse NAT. The client sees a reply from the pod IP
instead of the Service IP and drops it, so the connection hangs (conntrack
shows `SYN_SENT [UNREPLIED]`). Traffic to backends on the other node is routed
through flannel, still passes through iptables, and kept working.

No reboot was needed and none was done. The fix took effect immediately.

## Symptoms

- BookStack: `SQLSTATE[HY000] [2002] Operation timed out` connecting to
  `bookstack-mariadb:3306`. The pod failed its startup and liveness probes and
  restarted 19 times. Both pods were on proxmox3.
- Longhorn CSI mounts failed with `failed to get volume … for publishing
  volume: Get "http://longhorn-backend…"`. The homer config-copy CronJob pod
  was stuck in `ContainerCreating` for 94 minutes.
- Any other client and Service backend on the same node: same failure.
  Services whose backend was on the other node worked, e.g. Jenkins and
  CoreDNS, both on proxmox2-old, which made the outage look partial and
  random.

## Diagnosis (how to recognise it again)

1. The backend pod IP works, the Service IP does not, from the same node:

   ```sh
   kubectl -n apps-bookstack run nettest --rm -i --restart=Never --image=busybox:1.37 \
     --overrides='{"spec":{"nodeName":"proxmox3"}}' --command -- \
     sh -c 'nc -z -w5 bookstack-mariadb 3306 && echo svc OK; nc -z -w5 <podIP> 3306 && echo pod OK'
   ```

2. The kube-proxy iptables rules and endpoints are correct, and the
   kube-router policy chain shows no REJECTs. Conntrack shows
   `SYN_SENT ... [UNREPLIED]` entries to the Service IP.
3. The setting is 0:

   ```sh
   cat /proc/sys/net/bridge/bridge-nf-call-iptables   # must be 1
   ```

   `br_netfilter` is built into the PVE kernel (`modinfo -n br_netfilter` prints
   `(builtin)`), so `lsmod` does not list it. That does not mean it is
   missing.
4. Cause: `grep -r bridge-nf-call /usr/lib/sysctl.d /etc/sysctl.d` finds
   `10-pve.conf`, and `/var/log/apt/history.log` shows the upgrade at the time
   the failures started.

## Fix

Applied on both nodes at about 15:00 CET:

```sh
printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' \
  | sudo tee /etc/sysctl.d/99-kubernetes.conf
sudo /usr/lib/systemd/systemd-sysctl     # re-applies all sysctl.d files
cat /proc/sys/net/bridge/bridge-nf-call-iptables   # → 1
```

The file is named `99-` so it is applied after Proxmox's `10-pve.conf` and wins
whenever `systemd-sysctl` runs again: on boot, on a package upgrade, or after
`sysctl --system`. Re-running the full `systemd-sysctl` confirmed the value
stays at 1. The same setting is now in `ansible/site.yml` (task "Keep bridged
pod traffic going through iptables"), so a rebuilt host gets it too.

Setting it to 1 also sends bridged Proxmox VM/LXC traffic through iptables,
which is how both hosts had already been running since k3s first started.

## Verification

- `bookstack-mariadb:3306` reachable through the Service from proxmox3.
- BookStack rollout completed, the pod is 1/1 Ready, and
  `https://bookstack.rancher.tailscale.bnowakowski.pl/login` returns 200.
- The stuck homer CronJob pod mounted its Longhorn volumes and completed.
- No other pods were not ready afterwards, apart from older unrelated ones: a
  Pending traefik rollout pod blocked by a hostPort conflict, and two stale
  `Unknown` pods.

## Related, not caused by this

The same day at 01:18, k3s on proxmox3 exited after "leaderelection lost". etcd
`slow fdatasync` and API timeouts happened while the Longhorn
`nas-daily-backup` RecurringJob (cron `0 1 * * *`) was running. It also
crashed on 30 and 31 October. That is the separate I/O-pressure problem, see
[longhorn/io-pressure-incident-2026-10-25.md](../longhorn/io-pressure-incident-2026-10-25.md).

#!/usr/bin/env bash
# Run after a freeze/reboot to preserve evidence from the boot in which it failed.
set -u -o pipefail

if (( EUID != 0 )); then
    echo 'Run this script as root.' >&2
    exit 1
fi

node=$(hostname -s)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output=${1:-"/var/log/proxmox-migration-monitor/${node}-postmortem-${stamp}"}
if [[ -e $output ]]; then
    echo "Refusing to use existing path: $output" >&2
    exit 1
fi
mkdir -p -m 0700 "$output"

capture() {
    local label=$1
    shift
    # A broken storage path can make pvesm/zpool block. Preserve the rest of
    # the evidence even if one command does not return.
    timeout 20s "$@" > "$output/$label.txt" 2>&1 || true
}
capture uname uname -a
capture uptime uptime
capture last last -x
capture pveversion pveversion -v
capture pvesm-status pvesm status
capture zpool-status zpool status -v
capture ip-link ip -s -s link
capture ip-address ip -br address
capture ip-route ip route show table all
capture ip-neighbours ip -s neigh show
capture sockets ss -tin
for nic in /sys/class/net/*; do
    [[ -e $nic/device ]] || continue
    interface=${nic##*/}
    capture "$interface-driver" ethtool -i "$interface"
    capture "$interface-offloads" ethtool -k "$interface"
    capture "$interface-stats" ethtool -S "$interface"
    capture "$interface-eee" ethtool --show-eee "$interface"
    capture "$interface-pause" ethtool -a "$interface"
done

journalctl -b -1 -o short-precise > "$output/journal-previous-boot.log" 2>&1 || true
journalctl -b 0 -o short-precise > "$output/journal-current-boot.log" 2>&1 || true
dmesg -T > "$output/dmesg-current-boot.log" 2>&1 || true

echo "Postmortem data saved in: $output"

#!/usr/bin/env bash
# Passive NIC diagnostics; optional ICMP probes. Never changes NIC settings.
set -u -o pipefail
usage() {
    cat <<'HELP'
Usage: monitor-proxmox-nic.sh -n INTERFACE [-i SECONDS] [-p IP]... [-o DIRECTORY]
  -n INTERFACE  Physical NIC to inspect (required; proxmox5 uses nic0)
  -i SECONDS    Pause between samples (default: 5; commands add elapsed time)
  -p IP         Optional numeric IPv4/IPv6 probe target; repeat for multiple peers
  -o DIRECTORY  New local log directory (must not exist)
Stop with Ctrl-C. No offload changes, link resets, or active stress tests.
HELP
}
interface=''
interval=5
output=''
peers=()
while getopts ':n:i:p:o:h' option; do
    case "$option" in
        n) interface=$OPTARG ;;
        i) interval=$OPTARG ;;
        p) peers+=("$OPTARG") ;;
        o) output=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift "$((OPTIND - 1))"
if (( $# )) || ! [[ $interval =~ ^[1-9][0-9]*$ ]] || [[ -z $interface || $interface == */* || ! -d /sys/class/net/$interface ]]; then
    echo 'Specify an existing interface and a positive integer interval; no positional arguments.' >&2
    exit 2
fi
for peer in "${peers[@]}"; do
    if ! [[ $peer =~ ^[0-9a-fA-F:.]+$ ]]; then
        echo 'Probe targets must be numeric IP addresses (no DNS dependency).' >&2
        exit 2
    fi
done
if (( EUID != 0 )); then
    echo 'Run as root to capture the complete kernel journal.' >&2
    exit 1
fi
for command in ethtool ip journalctl timeout; do
    command -v "$command" >/dev/null || { echo "Required command unavailable: $command" >&2; exit 1; }
done
if (( ${#peers[@]} )); then
    command -v ping >/dev/null || { echo 'ping is required for probes.' >&2; exit 1; }
fi
node=$(hostname -s)
output=${output:-"/var/log/proxmox-migration-monitor/${node}-nic-$(date -u +%Y%m%dT%H%M%SZ)"}
if [[ -e $output ]]; then
    echo "Refusing to use existing path: $output" >&2
    exit 1
fi
umask 077
mkdir -p -m 0700 "$output" || exit 1
journal_pid=''
link_pid=''
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    [[ -z $journal_pid ]] || kill "$journal_pid" 2>/dev/null || true
    [[ -z $link_pid ]] || kill "$link_pid" 2>/dev/null || true
    printf '%s stopped status=%s\n' "$(date -Ins)" "$status" >> "$output/monitor-events.log"
    echo "Logs saved in: $output"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
capture() {
    local status
    printf '\n%s command:' "$(date -Ins)"
    printf ' %q' "$@"
    printf '\n'
    timeout -k 2s 5s "$@"
    status=$?
    printf '%s exit_status=%s\n' "$(date -Ins)" "$status"
    return 0
}
{
    date -Ins
    hostname
    uname -a
    printf 'interface=%s interval=%s\n' "$interface" "$interval"
    printf 'probe targets: %s\n' "${peers[*]:-none}"
    cat /proc/sys/kernel/random/boot_id
    capture ip -br address
    capture ip route show
    capture ip -6 route show
    capture ethtool -i "$interface"
    capture ethtool -k "$interface"
    capture ethtool --show-eee "$interface"
    capture ethtool -a "$interface"
} > "$output/nic-baseline.log" 2>&1
journalctl -b -k -f -o short-precise > "$output/kernel-follow.log" 2>&1 &
journal_pid=$!
ip -ts monitor link address route neigh > "$output/network-events.log" 2>&1 &
link_pid=$!
echo "Monitoring $node interface $interface; Ctrl-C to stop."
echo "Log directory: $output"
iteration=0
while :; do
    {
        printf '\n%s heartbeat\n' "$(date -Ins)"
        cat /proc/uptime /proc/loadavg
        for pressure in /proc/pressure/{cpu,io,memory}; do
            [[ -r $pressure ]] || continue
            printf '%s\n' "$pressure"
            cat "$pressure"
        done
        kill -0 "$journal_pid" 2>/dev/null || echo 'WARNING: kernel journal follower has exited'
    } >> "$output/heartbeat.log" 2>&1
    {
        capture ip -s -s link show dev "$interface"
        capture ethtool "$interface"
        capture ethtool -S "$interface"
        for counter in carrier operstate carrier_changes carrier_up_count carrier_down_count; do
            [[ -r /sys/class/net/$interface/$counter ]] || continue
            printf '%s=' "$counter"
            cat "/sys/class/net/$interface/$counter"
        done
    } >> "$output/nic-counters.log" 2>&1
    if (( iteration % 12 == 0 )); then
        {
            capture ethtool -k "$interface"
            capture ethtool --show-eee "$interface"
            capture ethtool -a "$interface"
        } >> "$output/nic-settings.log" 2>&1
    fi
    if (( iteration % 12 == 0 )); then
        {
            capture ip route show table all
            capture ip -6 route show table all
            capture ip -s neigh show
            capture bridge -s link show
            capture tc -s qdisc show dev "$interface"
            capture ss -s
            capture ss -tin state established
            printf '%s interrupt and softirq counters\n' "$(date -Ins)"
            cat /proc/interrupts /proc/softirqs /proc/net/softnet_stat
            for counter in /sys/class/net/"$interface"/device/aer_* /sys/class/net/"$interface"/device/power/{control,runtime_status}; do
                [[ -r $counter ]] || continue
                printf '%s\n' "$counter"
                cat "$counter"
            done
            kill -0 "$link_pid" 2>/dev/null || echo 'WARNING: network event follower has exited'
        } >> "$output/network-state.log" 2>&1
    fi
    for peer in "${peers[@]}"; do
        # Use host routing: records host reachability, not a forced physical-port path.
        capture ping -n -c 1 -W 1 "$peer" >> "$output/probes.log" 2>&1
    done
    iteration=$((iteration + 1))
    sleep "$interval"
done

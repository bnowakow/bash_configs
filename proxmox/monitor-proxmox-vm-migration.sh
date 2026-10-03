#!/usr/bin/env bash
# Capture evidence during a Proxmox VM migration without placing meaningful load
# on the host. Run as root before starting the migration; stop with Ctrl-C after.
set -u -o pipefail

usage() {
    cat <<'EOF'
Usage: monitor-proxmox-vm-migration.sh [-v VMID] [-i SECONDS] [-o DIRECTORY]

  -v VMID       VM being migrated (optional, used to focus process snapshots)
  -i SECONDS    Sampling interval; default: 2
  -o DIRECTORY  Log directory; default: /var/log/proxmox-migration-monitor/<timestamp>
EOF
}

vmid=''
interval=2
output=''
while getopts ':v:i:o:h' option; do
    case "$option" in
        v) vmid=$OPTARG ;;
        i) interval=$OPTARG ;;
        o) output=$OPTARG ;;
        h) usage; exit 0 ;;
        :) echo "Missing value for -$OPTARG" >&2; usage >&2; exit 2 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
    esac
done

if ! [[ $interval =~ ^[1-9][0-9]*$ ]]; then
    echo 'Interval must be a positive whole number.' >&2
    exit 2
fi
if (( EUID != 0 )); then
    echo 'Run this script as root so it can collect the complete kernel journal and Proxmox state.' >&2
    exit 1
fi

started_utc=$(date -u +%Y%m%dT%H%M%SZ)
node=$(hostname -s)
output=${output:-"/var/log/proxmox-migration-monitor/${node}-${started_utc}"}
if [[ -e $output ]]; then
    echo "Refusing to use existing path: $output" >&2
    exit 1
fi
mkdir -p -m 0700 "$output"

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    printf '%s monitor stopping (status %s)\n' "$(date -Ins)" "$status" >> "$output/monitor-events.log"
    for pid in "${children[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    # Do not wait here: a storage command stuck in uninterruptible I/O must not
    # prevent this shell from returning control to the operator.
    printf '%s\n' "$(date -Ins)" > "$output/stopped-at.txt"
    echo "Logs saved in: $output"
    exit "$status"
}
children=()
trap cleanup EXIT INT TERM

{
    echo "started_at=$(date -Ins)"
    echo "hostname=$(hostname -f 2>&1 || hostname)"
    echo "vmid=${vmid:-not-specified}"
    echo "interval_seconds=$interval"
    echo
    pveversion -v 2>&1 || true
    echo
    uname -a
    echo
    uptime
    echo
    findmnt -rno TARGET,SOURCE,FSTYPE,OPTIONS 2>&1 || true
    echo
    ip -br address 2>&1 || true
    echo
    ip route 2>&1 || true
    echo
    echo 'Kernel block-device timeout settings (seconds):'
    for timeout_file in /sys/block/*/device/timeout; do
        [[ -r $timeout_file ]] || continue
        printf '%s=' "${timeout_file%/device/timeout}"
        cat "$timeout_file"
    done
} > "$output/host-baseline.txt"

# journalctl follows new kernel messages with their original, precise timestamps.
journalctl -k -f -o short-precise > "$output/kernel-follow.log" 2>&1 &
children+=("$!")

# Keep a separate Proxmox service log: migration errors can be absent from dmesg.
journalctl -f -o short-precise -u pvedaemon -u pveproxy -u pvestatd -u pve-ha-lrm -u pve-ha-crm \
    > "$output/proxmox-services-follow.log" 2>&1 &
children+=("$!")

sample_system() {
    echo 'timestamp,load1,load5,load15,mem_available_kb,dirty_kb,writeback_kb,io_some_avg10,io_full_avg10,cpu_some_avg10,memory_some_avg10'
    while :; do
        local timestamp load1 load5 load15 memory dirty writeback io_some io_full cpu_some memory_some
        timestamp=$(date -Ins)
        read -r load1 load5 load15 _ < /proc/loadavg
        memory=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
        dirty=$(awk '/^Dirty:/ {print $2}' /proc/meminfo)
        writeback=$(awk '/^Writeback:/ {print $2}' /proc/meminfo)
        io_some=$(awk '$1 == "some" {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i}}' /proc/pressure/io 2>/dev/null || echo '')
        io_full=$(awk '$1 == "full" {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i}}' /proc/pressure/io 2>/dev/null || echo '')
        cpu_some=$(awk '$1 == "some" {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i}}' /proc/pressure/cpu 2>/dev/null || echo '')
        memory_some=$(awk '$1 == "some" {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i}}' /proc/pressure/memory 2>/dev/null || echo '')
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$timestamp" "$load1" "$load5" "$load15" "$memory" "$dirty" "$writeback" "$io_some" "$io_full" "$cpu_some" "$memory_some"
        sleep "$interval"
    done
}

sample_processes() {
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        ps -eo pid,ppid,stat,psr,pcpu,pmem,etimes,wchan:32,args --sort=-pcpu | head -n 80
        if [[ -n $vmid ]]; then
            echo "--- processes mentioning VMID $vmid ---"
            ps -eo pid,ppid,stat,psr,pcpu,pmem,etimes,wchan:32,args | grep -F -- "$vmid" | grep -v '[g]rep' || true
        fi
        echo '--- D-state processes (blocked, commonly storage related) ---'
        ps -eo pid,ppid,stat,wchan:48,args | awk '$3 ~ /^D/ {print}' || true
        sleep "$interval"
    done
}

sample_network() {
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        ip -s link
        echo '--- migration-related TCP sockets ---'
        ss -tinp '( sport = :22 or dport = :22 or sport = :60000 or dport = :60000 )' 2>&1 || true
        sleep "$((interval * 5))"
    done
}

# These procfs reads are cheap snapshots of ZFS cache and transaction-group
# state. They deliberately do not invoke zpool status or any pool-wide scan.
sample_zfs_kstats() {
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        if [[ -r /proc/spl/kstat/zfs/arcstats ]]; then
            echo '--- ARC statistics ---'
            awk 'NR > 2 {print}' /proc/spl/kstat/zfs/arcstats
        fi
        for txgs_file in /proc/spl/kstat/zfs/*/txgs; do
            [[ -r $txgs_file ]] || continue
            echo "--- transaction groups: ${txgs_file%/txgs} ---"
            awk 'NR > 2 {print}' "$txgs_file"
        done
        sleep "$interval"
    done
}

# Raw counters make it possible to calculate device busy time and I/O deltas
# even if iostat terminates or its output is incomplete after a hard lockup.
sample_diskstats() {
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        cat /proc/diskstats
        sleep "$interval"
    done
}

# NVMe admin commands can themselves stop responding during a controller fault.
# Time-limit each sample and retain the timeout as evidence instead of blocking
# the rest of the monitor. Run these infrequently to avoid diagnostic load.
sample_nvme_health() {
    local controller
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        for controller in /dev/nvme[0-9]; do
            [[ -b $controller ]] || continue
            echo "--- $controller SMART / health ---"
            timeout 8s nvme smart-log "$controller" 2>&1 || true
            echo "--- $controller controller error log ---"
            timeout 8s nvme error-log -e 64 "$controller" 2>&1 || true
        done
        sleep "$((interval * 30))"
    done
}

# Kernel messages are saved separately. These cheap sysfs reads also expose
# correctable PCIe AER errors that may not result in a message.
sample_pcie_aer() {
    local aer_file
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        for aer_file in /sys/bus/pci/devices/*/aer_*; do
            [[ -r $aer_file ]] || continue
            printf '%s=' "$aer_file"
            cat "$aer_file"
        done
        sleep "$((interval * 30))"
    done
}

sample_thermal() {
    while :; do
        printf '\n===== %s =====\n' "$(date -Ins)"
        sensors 2>&1 || true
        sleep "$((interval * 30))"
    done
}

sample_system > "$output/system.csv" &
children+=("$!")
sample_processes > "$output/processes.log" 2>&1 &
children+=("$!")
sample_network > "$output/network.log" 2>&1 &
children+=("$!")
sample_diskstats > "$output/diskstats.log" 2>&1 &
children+=("$!")
sample_pcie_aer > "$output/pcie-aer-counters.log" 2>&1 &
children+=("$!")

if command -v iostat >/dev/null 2>&1; then
    iostat -dxm -t "$interval" > "$output/iostat.log" 2>&1 &
    children+=("$!")
else
    echo 'iostat not installed; install the sysstat package for per-device latency and queue-depth data.' > "$output/iostat-unavailable.txt"
fi
if command -v pidstat >/dev/null 2>&1; then
    pidstat -d -h -p ALL "$interval" > "$output/pidstat-disk.log" 2>&1 &
    children+=("$!")
fi
if command -v nvme >/dev/null 2>&1; then
    sample_nvme_health > "$output/nvme-health.log" 2>&1 &
    children+=("$!")
fi
if command -v sensors >/dev/null 2>&1; then
    sample_thermal > "$output/thermal.log" 2>&1 &
    children+=("$!")
fi
if command -v zpool >/dev/null 2>&1; then
    zpool iostat -vy "$interval" > "$output/zpool-iostat.log" 2>&1 &
    children+=("$!")
    zpool events -f -v > "$output/zpool-events.log" 2>&1 &
    children+=("$!")
    sample_zfs_kstats > "$output/zfs-kstats.log" 2>&1 &
    children+=("$!")
fi
if command -v ceph >/dev/null 2>&1; then
    (
        while :; do
            printf '\n===== %s =====\n' "$(date -Ins)"
            ceph -s
            ceph osd perf 2>&1 || true
            sleep "$((interval * 5))"
        done
    ) > "$output/ceph.log" 2>&1 &
    children+=("$!")
fi

echo "Monitoring node $node${vmid:+ for VMID $vmid}. Start the migration now. Press Ctrl-C after it finishes."
echo "Log directory: $output"
wait

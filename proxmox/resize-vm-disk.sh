#!/usr/bin/env bash
set -euo pipefail

# Grow a VM's sole data disk and a filesystem inside it. Never shrink.
# Run as your normal user so SSH uses that user's keys. Host commands use sudo;
# guest resize operations use an SSH terminal for sudo password prompts.
usage() {
    cat <<'EOF'
Usage: resize-vm-disk.sh --vmid ID --size TOTAL_GiB [--ssh [USER@]HOST] [--mount /] [--apply]
       resize-vm-disk.sh --vmid ID [--status] [--ssh [USER@]HOST] [--mount /]

Examples (40 means a TOTAL size of 40 GiB, not an additional 40 GiB):
  ./resize-vm-disk.sh --vmid 601 --status
  ./resize-vm-disk.sh --vmid 601 --ssh sup@GUEST_IP --size 40
  ./resize-vm-disk.sh --vmid 601 --ssh sup@GUEST_IP --size 40 --apply

Run without sudo in front of the script to use your own SSH keys. Host qm
commands use sudo internally (may prompt locally). Guest resize/preflight uses
sudo over an SSH terminal and may prompt for your guest password. --status needs no guest sudo or resize
tools and reports virtual disk capacity plus filesystem size/used/free/use%.
SSH defaults to the current user's name and Proxmox's configured VM name,
with .localdomain.bnowakowski.pl appended to short names. Already qualified
VM names are used as configured.
Override the destination with --ssh HOST or --ssh USER@HOST.

Without --size: show status and resize instructions. With --size: preflight
unless --apply is also supplied. Preflight may install cloud-guest-utils if
growpart is missing. Take a VM backup before --apply.
Supports mounted ext4/XFS on a whole disk, final partition, or a linear LVM
volume in a single-PV VG. LVM growth assigns all free space in that VG to the
selected volume. Encrypted, RAID, thin LVM and multi-disk layouts are refused.
Guest packages: cloud-guest-utils (growpart) for partitions is automatically
installed with apt-get if missing (Debian/Ubuntu). Other prerequisites:
e2fsprogs for ext4, xfsprogs for XFS, lvm2 for LVM. The script does not reboot.
If guest growth fails after host growth, fix the reported issue and rerun with
the SAME total size. The larger virtual disk is retained.
EOF
}
die() { echo "Error: $*" >&2; exit 1; }
vmid= target= size= mountpoint=/ apply=0 status=0
while (($#)); do
    case "$1" in
        --vmid|--ssh|--size|--mount)
            (($# >= 2)) || die "Missing value for $1"
            case "$1" in
                --vmid) vmid=$2;; --ssh) target=$2;; --size) size=$2;; --mount) mountpoint=$2;;
            esac
            shift 2;;
        --apply) apply=1; shift;;
        --status) status=1; shift;;
        -h|--help) usage; exit 0;;
        *) die "Unknown option: $1";;
    esac
done
[[ $vmid =~ ^[1-9][0-9]{2,8}$ ]] || die "Supply --vmid (100–999999999)"
if [[ -n $target ]]; then
    [[ $target =~ ^[a-zA-Z0-9_.@:-]+$ && $target != -* ]] || die "Invalid --ssh destination"
fi
if [[ -z $size ]] && ((!status)); then
    ((apply == 0)) || die "--apply requires --size TOTAL_GiB"
    status=1
fi
if ((status)); then
    [[ -z $size && $apply == 0 ]] || die "--status cannot be combined with --size or --apply"
else
    [[ $size =~ ^[1-9][0-9]{0,5}$ ]] || die "--size must be an integer total size in GiB"
fi
[[ $mountpoint =~ ^/[a-zA-Z0-9_./-]*$ ]] || die "Unsupported mount path"
command -v ssh >/dev/null || die "Missing ssh"
if ((EUID != 0)); then
    command -v sudo >/dev/null || die "Missing sudo"
    sudo -v
fi
qm() {
    if ((EUID == 0)); then command qm "$@"; else sudo -- qm "$@"; fi
}
[[ $(qm status "$vmid") == 'status: running' ]] || die "VM $vmid must be running"
config=$(qm config "$vmid")
current=$(qm config "$vmid" --current 1)
[[ $config == "$current" ]] || die "Resolve pending VM configuration changes first"
disk_count=0
disk_config= mac= vm_name=
while IFS= read -r line; do
    if [[ $line =~ ^(scsi|sata|virtio|ide)[0-9]+: && $line != *media=cdrom* ]]; then
        ((disk_count+=1))
        [[ $line == 'scsi0: '* ]] && disk_config=${line#scsi0: }
    fi
    if [[ $line =~ ^net0:.*=([[:xdigit:]:]{17}), ]]; then mac=${BASH_REMATCH[1],,}; fi
    [[ $line != 'name: '* ]] || vm_name=${line#name: }
done <<< "$current"
(( disk_count == 1 )) && [[ -n $disk_config && -n $mac ]] || die "Expected sole disk scsi0 and net0 MAC"
if [[ -z $target ]]; then
    [[ $vm_name =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die "Cannot determine VM hostname; supply --ssh HOST"
    target=$vm_name
    [[ $target == *.* ]] || target+=.localdomain.bnowakowski.pl
    echo "Using Proxmox VM name as SSH hostname: $target (override with --ssh HOST)"
fi
[[ $target == *@* ]] || target="$(id -un)@$target"
echo "SSH destination: $target"
[[ $disk_config =~ ,size=([0-9]+)G(,|$) ]] || die "Expected an integer GiB disk size"
old_size=${BASH_REMATCH[1]}
if ((status)); then
    echo "VM $vmid: virtual disk scsi0 capacity ${old_size} GiB"
    echo "To preview a resize, add --size TOTAL_GiB (e.g. --size 40 means 40 GiB total)."
    echo "To perform the resize after taking a backup, add --size TOTAL_GiB --apply."
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" \
        "bash -s -- '$mountpoint' '$mac'" <<'STATUS'
set -euo pipefail
mountpoint=$1 mac=$2
matched=0
for address in /sys/class/net/*/address; do
    [[ $(cat "$address") == "$mac" ]] && matched=1
done
((matched)) || { echo "SSH guest MAC does not match the selected VM's net0" >&2; exit 1; }
findmnt --mountpoint "$mountpoint" -o SOURCE,FSTYPE,TARGET
echo "Guest filesystem capacity and usage:"
df -h --output=source,size,used,avail,pcent,target "$mountpoint"
echo "Guest block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
STATUS
    exit 0
fi
(( size >= old_size )) || die "Shrinking is forbidden (current size ${old_size} GiB)"
expected_bytes=$((size * 1024 * 1024 * 1024))

# Send the same inspection program for preflight and apply; no guest files kept.
guest() {
    local guest_program encoded
    guest_program=$(cat <<'GUEST'
set -euo pipefail
mode=$1 mountpoint=$2 mac=$3 expected_bytes=$4
die() { echo "Guest error: $*" >&2; exit 1; }
[[ $EUID == 0 ]] || die "Root required"
matched=0
for address in /sys/class/net/*/address; do
    [[ $(cat "$address") == "$mac" ]] && matched=1
done
((matched)) || die "SSH guest MAC does not match the selected VM's net0"
for cmd in findmnt lsblk readlink blockdev df cat awk xargs; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
source=$(findmnt -nro SOURCE --mountpoint "$mountpoint") || die "Path is not a mountpoint"
fstype=$(findmnt -nro FSTYPE --mountpoint "$mountpoint")
options=$(findmnt -nro OPTIONS --mountpoint "$mountpoint")
[[ ,$options, == *,rw,* ]] || die "Filesystem is not writable"
case $fstype in
    ext4) grow_fs=resize2fs;;
    xfs) grow_fs=xfs_growfs;;
    *) die "Unsupported filesystem: $fstype";;
esac
command -v "$grow_fs" >/dev/null || die "Install $grow_fs first"
source=$(readlink -f "$source")
leaf=$source
type=$(lsblk -dnro TYPE "$source")
lvm=0
if [[ $type == lvm ]]; then
    lvm=1
    for cmd in lvs pvs vgs pvresize lvextend; do command -v "$cmd" >/dev/null || die "Install lvm2 first"; done
    # readlink turns /dev/mapper/VG-LV into /dev/dm-N. LVM's positional
    # arguments expect VG/LV names, so recover the LV path by device identity.
    device_number=$(lsblk -dnro MAJ:MIN "$source" | xargs)
    [[ $device_number =~ ^[0-9]+:[0-9]+$ ]] || die "Cannot identify LVM device $source"
    lv_paths=$(lvs --noheadings -o lv_path --select \
        "lv_kernel_major=${device_number%:*} && lv_kernel_minor=${device_number#*:}")
    mapfile -t matching_lvs < <(printf '%s\n' "$lv_paths" | awk 'NF {$1=$1; print}')
    ((${#matching_lvs[@]} == 1)) || die "Cannot uniquely identify logical volume for $source"
    lv_path=${matching_lvs[0]}
    [[ $lv_path == /dev/* && $(readlink -f "$lv_path") == "$source" ]] || die "LVM device identity mismatch"
    source=$lv_path
    vg=$(lvs --noheadings -o vg_name "$source" | xargs)
    segments=$(lvs --noheadings -o segtype "$source" | xargs)
    for segment in $segments; do [[ $segment == linear ]] || die "Only linear LVM is supported"; done
    mapfile -t pvs_in_vg < <(pvs --noheadings -o pv_name --select "vg_name=$vg" | awk '{$1=$1; print}')
    ((${#pvs_in_vg[@]} == 1)) || die "VG must have exactly one PV"
    leaf=$(readlink -f "${pvs_in_vg[0]}")
    type=$(lsblk -dnro TYPE "$leaf")
fi
partition=
case $type in
    part)
        if ! command -v growpart >/dev/null; then
            command -v apt-get >/dev/null || die "Automatic growpart installation requires apt-get; install cloud-guest-utils manually on this guest"
            echo "growpart is missing; installing cloud-guest-utils in the guest."
            apt-get update
            apt-get install -y cloud-guest-utils
            command -v growpart >/dev/null || die "cloud-guest-utils installation did not provide growpart"
        fi
        parent=$(lsblk -dnro PKNAME "$leaf")
        disk=/dev/$parent
        partition=$(cat "/sys/class/block/${leaf##*/}/partition")
        start=$(cat "/sys/class/block/${leaf##*/}/start")
        for entry in /sys/class/block/"$parent"/*/start; do
            [[ -f $entry ]] || continue
            (( $(cat "$entry") <= start )) || die "Selected partition is not the final partition on disk"
        done;;
    disk) disk=$leaf;;
    *) die "Unsupported backing device type: $type";;
esac
[[ $(lsblk -dnro TYPE "$disk") == disk ]] || die "Backing device must be a disk"
mapfile -t disks < <(lsblk -dnro NAME,TYPE | awk '$2 == "disk" {print $1}')
((${#disks[@]} == 1)) || die "Guest must have exactly one disk"
(( $(blockdev --getsize64 "$disk") <= expected_bytes )) || die "Guest disk already exceeds requested size"
echo "Guest: $source ($fstype), mount $mountpoint, disk $disk, partition ${partition:-none}, LVM $lvm"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
df -h "$mountpoint"
[[ $mode == apply ]] || exit 0
if [[ -w /sys/class/block/${disk##*/}/device/rescan ]]; then
    echo 1 > "/sys/class/block/${disk##*/}/device/rescan"
fi
for attempt in {1..10}; do
    bytes=$(blockdev --getsize64 "$disk")
    ((bytes >= expected_bytes)) && break
    sleep 1
done
((bytes >= expected_bytes)) || die "Guest has not detected new disk size; reboot the VM, then rerun with the same total size"
if [[ -n $partition ]]; then
    set +e
    output=$(growpart "$disk" "$partition" 2>&1)
    result=$?
    set -e
    echo "$output"
    if ((result != 0)); then
        [[ $result == 1 && $output == *NOCHANGE:* ]] || die "growpart failed; resolve before rerunning"
    fi
    # growpart must have updated the kernel's partition size too.
    sectors=$(cat "/sys/class/block/${leaf##*/}/size")
    disk_sectors=$((bytes / 512))
    ((disk_sectors - start - sectors < 4096)) || die "Partition does not fill the disk; reboot if kernel partition size is stale, then rerun"
fi
if ((lvm)); then
    pvresize "$leaf"
    free=$(vgs --noheadings -o vg_free_count "$vg" | xargs)
    ((free == 0)) || lvextend -l +100%FREE "$source"
fi
if [[ $fstype == ext4 ]]; then resize2fs "$source"; else xfs_growfs -d "$mountpoint"; fi
df -h "$mountpoint"
GUEST
    )
    # Keep SSH stdin attached to the terminal for sudo's password prompt.
    # Base64 safely carries the program as a remote command argument.
    encoded=$(printf '%s' "$guest_program" | base64 -w 0)
    ssh -t -o BatchMode=yes -o ConnectTimeout=10 "$target" \
        "sudo bash -c \"\$(printf '%s' '$encoded' | base64 -d)\" -- '$1' '$mountpoint' '$mac' '$expected_bytes'"
}
echo "VM $vmid: scsi0 ${old_size} GiB -> ${size} GiB; guest $target; mount $mountpoint"
guest check
if ((!apply)); then
    echo "Preflight passed. No disk changes made (missing growpart may have been installed). Rerun with --apply after taking a backup."
    exit 0
fi
trap 'echo "Resize incomplete. Host disk may already be larger. Fix the error and rerun with the SAME --size." >&2' ERR
if ((size > old_size)); then qm disk resize "$vmid" scsi0 "${size}G"; fi
guest apply
echo "Virtual disk and guest filesystem growth completed."

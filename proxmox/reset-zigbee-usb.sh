#!/usr/bin/env bash
set -euo pipefail

expected_id="1a86:7523"
sysfs_root="/sys/bus/usb/devices"
vm_id="300"
usb_slot="usb0"
# Optional: set this to an SSH target for the Home Assistant OS shell, for
# example "root@homeassistant", to verify when the guest serial device is
# actually usable. Leave empty until the next reproduction.
ha_ssh_target=""

# Stop the Zigbee app in Home Assistant before running this script.
# The VM stays running; only its coordinator USB attachment is reset.

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this script as root on the Proxmox host." >&2
    exit 1
fi
sysfs_path=""
for candidate in "${sysfs_root}"/*; do
    [[ -f ${candidate}/idVendor && -f ${candidate}/idProduct ]] || continue
    candidate_id="$(<"${candidate}/idVendor"):$(<"${candidate}/idProduct")"
    [[ ${candidate_id} == "${expected_id}" ]] || continue
    [[ -z ${sysfs_path} ]] || { echo "Multiple USB devices matching ${expected_id} were found; refusing to reset an ambiguous device." >&2; exit 1; }
    sysfs_path="${candidate}"
done
[[ -n ${sysfs_path} ]] || { echo "USB device ${expected_id} is not currently present." >&2; exit 1; }
usb_device="${sysfs_path##*/}"
actual_id="$(<"${sysfs_path}/idVendor"):$(<"${sysfs_path}/idProduct")"

device_is_present() {
    local candidate candidate_id
    for candidate in "${sysfs_root}"/*; do
        [[ -f ${candidate}/idVendor && -f ${candidate}/idProduct ]] || continue
        candidate_id="$(<"${candidate}/idVendor"):$(<"${candidate}/idProduct")"
        [[ ${candidate_id} == "${expected_id}" ]] && return 0
    done
    return 1
}

wait_for_device() {
    local attempts=${1:-10}
    while (( attempts > 0 )); do
        device_is_present && return 0
        sleep 1
        ((attempts--))
    done
    return 1
}

wait_for_ha_serial() {
    [[ -n ${ha_ssh_target} ]] || return 0
    local attempts=15
    while (( attempts > 0 )); do
        if ssh -o BatchMode=yes -o ConnectTimeout=3 "${ha_ssh_target}" \
            'stty -F /dev/ttyUSB0 115200' >/dev/null 2>&1; then
            echo "Home Assistant serial device is ready."
            return 0
        fi
        sleep 1
        ((attempts--))
    done
    echo "Home Assistant serial device did not become ready within 15 seconds." >&2
    return 1
}

[[ $(qm status "${vm_id}") == "status: running" ]] || { echo "VM ${vm_id} must be running." >&2; exit 1; }
# Refuse pending changes so restoration cannot overwrite them.
pending="$(qm pending "${vm_id}")"
if [[ ${pending} == *"new ${usb_slot}:"* || ${pending} == *"del ${usb_slot}:"* ]]; then
    echo "VM ${vm_id} has a pending ${usb_slot} change; resolve it first." >&2
    exit 1
fi
config="$(qm config "${vm_id}" --current 1)"
usb_config=""
while IFS= read -r line; do
    [[ ${line} == "${usb_slot}: "* ]] || continue
    usb_config="${line#*: }"
done <<< "${config}"
[[ ,${usb_config}, == *",host=${expected_id},"* ]] || {
    echo "VM ${vm_id} ${usb_slot} must reference host=${expected_id}; refusing to change another attachment." >&2
    exit 1
}

restore_passthrough=0
restore_binding=0
cleanup() {
    local result=$?
    trap - EXIT
    if (( restore_binding )); then
        if ! printf '%s' "${usb_device}" > /sys/bus/usb/drivers/usb/bind; then
            echo "Could not restore USB binding for ${usb_device}." >&2
            result=1
        fi
    fi
    if (( restore_passthrough )); then
        if ! qm set "${vm_id}" "--${usb_slot}" "${usb_config}"; then
            echo "Could not restore passthrough. Run: qm set ${vm_id} --${usb_slot} '${usb_config}'" >&2
            result=1
        fi
    fi
    exit "${result}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "The Zigbee app must already be stopped in Home Assistant."
echo "Detaching ${actual_id} from VM ${vm_id} (${usb_slot})..."
restore_passthrough=1
qm set "${vm_id}" --delete "${usb_slot}"
config="$(qm config "${vm_id}" --current 1)"
while IFS= read -r line; do
    if [[ ${line} == "${usb_slot}: "* ]]; then
        echo "USB attachment is still present; refusing to reset it." >&2
        exit 1
    fi
done <<< "${config}"

echo "Unbinding/rebinding USB device ${usb_device}..."
restore_binding=1
printf '%s' "${usb_device}" > /sys/bus/usb/drivers/usb/unbind
sleep 1
printf '%s' "${usb_device}" > /sys/bus/usb/drivers/usb/bind
if ! wait_for_device 10; then
    echo "USB device ${expected_id} did not reappear after rebinding." >&2
    exit 1
fi
restore_binding=0

echo "Restoring VM USB passthrough..."
qm set "${vm_id}" "--${usb_slot}" "${usb_config}"
restore_passthrough=0
if ! wait_for_device 10; then
    echo "USB device ${expected_id} is no longer present after restoring VM passthrough." >&2
    exit 1
fi
if ! wait_for_ha_serial; then
    echo "Check Home Assistant manually with: stty -F /dev/ttyUSB0 115200" >&2
    exit 1
fi
echo "USB reset complete. Start the Zigbee app in Home Assistant now."

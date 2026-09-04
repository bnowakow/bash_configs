#!/usr/bin/env bash
set -Eeuo pipefail

# Prepare this host for Longhorn and optionally join it to an existing K3s
# cluster.  Run as root on the node being added.

longhorn_path=${LONGHORN_DATA_PATH:-/var/lib/longhorn}
zfs_pool=${LONGHORN_ZFS_POOL:-rpool}
zfs_volume=${LONGHORN_ZFS_VOLUME:-longhorn}
zfs_size=${LONGHORN_ZFS_SIZE:-100G}
server_url=${K3S_SERVER_URL:-}
k3s_token=${K3S_TOKEN:-}
k3s_version=${K3S_VERSION:-}

usage() {
  echo "Usage: $0 dependencies | prepare | join | all"
  echo
  echo "Environment for join: K3S_SERVER_URL=host[:6443] [K3S_TOKEN=...]"
  echo "Optional: K3S_VERSION=v1.x.y+k3sN LONGHORN_ZFS_POOL=rpool LONGHORN_ZFS_SIZE=100G"
}

die() { echo "ERROR: $*" >&2; exit 1; }

load_module_if_available() {
  local module=$1
  if modprobe "$module" 2>/dev/null; then
    enabled_modules+=("$module")
  else
    missing_modules+=("$module")
    echo "WARNING: kernel module '$module' is unavailable on $(uname -r)" >&2
  fi
}

ssh_as_invoking_user() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    runuser -u "$SUDO_USER" -- ssh "$@"
  else
    ssh "$@"
  fi
}

remote_sudo() {
  local host=$1
  local command=$2
  local remote_password=${3-}
  if [[ -n "$remote_password" ]]; then
    printf '%s\n' "$remote_password" | \
      ssh_as_invoking_user -o BatchMode=yes "sup@${host}" "sudo -S -p '' ${command}"
  else
    ssh_as_invoking_user -o BatchMode=yes "sup@${host}" "sudo -n ${command}"
  fi
}

[[ ${EUID} -eq 0 ]] || die "run as root (for example: sudo $0 prepare)"
command -v apt-get >/dev/null || die "this script currently supports Debian/Ubuntu hosts only"

dependencies() {
  local packages=(open-iscsi nfs-common cryptsetup dmsetup whiptail)
  local apt_log apt_status package state
  local -a enabled_modules=() missing_modules=()
  apt_log=$(mktemp /tmp/longhorn-apt.XXXXXX.log)

  apt-get update
  set +e
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" 2>&1 | tee "$apt_log"
  apt_status=${PIPESTATUS[0]}
  set -e

  if [[ $apt_status -ne 0 ]]; then
    if grep -Fq 'dpkg: error processing package vim (--configure):' "$apt_log"; then
      for package in "${packages[@]}"; do
        state=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
        [[ "$state" == installed ]] || die "APT failed while Vim was being configured, and required package '$package' is not installed"
      done
      echo "Ignoring only the known Vim configuration failure; Longhorn packages are installed."
    else
      die "apt-get install failed; see $apt_log"
    fi
  else
    rm -f "$apt_log"
  fi

  systemctl enable --now iscsid
  load_module_if_available iscsi_tcp
  load_module_if_available dm_crypt
  install -d -m 0755 /etc/modules-load.d
  printf '%s\n' "${enabled_modules[@]}" > /etc/modules-load.d/longhorn.conf
  if ((${#missing_modules[@]})); then
    echo "WARNING: unavailable kernel modules: ${missing_modules[*]}" >&2
    echo "Longhorn preflight may reject this host; use a supported K3s/Linux kernel." >&2
  fi
}

prepare_storage() {
  command -v zpool >/dev/null || die "zfs utilities are required"
  command -v zfs >/dev/null || die "zfs utilities are required"

  if ! zpool list -H -o name "$zfs_pool" >/dev/null 2>&1; then
    local -a pools
    mapfile -t pools < <(zpool list -H -o name)
    ((${#pools[@]})) || die "no ZFS pools are available"
    command -v whiptail >/dev/null || die "ZFS pool '$zfs_pool' was not found and whiptail is unavailable"

    local -a menu=()
    local pool
    for pool in "${pools[@]}"; do
      menu+=("$pool" "$(zpool list -H -o size,free "$pool")")
    done
    zfs_pool=$(whiptail --title 'Longhorn ZFS pool' \
      --menu 'Select the ZFS pool for the Longhorn volume:' 15 70 6 \
      "${menu[@]}" 3>&1 1>&2 2>&3) || die "ZFS pool selection cancelled"
  fi

  echo "Using ZFS pool: $zfs_pool"

  local volume_path="${zfs_pool}/${zfs_volume}"
  if zfs list -t filesystem -H -o name "$volume_path" >/dev/null 2>&1; then
    die "ZFS dataset '$volume_path' already exists as a filesystem; refusing to use it as a block device"
  fi
  if ! zfs list -t volume -H -o name "$volume_path" >/dev/null 2>&1; then
    zfs create -s -V "$zfs_size" "$volume_path"
  fi

  local device="/dev/zvol/${volume_path}"
  zfs set volmode=dev "$volume_path"
  command -v udevadm >/dev/null && udevadm settle || true
  [[ -b "$device" ]] || die "ZFS volume device '$device' is unavailable"
  if blkid "$device" >/dev/null 2>&1; then
    local fs_type
    fs_type=$(blkid -o value -s TYPE "$device")
    [[ "$fs_type" == ext4 || "$fs_type" == xfs ]] || die "$device contains unsupported filesystem '$fs_type'"
    [[ "$fs_type" == ext4 ]] || die "$device is formatted as xfs; refusing to change it"
  else
    mkfs.ext4 -L longhorn "$device"
  fi

  install -d -m 0755 "$longhorn_path"
  local uuid
  uuid=$(blkid -o value -s UUID "$device")
  grep -qE "^[[:space:]]*UUID=${uuid}[[:space:]]+${longhorn_path}[[:space:]]" /etc/fstab || \
    printf 'UUID=%s  %s  ext4  defaults  0  2\n' "$uuid" "$longhorn_path" >> /etc/fstab
  mountpoint -q "$longhorn_path" || mount "$longhorn_path"

  local mounted_type
  mounted_type=$(findmnt -n -o FSTYPE --target "$longhorn_path")
  [[ "$mounted_type" == ext4 ]] || die "$longhorn_path is mounted as '$mounted_type'"
}

prepare() {
  dependencies
  prepare_storage

  echo "Longhorn host prerequisites are ready:"
  findmnt --target "$longhorn_path"
  df -h "$longhorn_path"
  systemctl is-active iscsid
}

join_cluster() {
  [[ -n "$server_url" ]] || die "K3S_SERVER_URL is required for join"

  local first_node_host
  if [[ "$server_url" =~ ^https://([^/:]+)(:6443)?$ ]]; then
    first_node_host=${BASH_REMATCH[1]}
    server_url="https://${first_node_host}:6443"
  elif [[ "$server_url" =~ ^[^/:]+$ ]]; then
    first_node_host=$server_url
    server_url="https://${first_node_host}:6443"
  else
    die "K3S_SERVER_URL must be a hostname or look like https://host:6443"
  fi

  local remote_password=''
  if [[ -z "$k3s_token" ]]; then
    command -v ssh >/dev/null || die "ssh is required to retrieve K3s credentials"
    k3s_token=$(remote_sudo "$first_node_host" \
      'cat /var/lib/rancher/k3s/server/node-token') || {
        [[ -t 0 || -e /dev/tty ]] || die "remote sudo requires a password, but no terminal is available"
        read -r -s -p "Remote sudo password for sup@${first_node_host}: " remote_password < /dev/tty
        echo >&2
        k3s_token=$(remote_sudo "$first_node_host" \
          'cat /var/lib/rancher/k3s/server/node-token' "$remote_password") || \
          die "could not retrieve the K3s token from sup@${first_node_host}"
      }
  fi
  if [[ -z "$k3s_version" ]]; then
    k3s_version=$(remote_sudo "$first_node_host" \
      'k3s --version' "$remote_password" | awk 'NR == 1 { print $3 }') || \
      die "could not retrieve the K3s version from sup@${first_node_host}"
  fi
  [[ -n "$k3s_token" ]] || die "retrieved K3S_TOKEN is empty"
  [[ -n "$k3s_version" ]] || die "retrieved K3S_VERSION is empty"

  local install_args=(agent --server "$server_url" --token "$k3s_token")
  export INSTALL_K3S_VERSION=${k3s_version//+/%2B}
  curl -sfL https://get.k3s.io | sh -s - "${install_args[@]}"
  systemctl is-active --quiet k3s-agent || die "k3s-agent did not become active"

  local node_name
  node_name=$(hostname)
  if ! remote_sudo "$first_node_host" \
      "k3s kubectl label node ${node_name} node.longhorn.io/create-default-disk=true --overwrite" \
      "$remote_password"; then
    [[ -t 0 || -e /dev/tty ]] || die "remote sudo requires a password, but no terminal is available to label the node"
    read -r -s -p "Remote sudo password for sup@${first_node_host}: " remote_password < /dev/tty
    echo >&2
    remote_sudo "$first_node_host" \
      "k3s kubectl label node ${node_name} node.longhorn.io/create-default-disk=true --overwrite" \
      "$remote_password" || die "could not label node ${node_name} for Longhorn"
  fi
  remote_password=''
  echo "K3s agent joined and node ${node_name} was labeled for Longhorn."
}

[[ $# -eq 1 ]] || { usage; exit 2; }
case "$1" in
  dependencies) dependencies ;;
  prepare) prepare ;;
  join) join_cluster ;;
  all) prepare; join_cluster ;;
  *) usage; exit 2 ;;
esac

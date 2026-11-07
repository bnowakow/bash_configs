#!/bin/bash
# Temporary testing helper. Bootstrap from master:
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bnowakow/homelab/master/taerar/ansible/undo-provision.sh)"
set -euo pipefail

main() {
  if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    return 2
  fi
  if [[ $(uname -s) != Darwin ]]; then
    echo 'This script requires macOS.' >&2
    return 1
  fi
  if [[ $EUID -eq 0 ]]; then
    echo 'Run this script as your normal user, without sudo.' >&2
    return 1
  fi

  local state_dir="$HOME/.homelab-provision-state"
  local repo_dir="$HOME/code/homelab"
  local uninstaller
  if [[ ! -d "$state_dir" ]]; then
    echo 'No recorded provisioning changes to undo. Earlier untracked runs cannot be undone automatically.'
    return 0
  fi

  # Reverse provisioning order. Leave each marker until its undo succeeds.
  if [[ -f "$state_dir/homebrew-installed" ]]; then
    echo 'Uninstalling Homebrew installed by provisioning...'
    uninstaller=$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)
    NONINTERACTIVE=1 /bin/bash -c "$uninstaller"
    rm "$state_dir/homebrew-installed"
  fi

  if [[ -f "$state_dir/repo-created" ]]; then
    echo "Removing provisioning-created checkout (including any local changes): $repo_dir"
    # The running script may live inside this checkout. main is already parsed.
    cd "$HOME"
    rm -rf -- "$repo_dir"
    rm "$state_dir/repo-created"
  fi

  if [[ -f "$state_dir/code-created" ]]; then
    if [[ -d "$HOME/code" ]]; then
      # Preserve unrelated files; retry on the next undo after they are moved.
      if ! rmdir "$HOME/code"; then
        echo '~/code was retained because it is not empty. Its undo marker is preserved.' >&2
        return 1
      fi
    fi
    rm "$state_dir/code-created"
  fi

  rmdir "$state_dir"
  echo 'Recorded provisioning changes have been undone.'
}

main "$@"

#!/bin/bash
# Bootstrap from master (copy and run in Terminal):
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bnowakow/homelab/master/taerar/ansible/provision.sh)"
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

if [[ $(uname -s) != Darwin ]]; then
  echo 'This script requires macOS.' >&2
  exit 1
fi

if [[ $EUID -eq 0 ]]; then
  echo 'Run this script as your normal user, without sudo.' >&2
  exit 1
fi

# Keep test rollback state outside the checkout, which undo may remove.
state_dir="$HOME/.homelab-provision-state"
umask 077
mkdir -p "$state_dir"

if [[ ! -e "$HOME/code" ]]; then
  touch "$state_dir/code-created"
  mkdir "$HOME/code"
fi

repo_dir="$HOME/code/homelab"
if [[ ! -e "$repo_dir" ]]; then
  echo "Cloning homelab into $repo_dir..."
  # Record intent first so a failed/interrupted clone can also be undone.
  touch "$state_dir/repo-created"
  git clone https://github.com/bnowakow/homelab.git "$repo_dir"
elif [[ ! -e "$repo_dir/.git" ]]; then
  echo "$repo_dir already exists but is not a Git checkout. Resolve this before continuing." >&2
  exit 1
else
  echo "Reusing homelab checkout: $repo_dir"
fi

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    echo /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    echo /usr/local/bin/brew
  else
    return 1
  fi
}

if brew_bin=$(find_brew); then
  echo "Homebrew is already installed: $brew_bin"
else
  echo 'Installing Homebrew...'
  installer=$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
  touch "$state_dir/homebrew-installed"
  /bin/bash -c "$installer"
  unset installer
  if ! brew_bin=$(find_brew); then
    echo 'Homebrew installation finished, but brew could not be found.' >&2
    exit 1
  fi
fi

# Make Homebrew available to subsequent provisioning steps in this process.
eval "$("$brew_bin" shellenv)"
brew --version

# macOS provisioning

This directory will contain the Ansible setup for provisioning macOS machines,
following the approach used by [`nas/ansible/provision.sh`](../../nas/ansible/provision.sh)
for Linux servers.

This document records the manual preparation required before running Ansible.
`provision.sh` currently creates `~/code`, clones this repository if missing, and
ensures Homebrew and Ansible are installed. Subsequent provisioning actions will
be implemented as Ansible playbooks, including dotfile installation.

## Manual steps before running Ansible

The checklist is pending. Add the manual steps here as they are identified, in
the order they must be completed on a Mac.

For each step, document:

- The action to perform, including any commands or macOS settings paths.
- Any required choices or values.
- How to verify that the step is complete.

## Running provisioning

On a new Mac, run as your normal user, without `sudo`. This downloads and executes
the script from the `master` branch:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bnowakow/homelab/master/taerar/ansible/provision.sh)" -- --unattended
```

The examples use `--unattended` to automatically proceed past installation
confirmations such as `Do you want to proceed with the installation? [y/n]`.
Omit `--unattended` to keep interactive prompts. The Homebrew installer requires
existing sudo authorization for unattended installation; if necessary, run
`sudo -v` first. Passwords and macOS permission dialogs cannot be auto-answered.

To find the command: open [bnowakowski.pl](http://bnowakowski.pl), follow the
GitHub link, open the `homelab` repository, and browse to
`taerar/ansible/provision.sh`.

The script creates `~/code` if needed and clones
`https://github.com/bnowakow/homelab.git` into `~/code/homelab` if that path is
missing. Existing checkouts are reused without changing their remote. Switching
`origin` to SSH will be added later. Git must be available to clone; on a fresh
Mac, complete any macOS Command Line Tools installation prompt and rerun the
script if needed.

From an existing checkout, you can also run from the repository root:

```sh
./taerar/ansible/provision.sh --unattended
```

The script reuses Homebrew if it is on `PATH` or in either standard macOS
installation location (`/opt/homebrew` or `/usr/local`). Otherwise, it runs the
official Homebrew installer, which may prompt for your password and confirmation.
It loads Homebrew's environment for subsequent steps in the script.

Next it reuses an existing `ansible-playbook` command, or installs the `ansible`
Homebrew formula and verifies it with `ansible-playbook --version`. Missing
formulae are recorded before installation so partial installs can be undone.

## Undoing provisioning during testing

Run as your normal user, without `sudo`:

```sh
./taerar/ansible/undo-provision.sh
```

Or download and run the version from `master`:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bnowakow/homelab/master/taerar/ansible/undo-provision.sh)"
```

Provisioning records its changes in `~/.homelab-provision-state`, including
attempts that may fail partway through. Undo reverses them in order: remove
Ansible and its newly installed dependencies, uninstall Homebrew using the
official uninstaller without confirmation, remove the cloned
`~/code/homelab` checkout **including any local changes**, then remove `~/code`
only if empty. Resources that existed before provisioning are preserved. State
is retained when an undo step fails so you can rerun it. Do not run provisioning
and undo concurrently.

Runs made before tracking was added cannot be automatically undone. Homebrew's
installer may install Apple's Command Line Tools; undo does not remove those.
The Homebrew uninstaller may also report leftover files requiring manual cleanup.
Environment changes made inside the provisioning process expire when it exits.
Ansible rollback preserves formulae present before installation; it does not
restore upgraded dependency versions. If another package now requires a tracked
formula, Homebrew may refuse removal; resolve that dependency before retrying.

## Running Ansible

Ansible installation is implemented. Playbook execution will be added next;
dotfile installation is deferred to a playbook rather than called directly from
the bootstrap shell script.

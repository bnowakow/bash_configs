#!/usr/bin/env bash
# Copy this host's dotfiles from ~ into bash_configs, so that
# nas/ansible/sup-dotfiles_playbook.yml (run by provision.sh) can apply them
# back to the hosts. The file list and the per-host .screenrc mapping live in
# nas/ansible/vars/sup-dotfiles.yml.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
config=nas/ansible/vars/sup-dotfiles.yml
host=$(hostname -s)

if [[ -t 1 ]]; then
	bold=$'\033[1m' green=$'\033[32m' yellow=$'\033[33m' normal=$'\033[0m'
else
	bold='' green='' yellow='' normal=''
fi

have_tty() { [[ -r /dev/tty && -w /dev/tty ]] && { : </dev/tty; } 2>/dev/null; }

# Items of a top-level list of plain strings, e.g. "sup_dotfiles:\n  - .zshrc".
read_list() {
	awk -v key="$1" '
		/^[^[:space:]#]/ { in_list = ($0 ~ "^" key ":") ; next }
		in_list && /^[[:space:]]+-[[:space:]]/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); gsub(/["\047]/, ""); print }
	' "$config"
}

# "regex<TAB>file" pairs from sup_screenrc_files.
read_screenrc_map() {
	awk '
		/^[^[:space:]#]/ { in_list = ($0 ~ /^sup_screenrc_files:/); next }
		!in_list { next }
		/host_regex:/ { sub(/.*host_regex:[[:space:]]*/, ""); gsub(/^["\047]|["\047][[:space:]]*$/, ""); regex = $0 }
		/[[:space:]]file:/ { sub(/.*file:[[:space:]]*/, ""); gsub(/["\047]/, ""); print regex "\t" $0 }
	' "$config"
}

ask_yes_no_dialog() {
	local title=$1 text=$2
	if have_tty && [[ -n "${TERM:-}" && "${TERM}" != dumb ]]; then
		if command -v dialog >/dev/null 2>&1; then
			dialog --title "$title" --yesno "$text" 20 90 >/dev/tty 2>&1 </dev/tty
			local status=$?
			clear >/dev/tty 2>&1 || true
			return "$status"
		fi
		if command -v whiptail >/dev/null 2>&1; then
			whiptail --title "$title" --yesno "$text" 20 90 >/dev/tty 2>&1 </dev/tty
			return
		fi
	fi
	ask_yes_no_prompt "$text"
}

ask_yes_no_prompt() {
	local answer
	if ! have_tty; then
		return 1
	fi
	printf '%s [y/N] ' "$1" >/dev/tty
	read -r answer </dev/tty || return 1
	[[ "$answer" =~ ^[yY]([eE][sS])?$ ]]
}

synced_files=()

sync_file() {
	local home_file=$1 repo_file=$2 shared=$3
	if [[ ! -e "$HOME/$home_file" ]]; then
		printf '  %-24s %smissing in ~, skipped%s\n' "$repo_file" "$yellow" "$normal"
		return
	fi
	if [[ -e "$repo_file" ]] && cmp -s "$HOME/$home_file" "$repo_file"; then
		printf '  %-24s up to date\n' "$repo_file"
		return
	fi

	if [[ "$shared" == shared ]]; then
		printf '\n%s~/%s differs from %s (shared by all hosts):%s\n' "$bold" "$home_file" "$repo_file" "$normal"
		git --no-pager diff --no-index --color=auto -- "$repo_file" "$HOME/$home_file" || true
		if ! ask_yes_no_prompt "Copy ~/$home_file into $repo_file for every host?"; then
			printf '  %-24s %sskipped%s\n\n' "$repo_file" "$yellow" "$normal"
			return
		fi
	fi

	cp -- "$HOME/$home_file" "$repo_file"
	synced_files+=("$repo_file")
	printf '  %-24s %supdated from ~/%s%s\n' "$repo_file" "$green" "$home_file" "$normal"
}

printf '%sSyncing dotfiles from ~ on %s%s\n' "$bold" "$host" "$normal"

screenrc_file=
while IFS=$'\t' read -r regex file; do
	if [[ "$host" =~ $regex ]]; then
		screenrc_file=$file
		break
	fi
done < <(read_screenrc_map)

if [[ -n "$screenrc_file" ]]; then
	sync_file .screenrc "$screenrc_file" host
else
	printf '  %-24s %sno mapping for %s in %s, skipped%s\n' .screenrc "$yellow" "$host" "$config" "$normal"
fi

while read -r file; do
	sync_file "$file" "$file" shared
done < <(read_list sup_dotfiles)

if [[ ${#synced_files[@]} -eq 0 ]]; then
	printf 'Nothing to sync.\n'
	exit 0
fi

git add -- "${synced_files[@]}"
if git diff --cached --quiet -- "${synced_files[@]}"; then
	printf 'No staged changes after sync.\n'
	exit 0
fi

printf '\nStaged: %s\n' "${synced_files[*]}"
message="Staged dotfile changes from $host:"$'\n\n'
message+=$(git diff --cached --stat -- "${synced_files[@]}")
other_staged=$(git diff --cached --name-only -- . "${synced_files[@]/#/:!}")
if [[ -n "$other_staged" ]]; then
	message+=$'\n\nAlso staged (will be included in the commit):\n'"$other_staged"
fi
message+=$'\n\nRun make codex-commit now?'

if ask_yes_no_dialog 'sync-dotfiles' "$message"; then
	exec make codex-commit
fi
printf 'Left staged. Commit later with: make codex-commit\n'

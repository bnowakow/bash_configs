# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...

# File search functions
function f() { find . -iname "*$1*" ${@:2} }
function r() { grep "$1" ${@:2} -R . }

# Create a folder and move into it in one command
function mkcd() { mkdir -p "$@" && cd "$_"; }

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*

export EDITOR=vim
export BUNDLEEDITOR="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
export CLICOLOR=1
unset GREP_OPTIONS;
export GREP_COLOR='1;32'
alias grep='grep --color=auto'

alias ll='ls -Ghlas'
alias ..='cd ..'
alias ...='cd .. ; cd ..'
alias g='grep -i'  #case insensitive grep
alias f='find . -iname'
alias ducks='du -cks * | sort -rn|head -11' # Lists the size of all the folders and files
alias top='top -o cpu'
alias systail='tail -f /var/log/system.log'

alias perms='stat -f %Mp%Lp $1'
alias ports='lsof -Pan -i tcp -i udp'

alias add="git add ."
alias commit="git commit -m $1"
alias cm="git commit -m $1"
alias pull="git pull"
alias push="git push"
alias log="git hist"
alias s="git status"
alias truth="git shortlog -s -n"

alias port="lsof -i $1"
alias killbyport="kill -9 \`lsof -i:3000 -t\`"
alias serve="python -m SimpleHTTPServer"

export PATH=$PATH:~/Applications
#:"/Applications/IntelliJ IDEA 15.app/Contents/MacOS"

export GPG_TTY=$(tty)

export HOMEBREW_PREFIX="/opt/homebrew";
export HOMEBREW_CELLAR="/opt/homebrew/Cellar";
export HOMEBREW_REPOSITORY="/opt/homebrew";
export HOMEBREW_SHELLENV_PREFIX="/opt/homebrew";
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}";
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:";
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}";

export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# https://www.cyberciti.biz/faq/perl-warning-setting-locale-failed-in-debian-ubuntu/
export LC_CTYPE=pl_PL.UTF-8
export LC_ALL=pl_PL.UTF-8

[[ -s "$HOME/.profile" ]] && source "$HOME/.profile" # Load the default .profile

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*

 # export BUNDLEEDITOR=/usr/local/bin/mate
export BUNDLEEDITOR=/usr/local/bin/atom
export CLICOLOR=1
export GREP_OPTIONS='--color=auto' GREP_COLOR='1;32'

# customize the colors in terminal preferences to your liking
export TERM='xterm-256color'
export COLOR_NC='\[\033[0m\]' # No Color
export COLOR_BLACK='\[\033[0;30m\]'
export COLOR_BRIGHT_BLACK='\[\033[1;30m\]'
export COLOR_RED='\[\033[0;31m\]'
export COLOR_BRIGHT_RED='\[\033[1;31m\]'
export COLOR_GREEN='\[\033[0;32m\]'
export COLOR_BRIGHT_GREEN='\[\033[1;32m\]'
export COLOR_YELLOW='\[\033[1;33m\]'
export COLOR_BRIGHT_YELLOW='\[\033[1;33m\]'
export COLOR_BLUE='\[\033[0;34m\]'
export COLOR_BRIGHT_BLUE='\[\033[1;34m\]'
export COLOR_PURPLE='\[\033[0;35m\]'
export COLOR_BRIGHT_PURPLE='\033[1;35m\]'
export COLOR_CYAN='\[\033[0;36m\]'
export COLOR_BRIGHT_CYAN='\[\033[1;36m\]'
export COLOR_WHITE='\[\033[0;37m\]'
export COLOR_BRIGHT_WHITE='\[\033[1;37m\]'
alias colorslist="set | egrep '^COLOR_\\w*'"  # lists all the colors

# call this function from prompt then customize your terminal colors how you like in the terminal/preference/settings
# colors will change so you can see what they look like in the terminal
colorsdisplay (){
	echo -e "\033[0mCOLOR_NC (No color)"
	echo -e "\033[0;30mCOLOR_BLACK\t\033[1;30mCOLOR_BRIGHT_BLACK"
	echo -e "\033[0;31mCOLOR_RED\t\033[1;31mCOLOR_BRIGHT_RED"
	echo -e "\033[0;32mCOLOR_GREEN\t\033[1;32mCOLOR_BRIGHT_GREEN"
	echo -e "\033[0;33mCOLOR_YELLOW\t\033[1;33mCOLOR_BRIGHT_YELLOW"
	echo -e "\033[0;34mCOLOR_BLUE\t\033[1;34mCOLOR_BRIGHT_BLUE"
	echo -e "\033[0;35mCOLOR_PURPLE\t\033[1;35mCOLOR_BRIGHT_PURPLE"
	echo -e "\033[0;36mCOLOR_CYAN\t\033[1;36mCOLOR_BRIGHT_CYAN"
	echo -e "\033[0;37mCOLOR_WHITE\t\033[1;37mCOLOR_BRIGHT_WHITE"
}

# http://git-prompt.sh
git_prompt_path=~/Applications/.git-prompt.sh;
git_prompt_exists=$(ls -la $git_prompt_path);
if [ $? -eq 1 ];
then
	echo ".git-prompt.sh does not exist. Downloading."
	curl -o $git_prompt_path \
	    https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh;
fi
source $git_prompt_path

GIT_COMPLETION=/Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash
if [ -f $GIT_COMPLETION ]; then
    . $GIT_COMPLETION
	#PS1="$PS1[${COLOR_NC}${COLOR_CYAN}git -> \W\$(__git_ps1 \" (%s)\")${COLOR_NC}${COLOR_BRIGHT_BLACK}]\n"
	PS1="[${COLOR_NC}${COLOR_CYAN}git -> \W\$(__git_ps1 \" (%s)\")${COLOR_NC}${COLOR_BRIGHT_BLACK}]\n"
fi
# end git display

# current working directory prompt
PS1="$PS1[${COLOR_NC}${COLOR_GREEN}pwd -> \w${COLOR_NC}${COLOR_BRIGHT_BLACK}]\n[${COLOR_NC}${COLOR_RED}\T${COLOR_NC}${COLOR_BRIGHT_BLACK}] -> ${COLOR_NC}"

#michal ps1
PS1="\u@\h: ${COLOR_NC}${COLOR_GREEN}\W ${COLOR_NC}${COLOR_PURPLE}\$(__git_ps1 \"(%s)\")${COLOR_NC}${COLOR_BRIGHT_BLACK} $ "
#PS1="${COLOR_NC}${COLOR_GREEN}\W ${COLOR_NC}${COLOR_PURPLE}\$(__git_ps1 \"(%s)\")${COLOR_NC}${COLOR_BRIGHT_BLACK} $ "
#michal ps1 end

export PS1
# prompt for continuing commands
PS2="${COLOR_BRIGHT_BLACK} -> ${COLOR_NC}"
export PS2

#alias ls='ls --color=auto'
#alias ls='ls -Glas'
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

alias sim='/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Applications/iPhone\ Simulator.app/Contents/MacOS/iPhone\ Simulator'
alias proxyon='networksetup -setwebproxystate Wi-Fi on; networksetup -setsecurewebproxystate Wi-Fi off;'
alias proxyoff='networksetup -setwebproxystate Wi-Fi off; networksetup -setsecurewebproxystate Wi-Fi off;'

alias add="git add ."
alias commit="git commit -m $1"
alias cm="git commit -m $1"
alias pull="git pull"
alias push="git push"
alias log="git hist"
alias s="git status"
alias port="lsof -i $1"
alias truth="git shortlog -s -n"
alias killbyport="kill -9 \`lsof -i:3000 -t\`"
alias serve="python -m SimpleHTTPServer"
# alias xcode5="sudo xcode-select --switch /Applications/Xcode5-DP5.app/Contents/Developer/"
# alias xcode4="sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer/"

export PATH=$PATH:~/Applications
#:"/Applications/IntelliJ IDEA 15.app/Contents/MacOS"

export GPG_TTY=$(tty)

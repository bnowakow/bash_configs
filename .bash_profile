GIT_PROMPT_PWD="/Users/sup/Documents/coding/git-prompt.sh"
if [ -f $GIT_PROMPT_PWD ]; then
	. $GIT_PROMPT_PWD
fi

export JAVA_HOME=`/usr/libexec/java_home -v 1.7 2>/dev/null`
#export AXIS2_HOME=`~/utils/axis2-1.6.2/bin`=~/utils/axis2-1.6.2/bin/:$PATH

export PATH="/Users/$USER/.gem/ruby/2.0.0/bin":${PATH}

export EC2_HOME=~/.ec2
export PATH=$PATH:$EC2_HOME/bin
#export EC2_PRIVATE_KEY=`ls $EC2_HOME/pk-*.pem`
#export EC2_CERT=`ls $EC2_HOME/cert-*.pem`
export JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Home/

export MAVEN_OPTS="-Xmx1536m -XX:MaxPermSize=512m"

#sx-lion-terminal-x256

#clear

[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm" # This loads RVM into a shell session
PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting

PATH="/usr/local/bin:/usr/local/sbin:/usr/local/mysql/bin:$PATH"
PATH="/usr/local/mysql/bin:$PATH" # mysql path

export BUNDLEEDITOR=/usr/local/bin/mate
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

# begin rvm display (if you don't want to use the rvm prompt display just comment out these lines in this section)
#if [ -d "$HOME/.rvm" ]; then
#	[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm" # Load RVM function (http://beginrescueend.com/workflow/prompt/)
#	[[ -r "$HOME/.rvm/scripts/completion" ]] && . "$HOME/.rvm/scripts/completion" # Load RVM completion (http://beginrescueend.com/workflow/completion/)
#	PS1="${COLOR_BRIGHT_BLACK}[${COLOR_NC}${COLOR_BRIGHT_PURPLE}rvm -> \$(~/.rvm/bin/rvm-prompt)${COLOR_NC}${COLOR_BRIGHT_BLACK}]\n"
#fi
# end rvm display

# begin git display (if you don't want to use the git prompt display just comment lines in this section)
# \W$(__git_ps1 " (%s)")
# Turn on git tab completion if the file exists (get it here: https://github.com/git/git/blob/master/contrib/completion/git-completion.bash)
source ~/.git-prompt.sh
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

alias motivo="cd ~/bi/motivo"
alias motivoweb="cd ~/bi/motivoweb"
alias db="cd ~/bi/dubbios"
alias dbweb="cd ~/bi/dubb"
alias pp="cd ~/bi/pitupitu"
alias ppw="cd ~/bi/pitupituweb"
alias ppa="cd ~/bi/pitupitu-android"
alias nb="cd ~/bi/nbmedical"
alias zebra="cd ~/bi/zebra"
alias zebraandroid="cd ~/bi/zebraandroid"
alias ihs="cd ~/ihs"
alias bi="cd ~/bi"
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
alias xcode5="sudo xcode-select --switch /Applications/Xcode5-DP5.app/Contents/Developer/"
alias xcode4="sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer/"


# allows you to save bookmarks to folders
#  cd ~/src/git
#  save git
#  cd ~/src/git/killer/rails/awesome/app
#  save awesome_app
# list your bookmarks
#  show
#   git="~/src/git"
#   awesome_app="~/src/git/killer/rails/awesome/app"
# easily cd into the bookmarks from any directory
#  cd git
#  cd awesome_app
if [ ! -f ~/.dirs ]; then  # if doesn't exist, create it
	touch ~/.dirs
fi

alias show='cat ~/.dirs'
save (){
	command sed "/!$/d" ~/.dirs > ~/.dirs1; mv ~/.dirs1 ~/.dirs; echo "$@"=\"`pwd`\" >> ~/.dirs; source ~/.dirs ; 
}
source ~/.dirs  # Initialization for the above 'save' facility: source the .sdirs file
shopt -s cdable_vars # set the bash option so that no '$' is required when using the above facility

# bash shell useful settings
export HISTCONTROL=ignoredups # Ignores dupes in the history
shopt -s checkwinsize # After each command, checks the windows size and changes lines and columns

# bash completion settings (actually, these are readline settings)
bind "set completion-ignore-case on" # note: bind is used instead of setting these in .inputrc.  This ignores case in bash completion
bind "set bell-style none" # No bell, because it's damn annoying
bind "set show-all-if-ambiguous On" # this allows you to automatically show completion without double tab-ing

# shows the commands you use most, it's useful to show you what you should create aliases for
alias profileme="history | awk '{print $2}' | awk 'BEGIN{FS=\"|\"}{print $1}' | sort | uniq -c | sort -n | tail -n 20 | sort -nr"

# Turn on advanced bash completion if the file exists (get it here: http://www.caliban.org/bash/index.shtml#completion)
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi
# Initialization for FDK command line tools.Mon Oct 22 08:36:12 2012
FDK_EXE="/Users/$USER/bin/FDK/Tools/osx"
PATH=${PATH}:"/Users/$USER/bin/FDK/Tools/osx"
PATH=${PATH}:"/Users/$USER/android-sdk-macosx 2/tools"
PATH=${PATH}:"/Applications/Postgres93.app/Contents/MacOS/bin"
#PATH=${PATH}:"/Volumes/supach-Bigi-Mac/Applications/Postgres93.app/Contents/MacOS/bin"

export PATH
export FDK_EXE

ANDROID_HOME="/usr/local/Cellar/android-sdk/r13"
export ANDROID_HOME

# git config credential.helper store
# git config --global credential.helper cache
# git config --global credential.helper "cache --timeout=3600"
# git config --global credential.helper osxkeychain
git config --global alias.today '!git log --since=midnight --author="$(git config user.name)" --oneline'

#\curl -L https://get.rvm.io | bash -s stable

### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

source ~/.profile
export GEM_HOME="$HOME/.gem/ruby/2.0.0"

export EDITOR="mate -wl1"

function setjdk() {  
  if [ $# -ne 0 ]; then  
   removeFromPath '/System/Library/Frameworks/JavaVM.framework/Home/bin'  
   if [ -n "${JAVA_HOME+x}" ]; then  
    removeFromPath $JAVA_HOME  
   fi  
   
   export JAVA_HOME=`/usr/libexec/java_home -v $@`  
   export PATH=$JAVA_HOME/bin:$PATH  
  fi  
 }  
 function removeFromPath() {  
  export PATH=$(echo $PATH | sed -E -e "s;:$1;;" -e "s;$1:?;;")  
 }
 #setjdk 1.8
setjdk 1.8

function manp() { man -t $1 | open -f -a Preview; }

# Pebble SDK
export PATH="/Users/sup/pebble-dev/PebbleSDK-current/bin:$PATH"

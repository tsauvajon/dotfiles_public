# Replace ls with eza
alias ls='eza -al --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions' # preferred listing
alias la='eza -a --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions'  # all files and dirs
alias ll='eza -l --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions'  # long format
alias lt='eza -aT --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions' # tree listing

# More replacements
alias j='z'
alias top='htop'
alias btop='htop'
alias du='dust'
alias find='fd'

# Editor aliases
alias h='hx'
alias vi='nvim'
alias vim='nvim'

# TUI file explorer aliases
alias ranger='yazi'
alias lf='yazi'

# Common use
alias fmt='rustup run nightly cargo fmt'
alias grubup="sudo grub-mkconfig -o /boot/grub/grub.cfg"
alias fixpacman="sudo rm /var/lib/pacman/db.lck"
alias tarnow='tar -acf '
alias untar='tar -zxvf '
alias wget='wget -c '
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias hw='hwinfo --short'                                   # Hardware Info
alias big="expac -H M '%m\t%n' | sort -h | nl"              # Sort installed packages according to size in MB
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l'          # List amount of -git packages
alias update='sudo pacman -Syu'

# Path aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

# Get fastest mirrors
alias mirror="sudo cachyos-rate-mirrors"

# Help people new to Arch
alias apt='man pacman'
alias apt-get='man pacman'
alias please='sudo'
alias tb='nc termbin.com 9999'

# Cleanup orphaned packages
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'

# Get the error messages from journalctl
alias jctl="journalctl -p 3 -xb"

# Recent installed packages
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"

# Fix broken ntfs partitions (specific to my ROG zephyrus laptop setup)
alias fixntfs="sudo ntfsfix /dev/nvme0n1p4 && sudo ntfsfix /dev/nvme0n1p6 && sudo ntfsfix /dev/nvme0n1p7 && sudo ntfsfix /dev/nvme0n1p8" 

# Fish command history
function history
    builtin history --show-time='%F %T '
end

# Rename files to .bak
function backup --argument filename
    cp $filename $filename.bak
end

# Copy DIR1 DIR2
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | trim-right /)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

# Find in files - until I remember the grep command
function search --argument folder --argument pattern
    echo "grep -rnw 'FOLDER' -e 'PATTERN'"
    grep -rnw "$folder" -e "$pattern"
end

# Git
alias g='git'
alias ga='git add'
alias gan='git commit --all --amend --no-edit'
alias gcn='git commit --amend --no-edit'
alias gss='git status --short'
alias glog='echo "TODO"'
alias gd='git diff'
alias gp='git push'
alias gpu='git push --set-upstream'
alias gpl='git pull --recurse-submodules'
alias gcl='git clone --recurse-submodules'
alias gc='git commit'
alias gam='git commit -am'
alias gcm='git commit -m'
alias gcb='git checkout -b'
alias gco='git checkout'
alias gra='git remote add'
alias grr='git remote remove'
alias grv='git remote --verbose'
alias grb='git fetch && git rebase --interactive --autosquash'
alias gf='git fetch' 

# Shorthands
alias oc='opencode'
alias md='mdterm'

# Task
alias cdt='cd-task'
alias t='task'
alias ts='task start'
alias tp='task path'
alias td='task detach'

# Fish-only aliases.
#
# Cross-shell aliases live in home/programs/aliases.nix and are
# generated into ~/.config/fish/conf.d/common-aliases.fish (auto-loaded
# by fish). Machine-private aliases live in ~/.config/dotfiles/extras.fish
# and are sourced from config.fish.
#
# Each block below is sorted alphabetically (case-insensitive, lowercase
# first).

# Tool replacements
alias btop='htop'
alias cat='bat'
alias du='dust'
alias find='fd'
alias top='htop'

# TUI file explorer aliases
alias lf='yazi'
alias ranger='yazi'

# Common use
alias big="expac -H M '%m\t%n' | sort -h | nl"              # Sort installed packages according to size in MB
alias dir='dir --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias fixpacman="sudo rm /var/lib/pacman/db.lck"
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l'          # List amount of -git packages
alias grep='grep --color=auto'
alias grubup="sudo grub-mkconfig -o /boot/grub/grub.cfg"
alias hw='hwinfo --short'                                   # Hardware Info
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias tarnow='tar -acf '
alias untar='tar -zxvf '
alias update='sudo pacman -Syu'
alias vdir='vdir --color=auto'
alias wget='wget -c '

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

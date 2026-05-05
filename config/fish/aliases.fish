# Fish-only aliases and functions.
#
# Cross-shell aliases live in home/programs/aliases.nix and are
# generated into ~/.config/fish/conf.d/common-aliases.fish (auto-loaded
# by fish). Machine-private aliases live in ~/.config/dotfiles/extras.fish
# and are sourced from config.fish.
#
# Only fish-specific functions live here. The zsh equivalents are
# kept in sync in config/shell/zshrc.

# Show timestamps in `history` output. zsh has its own version that
# uses `fc -li`; both shells produce a date+time prefix.
function history
    builtin history --show-time='%F %T '
end

# Copy a file to <file>.bak. zsh has its own one-liner equivalent.
function backup --argument filename
    cp $filename $filename.bak
end

function rd --description 'ripgrep with delta syntax highlighting'
    set -l has_context 0
    for arg in $argv
        string match -qr -- '^-C' $arg; and set has_context 1
    end

    if test $has_context -eq 0
        rg --json -C2 $argv | delta
    else
        rg --json $argv | delta
    end
end

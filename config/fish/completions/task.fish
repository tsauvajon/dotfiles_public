function __task_complete
    task __complete (commandline -opc | string split ' ' | tail -n +2) 2>/dev/null
end

complete -c task -f -a '(__task_complete)'

# Build a merged directory from a list of source paths.
#
# Each source's top-level entries (files or subdirectories) are
# symlinked into the output. Later sources override earlier ones on
# filename collision — i.e. pass `[ public private ]` to let the
# private overlay win on conflict.
#
# Use the result as `home.file."<target>".source = mergeDirs { ... };`
# or `xdg.configFile."<target>".source = mergeDirs { ... };`.
#
# Sources that do not exist are silently skipped.
{ pkgs, lib }:

{
  name,
  sources,
  excludeNames ? [ ],
}:

let
  existingSources = builtins.filter builtins.pathExists sources;
  excludeCases =
    if excludeNames == [ ] then
      "          __merge_dirs_no_exclusions__) : ;;"
    else
      lib.concatMapStringsSep "\n" (entry: "          ${lib.escapeShellArg entry}) continue ;;") excludeNames;
in
pkgs.runCommand name { } ''
  mkdir -p "$out"
  ${lib.concatMapStringsSep "\n" (src: ''
    if [ -d "${src}" ]; then
      for entry in "${src}"/* "${src}"/.[!.]* "${src}"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        entry_name="''${entry##*/}"
        case "$entry_name" in
${excludeCases}
        esac
        ln -sfn "$entry" "$out/"
      done
    fi
  '') existingSources}
''

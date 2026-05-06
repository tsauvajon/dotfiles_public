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
}:

let
  existingSources = builtins.filter builtins.pathExists sources;
in
pkgs.runCommand name { } ''
  mkdir -p "$out"
  ${lib.concatMapStringsSep "\n" (src: ''
    if [ -d "${src}" ]; then
      find "${src}" -mindepth 1 -maxdepth 1 \
        -exec ln -sfn {} "$out/" \;
    fi
  '') existingSources}
''

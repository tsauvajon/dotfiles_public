# Wire the upstream task Home Manager module into this flake.
#
# The base config (repos_dir, wt_dir, detached_dir, editor, [[install]]
# entries shared across machines) is declared inline. Machine-local
# extras live under ~/.config/dotfiles/task.*.toml. We hand-merge them
# here because `lib.recursiveUpdate` would replace the `install` array
# wholesale; we want the public + private installs concatenated.
{
  inputs,
  lib,
  ...
}:

let
  publicInstalls = [
    { repo = "github.com/tsauvajon/goto"; }
    { repo = "github.com/tsauvajon/task"; }
    { repo = "github.com/bahdotsh/mdterm"; }
    { repo = "github.com/jrobhoward/dumap"; }
  ];

  # Read all `~/.config/dotfiles/task.*.toml` overlays and deep-merge
  # them so the upstream HM module can take a single attrset.
  privateOverlayDir = builtins.toPath (builtins.getEnv "HOME" + "/.config/dotfiles");
  overlayFiles =
    if privateOverlayDir != "/.config/dotfiles" && builtins.pathExists privateOverlayDir then
      let
        entries = builtins.readDir privateOverlayDir;
        accepted = lib.filterAttrs (
          name: type:
          (type == "regular" || type == "symlink")
          && lib.hasPrefix "task." name
          && lib.hasSuffix ".toml" name
        ) entries;
        names = lib.sort (a: b: a < b) (builtins.attrNames accepted);
      in
      map (name: privateOverlayDir + "/${name}") names
    else
      [ ];

  overlayContents = map (p: builtins.fromTOML (builtins.readFile p)) overlayFiles;
  mergedExtra = lib.foldl' lib.recursiveUpdate { } overlayContents;

  # Pull out the `install` array (if any) from each overlay and
  # concatenate, then strip it from `extraConfig` so it does not
  # collide with `installs` in the upstream HM module.
  privateInstalls = lib.concatMap (c: c.install or [ ]) overlayContents;

  # Convert TOML's snake_case `extra_flags` to the camelCase `extraFlags`
  # the upstream HM module expects.
  normalizeInstall = entry: {
    inherit (entry) repo;
  } // lib.optionalAttrs (entry ? path) { inherit (entry) path; }
    // lib.optionalAttrs (entry ? extra_flags) { extraFlags = entry.extra_flags; };

  extraConfigWithoutInstalls = builtins.removeAttrs mergedExtra [ "install" ];
in
{
  imports = [ inputs.task.homeManagerModules.default ];

  programs.task = {
    enable = true;
    reposDir = "~/dev/repos";
    wtDir = "~/dev/wt";
    detachedDir = "~/dev/detached";
    editor = "helix";
    installs = publicInstalls ++ map normalizeInstall privateInstalls;
    extraConfig = extraConfigWithoutInstalls;
  };
}

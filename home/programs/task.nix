# Wire the upstream task Home Manager module into this flake.
#
# The public base config (repos_dir, wt_dir, detached_dir, editor,
# shared [[install]] entries) lives in ../../config/task/config.toml
# so it stays editable as plain TOML. Machine-local extras live under
# ~/.config/dotfiles/task.*.toml. We hand-merge the install arrays
# here because `lib.recursiveUpdate` would replace them wholesale.
#
# We also generate shell completion files at HM build time using
# `task completions <shell>` so zsh/fish/bash all pick them up
# without sourcing the binary at every shell startup.
{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  publicConfig = builtins.fromTOML (builtins.readFile ../../config/task/config.toml);

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

  publicInstalls = publicConfig.install or [ ];
  privateInstalls = lib.concatMap (c: c.install or [ ]) overlayContents;

  # Convert TOML's snake_case `extra_flags` to the camelCase `extraFlags`
  # the upstream HM module expects.
  normalizeInstall =
    entry:
    { inherit (entry) repo; }
    // lib.optionalAttrs (entry ? path) { inherit (entry) path; }
    // lib.optionalAttrs (entry ? extra_flags) { extraFlags = entry.extra_flags; };

  extraConfigWithoutInstalls = builtins.removeAttrs mergedExtra [ "install" ];

  # Build a derivation that captures `task completions <shell>` stdout.
  # We resolve the binary off the flake input directly to avoid bouncing
  # through `config.programs.task.package`, which is only finalized
  # after the module evaluates.
  taskPkg = inputs.task.packages.${pkgs.stdenv.hostPlatform.system}.default;
  mkCompletion =
    shell:
    pkgs.runCommand "task-completion-${shell}" { } ''
      ${taskPkg}/bin/task completions ${shell} > $out
    '';
in
{
  imports = [ inputs.task.homeManagerModules.default ];

  programs.task = {
    enable = true;
    reposDir = publicConfig.repos_dir or "~/dev/repos";
    wtDir = publicConfig.wt_dir or "~/dev/wt";
    detachedDir = publicConfig.detached_dir or "~/dev/detached";
    editor = publicConfig.editor or "helix";
    installs = map normalizeInstall (publicInstalls ++ privateInstalls);
    extraConfig = extraConfigWithoutInstalls;
  };

  # Shell completions baked at HM build time. zsh autoload picks up
  # `_task` from the fpath; fish auto-loads completions/<cmd>.fish;
  # bash sources the file from ~/.bashrc.
  xdg.configFile = {
    "zsh/completions/_task".source = mkCompletion "zsh";
    "fish/completions/task.fish".source = mkCompletion "fish";
    "bash/completions/task".source = mkCompletion "bash";
  };
}

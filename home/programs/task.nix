# Wire the upstream task Home Manager module into this flake.
#
# The public base config (repos_dir, wt_dir, detached_dir, editor)
# lives in ../../config/task/config.toml so it stays editable as plain
# TOML. Machine-local extras live under ~/.config/dotfiles/task.*.toml.
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
  listFilesIn = import ../lib/list-files-in.nix { inherit lib; };

  publicConfig = builtins.fromTOML (builtins.readFile ../../config/task/config.toml);

  # The public `config.toml` is restricted to the keys consumed below;
  # arbitrary extras (e.g. a `[vscodium]` section) are only supported in
  # private overlays passed through `extraConfig`.
  recognizedPublicKeys = [
    "repos_dir"
    "wt_dir"
    "detached_dir"
    "editor"
  ];
  unknownPublicKeys = lib.subtractLists recognizedPublicKeys (builtins.attrNames publicConfig);

  # Read all `task.*.toml` overlays from the private flake's working
  # tree. `inputs.private.outPath` keeps the build pure.
  privateOverlayDir = inputs.private.outPath;
  overlayFiles = map (name: privateOverlayDir + "/${name}") (listFilesIn {
    dir = privateOverlayDir;
    predicate =
      name: type:
      (type == "regular" || type == "symlink")
      && lib.hasPrefix "task." name
      && lib.hasSuffix ".toml" name;
  });

  overlayContents = map (p: builtins.fromTOML (builtins.readFile p)) overlayFiles;
  mergedExtra = lib.foldl' lib.recursiveUpdate { } overlayContents;
  extraConfig = builtins.removeAttrs mergedExtra [ "install" ];

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
assert lib.assertMsg (unknownPublicKeys == [ ]) ''
  config/task/config.toml contains keys not propagated by home/programs/task.nix:
    ${lib.concatStringsSep ", " unknownPublicKeys}
  Move them to a private overlay (~/.config/dotfiles/task.*.toml) instead,
  or extend `recognizedPublicKeys` and the consumer below to handle them.
'';
{
  imports = [ inputs.task.homeManagerModules.default ];

  programs.task = {
    enable = true;
    reposDir = publicConfig.repos_dir or "~/dev/repos";
    wtDir = publicConfig.wt_dir or "~/dev/wt";
    detachedDir = publicConfig.detached_dir or "~/dev/detached";
    editor = publicConfig.editor or "helix";
    inherit extraConfig;
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

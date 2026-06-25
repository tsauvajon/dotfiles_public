# Per-host config for Thomas's Linux machine(s).
{ ... }:

{
  programs.fish.enable = true;

  # NVIDIA driver pin for nixGL. The hash is the sha256 of
  # NVIDIA-Linux-x86_64-<version>.run, which lets nixGL build the driver via
  # `fetchurl` (pure) instead of `builtins.fetchurl` (impure). Update `version`
  # and `hash` together from the same driver release.
  _module.args.nixglNvidia = {
    version = "610.43.02";
    hash = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM=";
  };

  home.username = "thomas";
  home.homeDirectory = "/home/thomas";

  home.stateVersion = "25.05";
}

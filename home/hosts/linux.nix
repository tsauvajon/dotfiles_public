# Per-host config for Thomas's Linux machine(s).
{ ... }:

{
  programs.fish.enable = true;

  _module.args.nixglNvidiaVersion = "610.43.02";
  # sha256 of NVIDIA-Linux-x86_64-610.43.02.run, lets nixGL build the driver
  # via `fetchurl` (pure) instead of `builtins.fetchurl` (impure). Update
  # whenever `nixglNvidiaVersion` changes.
  _module.args.nixglNvidiaHash = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM=";

  home.username = "thomas";
  home.homeDirectory = "/home/thomas";

  home.stateVersion = "25.05";
}

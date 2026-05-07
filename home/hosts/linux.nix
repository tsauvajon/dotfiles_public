# Per-host config for Thomas's Linux machine(s).
{ ... }:

{
  _module.args.nixglNvidiaVersion = "595.71.05";
  # sha256 of NVIDIA-Linux-x86_64-595.71.05.run, lets nixGL build the driver
  # via `fetchurl` (pure) instead of `builtins.fetchurl` (impure). Update
  # whenever `nixglNvidiaVersion` changes.
  _module.args.nixglNvidiaHash = "sha256-NiA7iWC35JyKQva6H1hjzeNKBek9KyS3mK8G3YRva4I=";

  home.username = "thomas";
  home.homeDirectory = "/home/thomas";

  home.stateVersion = "25.05";
}

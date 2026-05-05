# Per-host config for Thomas's Linux machine(s).
{ ... }:

{
  _module.args.nixglNvidiaVersion = "595.71.05";

  home.username = "thomas";
  home.homeDirectory = "/home/thomas";

  home.stateVersion = "25.05";
}

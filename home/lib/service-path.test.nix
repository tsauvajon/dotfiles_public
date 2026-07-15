{ lib }:

let
  servicePath = import ./service-path.nix;
  config = {
    home.homeDirectory = "/home/example";
    home.profileDirectory = "/home/example/.nix-profile";
    home.sessionPath = [ ];
  };
in
{
  testDarwinPathOmitsCurrentSystemProfile = {
    expr = servicePath {
      inherit config lib;
      pkgs.stdenv.isLinux = false;
    };
    expected = "/home/example/.local/share/mise/shims:/home/example/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/home/example/go/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  };

  testLinuxPathIncludesCurrentSystemProfile = {
    expr = servicePath {
      inherit config lib;
      pkgs.stdenv.isLinux = true;
    };
    expected = "/home/example/.local/share/mise/shims:/home/example/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/home/example/go/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin";
  };
}

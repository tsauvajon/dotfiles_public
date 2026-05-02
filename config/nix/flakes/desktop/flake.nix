{
  description = "Desktop session tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          desktop =
            if pkgs.stdenv.isLinux then
              pkgs.symlinkJoin {
                name = "dotfiles-desktop";
                paths = [ pkgs.mako ];
              }
            else
              pkgs.runCommand "dotfiles-desktop" { } ''
                mkdir -p "$out"
              '';
        in
        {
          packages = {
            inherit desktop;
            default = self.packages.${system}.desktop;
          };

          devShells.default = pkgs.mkShell {
            packages = if pkgs.stdenv.isLinux then [ pkgs.mako ] else [ ];
          };

          formatter = pkgs.nixfmt;
        }
      );
}

{
  description = "Filesystem navigation and search tools";

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
          packages = with pkgs; [
            bat
            eza
            fd
            fzf
            ripgrep
            yazi
            zoxide
          ];
        in
        {
          packages = {
            fs = pkgs.symlinkJoin {
              name = "dotfiles-fs";
              paths = packages;
            };

            default = self.packages.${system}.fs;
          };

          devShells.default = pkgs.mkShell {
            packages = packages;
          };

          formatter = pkgs.nixfmt;
        }
      );
}

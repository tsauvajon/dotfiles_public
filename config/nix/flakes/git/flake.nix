{
  description = "Git and forge CLIs";

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
            delta
            gh
            git
            glab
          ];
        in
        {
          packages = {
            git = pkgs.symlinkJoin {
              name = "dotfiles-git";
              paths = packages;
            };

            default = self.packages.${system}.git;
          };

          devShells.default = pkgs.mkShell {
            packages = packages;
          };

          formatter = pkgs.nixfmt;
        }
      );
}

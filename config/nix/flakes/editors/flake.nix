{
  description = "Editors and AI coding tools";

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
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          packages = with pkgs; [
            opencode
            vim
            vscodium
          ];
        in
        {
          packages = {
            editors = pkgs.symlinkJoin {
              name = "dotfiles-editors";
              paths = packages;
            };

            default = self.packages.${system}.editors;
          };

          devShells.default = pkgs.mkShell {
            packages = packages;
          };

          formatter = pkgs.nixfmt;
        }
      );
}

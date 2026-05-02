{
  description = "Shell and terminal workflow tools";

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
            alacritty
            asdf-vm
            (direnv.overrideAttrs { doCheck = false; })
            fish
            jq
            just
            kitty
            nix-direnv
            tmux
            zsh
            zsh-autosuggestions
            zsh-completions
          ];
        in
        {
          packages = {
            shell = pkgs.symlinkJoin {
              name = "dotfiles-shell";
              paths = packages;
            };

            default = self.packages.${system}.shell;
          };

          devShells.default = pkgs.mkShell {
            packages = packages;

            shellHook = ''
              export DEV_ROOT="''${DEV_ROOT:-$HOME/dev}"
              export PATH="$HOME/.asdf/shims:$PATH"
              echo "Dotfiles shell ready. Run: task bootstrap"
            '';
          };

          formatter = pkgs.nixfmt;
        }
      );
}

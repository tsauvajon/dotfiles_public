{
  description = "Personal dev toolchain for OpenCode + worktrees";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
          basePackages = with pkgs; [
            asdf-vm
            cargo
            clippy
	    delta
            direnv
            fd
            fish
            fzf
            gh
            git
            jq
            just
            nix-direnv
            opencode
            ripgrep
            rust-analyzer
            rustc
            rustfmt
            sccache
            tmux
            vim
            vscodium
            zoxide
          ] ++ (if pkgs.stdenv.isLinux then [ pkgs.mako ] else [ ]);
        in
        {
          packages = {
            toolchain = pkgs.symlinkJoin {
              name = "dotfiles-toolchain";
              paths = basePackages;
            };

            default = self.packages.${system}.toolchain;
          };

          devShells.default = pkgs.mkShell {
            packages = basePackages;

            shellHook = ''
              export DEV_ROOT="''${DEV_ROOT:-$HOME/dev}"
              export PATH="$HOME/.asdf/shims:$PATH"
              echo "Dotfiles dev shell ready. Run: task bootstrap"
            '';
          };

          formatter = pkgs.nixfmt-rfc-style;
        }
      );
}

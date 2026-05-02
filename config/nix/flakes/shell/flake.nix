{
  description = "Shell and terminal workflow tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl.url = "github:nix-community/nixGL";
    nixgl-nixpkgs.url = "github:nixos/nixpkgs/93e8cdce7afc64297cfec447c311470788131cd9";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixgl,
      nixgl-nixpkgs,
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
          nvidiaVersion = builtins.getEnv "NIXGL_NVIDIA_VERSION";
          nixglPkgs = import nixgl {
            pkgs = import nixgl-nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
            nvidiaVersion = if nvidiaVersion == "" then null else nvidiaVersion;
            enable32bits = system == "x86_64-linux";
            enableIntelX86Extensions = system == "x86_64-linux";
          };
          nixglLauncher =
            if nvidiaVersion == "" then
              "${nixglPkgs.nixGLIntel}/bin/nixGLIntel"
            else
              "${nixglPkgs.auto.nixGLDefault}/bin/nixGL";
          wrapWithNixGL =
            package: binary:
            if pkgs.stdenv.isLinux then
              pkgs.symlinkJoin {
                name = "${package.pname or binary}-nixgl";
                paths = [ package ];
                nativeBuildInputs = [ pkgs.makeWrapper ];
                postBuild = ''
                  rm "$out/bin/${binary}"
                  makeWrapper ${pkgs.writeShellScript "${binary}-nixgl-launcher" ''
                    exec ${nixglLauncher} ${package}/bin/${binary} "$@"
                  ''} "$out/bin/${binary}"
                '';
              }
            else
              package;
          packages = with pkgs; [
            (wrapWithNixGL alacritty "alacritty")
            asdf-vm
            (direnv.overrideAttrs { doCheck = false; })
            fish
            jq
            just
            (wrapWithNixGL kitty "kitty")
            nix-direnv
            tmux
            zellij
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

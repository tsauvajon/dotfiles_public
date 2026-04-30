{
  description = "Helix language servers, formatters, and debuggers";

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

          languageTools = with pkgs; [
            bash-language-server
            delve
            docker-compose-language-service
            dockerfmt
            docker-language-server
            dockerfile-language-server
            eslint_d
            fish-lsp
            gitlab-ci-ls
            golangci-lint
            golangci-lint-langserver
            gopls
            harper
            helm-ls
            llvmPackages.lldb
            marksman
            nil
            nixfmt
            prettier
            ruff
            shellcheck
            shfmt
            taplo
            terraform-ls
            ty
            typescript
            typescript-language-server
            vscode-js-debug
            vscode-langservers-extracted
            yaml-language-server
            yamlfmt
          ];
        in
        {
          packages = {
            helix-langs = pkgs.symlinkJoin {
              name = "helix-language-tools";
              paths = languageTools;
            };

            default = self.packages.${system}.helix-langs;
          };

          devShells.default = pkgs.mkShell {
            packages = languageTools;
          };

          formatter = pkgs.nixfmt;
        }
      );
}

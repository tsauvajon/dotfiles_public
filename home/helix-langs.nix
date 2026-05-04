# Helix language servers, formatters, and debuggers.
# Mirrors config/nix/flakes/helix-langs/flake.nix.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
}

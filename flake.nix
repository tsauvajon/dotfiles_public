{
  description = "Thomas's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixGL pinned alongside a known-good nixpkgs commit. The pin matches
    # the existing config/nix/flakes/shell setup; touching it will likely
    # break OpenGL on Linux.
    nixgl.url = "github:nix-community/nixGL";
    nixgl-nixpkgs.url = "github:nixos/nixpkgs/93e8cdce7afc64297cfec447c311470788131cd9";

    # Helix Steel and pinned plugin sources, mirroring
    # config/nix/flakes/helix-plugins/flake.nix.
    helix-steel = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    steel = {
      url = "github:mattwparas/steel/605d490c07ae6937d532d5a994920b4dab3016ad";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scooter-hx = {
      url = "github:thomasschafer/scooter.hx/v0.1.4";
      flake = false;
    };
    fake-warp-hx = {
      url = "github:Xerxes-2/fake-warp.hx/542214f6359880c70663e3e58e0d1c5fda10d328";
      flake = false;
    };
    smooth-scroll-hx = {
      url = "github:thomasschafer/smooth-scroll.hx/1ed8b088e465fb139389c36ad158ba4a2d9e1bbc";
      flake = false;
    };
    helix-file-watcher = {
      url = "github:mattwparas/helix-file-watcher/e36434634b0a862280dc832921c9aa0d62198964";
      flake = false;
    };

    # Private overlay flake: machine-local secrets, identity, and private
    # OpenCode commands/skills/agents/plugins/rules.
    #
    # The path resolves at flake-eval time via `--impure` because it lives
    # outside the repo. Phase 1 declares the input but no module consumes
    # it yet; Phase 3 will start using it for the OpenCode merges.
    private = {
      url = "path:/Users/thomas/.config/dotfiles";
      flake = true;
    };

    # Phase 5: consume goto and task as upstream flakes that expose
    # their own homeManagerModules.
    goto = {
      url = "github:tsauvajon/goto";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    task = {
      url = "github:tsauvajon/task";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    # Phase 8: catppuccin theme content sourced from upstream flakes
    # so the ./config/<tool>/catppuccin/ submodules can be retired.
    # The catppuccin/nix metaflake covers most tools; fzf and zellij
    # are not in the metaflake, so we pin their source repos directly.
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin-fzf = {
      url = "github:catppuccin/fzf";
      flake = false;
    };
    catppuccin-zellij = {
      url = "github:catppuccin/zellij";
      flake = false;
    };
    catppuccin-yazi = {
      url = "github:catppuccin/yazi";
      flake = false;
    };
    catppuccin-bat = {
      url = "github:catppuccin/bat";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      home-manager,
      rust-overlay,
      ...
    }:
    let
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ rust-overlay.overlays.default ];
        };

      # Resolve the live dotfiles repo path for use inside HM modules.
      # Tries `$DOTFILES` (set by setup.sh) first, then `~/.config/dotfiles/path`
      # (recorded by the Rust setup tool on first run). Both are used by the
      # Rust tool today; either is enough to cover typical cases.
      dotfilesRoot =
        let
          fromEnv = builtins.getEnv "DOTFILES";
          home = builtins.getEnv "HOME";
          pathFile = "${home}/.config/dotfiles/path";
          fromFile =
            if home != "" && builtins.pathExists pathFile then
              builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile pathFile)
            else
              "";
        in
        if fromEnv != "" then
          fromEnv
        else if fromFile != "" then
          fromFile
        else
          throw ''
            Could not determine the dotfiles repo path.
            Set $DOTFILES (e.g. by running setup.sh) or write the path to
            ~/.config/dotfiles/path.
          '';

      mkHome =
        {
          system,
          hostModule,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = { inherit inputs system dotfilesRoot; };
          modules = [
            ./home
            hostModule
          ];
        };
    in
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          formatter = pkgs.nixfmt-rfc-style;
        }
      )
    // {
      homeConfigurations = {
        thomas-darwin = mkHome {
          system = "aarch64-darwin";
          hostModule = ./home/hosts/darwin.nix;
        };
        thomas-linux = mkHome {
          system = "x86_64-linux";
          hostModule = ./home/hosts/linux.nix;
        };
      };
    };
}

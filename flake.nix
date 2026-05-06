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

    # nixGL pinned alongside a known-good nixpkgs commit. Touching the
    # pin will likely break OpenGL on Linux.
    nixgl.url = "github:nix-community/nixGL";
    nixgl-nixpkgs.url = "github:nixos/nixpkgs/93e8cdce7afc64297cfec447c311470788131cd9";

    # Helix Steel and pinned plugin sources.
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
    # Uses a pure placeholder by default; override at build time with:
    #   --override-input private ~/.config/dotfiles
    private = {
      url = "path:./private-placeholder";
      flake = true;
    };

    # goto and task are consumed as upstream flakes that expose their
    # own homeManagerModules.
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

    # Catppuccin theme content sourced from upstream flakes. The
    # catppuccin/nix metaflake covers most tools; fzf and zellij are
    # not in the metaflake, so we pin their source repos directly.
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

      # The dotfiles repo root is the directory containing this flake.
      # Pure: no env-var lookups, so --impure is not required.
      dotfilesRoot = ./.;

      mkHome =
        {
          system,
          hostModule,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = { inherit inputs system dotfilesRoot; };
          # The trailing list lets the private overlay contribute
          # extra HM modules without committing their content here.
          # Defaults to [] when the overlay is the placeholder.
          modules = [
            ./home
            hostModule
          ] ++ (inputs.private.homeModules or [ ]);
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

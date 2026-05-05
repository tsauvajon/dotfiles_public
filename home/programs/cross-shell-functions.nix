# Cross-shell function codegen.
#
# Some helpers MUST be shell functions because they manipulate the
# caller's shell state (cwd, history) or wrap a shell builtin. We
# can't promote them to PATH scripts (those run in subshells and
# can't `cd` the caller).
#
# Define each function once with `zshBody` and `fishBody` and this
# module emits per-shell function files:
#
#   ~/.config/zsh/functions/<name>.zsh        (sourced from zshrc)
#   ~/.config/fish/functions/<name>.fish      (auto-loaded by fish)
#
# Bodies stay per-shell because zsh and fish syntax differs (e.g.
# `$@` vs `$argv`, `$(...)` vs `(...)`). The contract is "same name,
# same observable behaviour".
{ config, lib, ... }:

let
  cfg = config.programs.crossShellFunctions;

  banner = format: ''
    # ============================================================
    # GENERATED FILE — do not edit by hand.
    # Source: home/programs/cross-shell-functions.nix in the dotfiles
    # repo. Edit the `programs.crossShellFunctions` attrset and rerun
    # setup.sh to regenerate. (${format} side)
    # ============================================================
  '';

  # Indent every body line by 2 spaces for readability inside the
  # generated function block. Strip a single trailing newline before
  # splitting so we don't emit a final whitespace-only line ("  ")
  # right before the closing brace/`end`. Empty lines in the body stay
  # empty (rather than becoming "  ") to avoid trailing whitespace.
  indent =
    body:
    let
      trimmed = lib.removeSuffix "\n" body;
      lines = lib.splitString "\n" trimmed;
    in
    lib.concatMapStringsSep "\n" (line: if line == "" then "" else "  ${line}") lines;

  zshFile = name: spec: {
    name = "zsh/functions/${name}.zsh";
    value.text = ''
      ${banner "zsh"}
      ${name}() {
      ${indent spec.zshBody}
      }
    '';
  };

  fishFile = name: spec: {
    name = "fish/functions/${name}.fish";
    value.text = ''
      ${banner "fish"}
      function ${name}${
        lib.optionalString (spec.description != "") " --description '${spec.description}'"
      }
      ${indent spec.fishBody}
      end
    '';
  };

  zshFiles = lib.mapAttrs' zshFile cfg;
  fishFiles = lib.mapAttrs' fishFile cfg;

  # Init snippet that zshrc sources to load every generated function.
  zshLoaderText = ''
    # ============================================================
    # GENERATED FILE — do not edit by hand.
    # Source: home/programs/cross-shell-functions.nix.
    # ============================================================
    for _f in ~/.config/zsh/functions/*.zsh; do
      [ -r "$_f" ] && source "$_f"
    done
    unset _f
  '';

  functionType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description (used by fish --description).";
      };
      zshBody = lib.mkOption {
        type = lib.types.str;
        description = "Function body in zsh syntax (no enclosing braces).";
      };
      fishBody = lib.mkOption {
        type = lib.types.str;
        description = "Function body in fish syntax (no enclosing function/end).";
      };
    };
  };
in
{
  options.programs.crossShellFunctions = lib.mkOption {
    type = lib.types.attrsOf functionType;
    default = { };
    description = ''
      Cross-shell functions. Each entry produces a per-shell file at
      ~/.config/zsh/functions/<name>.zsh and
      ~/.config/fish/functions/<name>.fish.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    xdg.configFile =
      zshFiles
      // fishFiles
      // {
        "zsh/common-functions.zsh".text = zshLoaderText;
      };
  };
}

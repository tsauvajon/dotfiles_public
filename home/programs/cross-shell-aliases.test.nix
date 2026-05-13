{ lib }:

let
  evalConfig =
    moduleConfig:
    (lib.evalModules {
      modules = [
        (
          { lib, ... }:
          {
            options.assertions = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [ ];
            };

            options.xdg.configFile = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.text = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                  };
                }
              );
              default = { };
            };
          }
        )
        ./cross-shell-aliases.nix
        moduleConfig
      ];
    }).config;

  config = evalConfig {
    programs.crossShellAliases = {
      aliases = {
        c = "cargo";
        cat = "bat";
        g = "git";
        ls = "eza -al";
        oc = "opencode";
      };
      fishAbbreviations = [ "c" ];
      fishCompletionWraps = {
        oc = "opencode";
      };
      replacementNotices = {
        cat = "bat";
        ls = "eza";
      };
    };
  };

  zshText = config.xdg.configFile."zsh/common-aliases.zsh".text;
  fishText = config.xdg.configFile."fish/conf.d/common-aliases.fish".text;
in
{
  testZshReplacementNoticeUsesFunction = {
    expr = lib.hasInfix ''
      cat() {
        printf '%s\n' 'dotfiles: cat is configured as bat' >&2
        bat "$@"
      }
    '' zshText;
    expected = true;
  };

  testZshReplacementClearsExistingAlias = {
    expr = lib.hasInfix "unalias ls 2>/dev/null || true" zshText;
    expected = true;
  };

  testFishReplacementNoticeUsesFunction = {
    expr = lib.hasInfix ''
      function ls --description 'ls replacement via eza'
        printf '%s\n' 'dotfiles: ls is configured as eza' >&2
        eza -al $argv
      end
    '' fishText;
    expected = true;
  };

  testRegularAliasesRemainAliases = {
    expr = (lib.hasInfix "alias g=git" zshText) && (lib.hasInfix "alias g git" fishText);
    expected = true;
  };

  testFishAbbreviationsRemainAbbreviations = {
    expr = lib.hasInfix "abbr --add -- c cargo" fishText;
    expected = true;
  };

  testFishCompletionWrapsEraseBuiltins = {
    expr = lib.hasInfix ''
      complete --erase --command oc
      complete --command oc --wraps opencode
    '' fishText;
    expected = true;
  };
}

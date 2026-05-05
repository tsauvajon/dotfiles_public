{
  description = "Placeholder for private dotfiles flake. Override with --override-input private /path/to/private/config";

  outputs = { self, ... }: {
    # Git identity (used by home/programs/git.nix)
    git = {
      name = "";
      email = "";
      signingKey = "";
    };

    # Goto config (used by home/programs/goto.nix)
    goto = {
      apiUrl = "";
      bookmarksFile = "";
    };

    # OpenCode private paths (used by home/opencode.nix)
    # Expose paths to empty dirs so merge helpers succeed.
    opencode = {
      commandsDir = self + "/opencode/commands";
      skillsDir = self + "/opencode/skills";
      agentsDir = self + "/opencode/agents";
      pluginsDir = self + "/opencode/plugins";
      configFile = self + "/opencode/opencode.json";
      packageFile = self + "/opencode/package.json";
      rulesDir = self + "/opencode/rules";
    };
  };
}

# Per-host config for Thomas's macOS machine.
{ ... }:

{
  home.username = "thomas";
  home.homeDirectory = "/Users/thomas";

  # The HM state version. Pin to the release used at first activation;
  # do not bump unless you have read the HM release notes for that
  # version's migration steps.
  home.stateVersion = "25.05";

  # Mirrors the existing `rules_mode = "private_only"` in
  # ~/.config/dotfiles/config.toml — only the private rules overlays
  # in ~/.config/dotfiles/opencode/rules/ feed into AGENTS.md.
  programs.opencode.rulesMode = "private_only";
}

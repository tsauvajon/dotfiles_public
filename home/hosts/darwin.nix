# Per-host config for Thomas's macOS machine.
{ ... }:

{
  home.username = "thomas";
  home.homeDirectory = "/Users/thomas";

  # The HM state version. Pin to the release used at first activation;
  # do not bump unless you have read the HM release notes for that
  # version's migration steps.
  home.stateVersion = "25.05";

  # Use the cross-source merge: public rules in
  # config/opencode/rules/ and private rules in
  # ~/.config/dotfiles/opencode/rules/ are sorted together by
  # filename to build AGENTS.md (private wins on collision).
  programs.opencode.rulesMode = "merged";
}

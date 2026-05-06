{
  description = "Placeholder for private dotfiles flake. Override with --override-input private /path/to/private/config";

  # The Home Manager modules under home/ access fields on this flake
  # defensively (`inputs.private.<x> or { }`), so the placeholder can
  # be a bare `outputs` attrset. The build will still throw in
  # home/programs/git.nix because no git identity is set — that is
  # intentional: dev-mode evaluation surfaces the missing override.
  outputs = { self, ... }: { };
}

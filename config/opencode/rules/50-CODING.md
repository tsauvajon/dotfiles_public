# Coding Baseline

- For non-trivial design, implementation, refactors, debugging, or testing work, load the `coding-workflow` skill.
- If a required CLI is unavailable after checking the repository's declared tooling, use `nix run nixpkgs#<package> -- <args>` as an ephemeral fallback instead of installing it globally; for example, `nix run nixpkgs#hadolint -- Dockerfile`.

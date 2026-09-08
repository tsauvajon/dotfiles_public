{ pkgs }:

(import ./bun-plugin-test.nix { inherit pkgs; }) {
  name = "git-signing";
  helpers = [
    "signingPrivateKeyPath"
    "signingConfigEntries"
    "existingSigningKey"
    "gitSigningEnv"
  ];
}

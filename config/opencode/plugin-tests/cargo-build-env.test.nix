{ pkgs }:

(import ./bun-plugin-test.nix { inherit pkgs; }) {
  name = "cargo-build-env";
  helpers = [
    "commandPath"
    "isCacheWrapperValue"
    "isKacheWrapperValue"
    "rustCacheEnv"
  ];
}

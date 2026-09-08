{ pkgs }:

(import ./bun-plugin-test.nix { inherit pkgs; }) {
  name = "primary-context";
  helpers = [
    "isRootSession"
    "primaryContextPath"
    "readPrimaryContext"
  ];
}

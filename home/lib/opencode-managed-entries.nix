{ lib }:

fileDeclarations:

lib.unique (
  map (path: lib.head (lib.splitString "/" (lib.removePrefix "opencode/" path))) (
    builtins.attrNames fileDeclarations
  )
)

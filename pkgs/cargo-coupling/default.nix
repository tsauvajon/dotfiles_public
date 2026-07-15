{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "cargo-coupling";
  version = "0.3.7";

  src = fetchFromGitHub {
    owner = "nwiizo";
    repo = "cargo-coupling";
    rev = "v${version}";
    hash = "sha256-lIgtOVCgUiB319RwNF1G3UHCX7dl65F3VTnF8gLe8sE=";
  };

  cargoHash = "sha256-UQCneddJgqziw+vaSLKkaOC+hthjQzYyLWMZTsnsKVc=";
  doCheck = false;

  meta = {
    description = "Coupling analysis tool for Rust projects";
    homepage = "https://github.com/nwiizo/cargo-coupling";
    license = lib.licenses.mit;
    mainProgram = "cargo-coupling";
    platforms = lib.platforms.unix;
  };
}

{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "cargo-coupling";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "nwiizo";
    repo = "cargo-coupling";
    rev = "v${version}";
    hash = "sha256-hOYQ2oA2Y7rRCISy3e/08zB7kDqDOqGyF2FsEBFCiIo=";
  };

  cargoHash = "sha256-Az3XGaJ4eDWjiejVICBquXafCOet+cohDZM0GhuYHms=";
  doCheck = false;

  meta = {
    description = "Coupling analysis tool for Rust projects";
    homepage = "https://github.com/nwiizo/cargo-coupling";
    license = lib.licenses.mit;
    mainProgram = "cargo-coupling";
    platforms = lib.platforms.unix;
  };
}

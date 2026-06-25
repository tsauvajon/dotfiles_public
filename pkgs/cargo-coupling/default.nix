{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "cargo-coupling";
  version = "0.3.3";

  src = fetchFromGitHub {
    owner = "nwiizo";
    repo = "cargo-coupling";
    rev = "v${version}";
    hash = "sha256-H0z2agodJ9Kzky9h2Gsu4UbdGCIyIxEkKt2cu169ASw=";
  };

  cargoHash = "sha256-wuRDej0GzdRrmAHNzImauCmywATULsykDJFuJjewiBs=";
  doCheck = false;

  meta = {
    description = "Coupling analysis tool for Rust projects";
    homepage = "https://github.com/nwiizo/cargo-coupling";
    license = lib.licenses.mit;
    mainProgram = "cargo-coupling";
    platforms = lib.platforms.unix;
  };
}

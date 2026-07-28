{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "cargo-coupling";
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "nwiizo";
    repo = "cargo-coupling";
    rev = "v${version}";
    hash = "sha256-W4S0Hw673guNaSCkJ7HjQz2lQS5N/L4cZVHjlOYJCpM=";
  };

  cargoHash = "sha256-lHwg3e+ZsO/hjxT1wc7uKKtmqzzjVLCr/Ig6Uew8MPc=";
  doCheck = false;

  meta = {
    description = "Coupling analysis tool for Rust projects";
    homepage = "https://github.com/nwiizo/cargo-coupling";
    license = lib.licenses.mit;
    mainProgram = "cargo-coupling";
    platforms = lib.platforms.unix;
  };
}

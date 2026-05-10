{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  stdenv,
}:

rustPlatform.buildRustPackage rec {
  pname = "glim";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "junkdog";
    repo = "glim";
    rev = "glim-v${version}";
    hash = "sha256-m5ZHXEu06kyCGqHBvcBgdgbi6gjHtegWrE1tDnMHyFg=";
  };

  cargoHash = "sha256-4NJtGqKOUWyv1ZcrQqqZgGI8vzSZpRfcVJWI7TKZCi8=";
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = lib.optionals stdenv.isLinux [ openssl ];

  meta = {
    description = "TUI for monitoring GitLab CI/CD pipelines and projects";
    homepage = "https://github.com/junkdog/glim";
    license = lib.licenses.mit;
    mainProgram = "glim";
    platforms = lib.platforms.unix;
  };
}

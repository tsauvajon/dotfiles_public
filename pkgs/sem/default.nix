{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-J0swVxM+8kyHQIf3PNfrOjzisCJthKC1OK5P+eLJ1kI=";
  };

  sourceRoot = "${src.name}/crates";

  cargoHash = "sha256-BG44++uZ3iWLMhluhaNpIePt3E36ZK1NoYSxpPvokkg=";
  cargoBuildFlags = [
    "--package"
    "sem-cli"
  ];
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = {
    description = "Semantic version control for code entities";
    homepage = "https://github.com/Ataraxy-Labs/sem";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "sem";
    platforms = lib.platforms.unix;
  };
}

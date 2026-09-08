{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  version = "0.24.0";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-yDIRlLL83JZbVHCrrsMMkxB9RL7JWjDw9PRGcok1gnw=";
  };

  sourceRoot = "${src.name}/crates";

  cargoHash = "sha256-3kYCMlZOuQp0ykQ5afDelkIJCfscoACuDKyFQdbxPHo=";
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

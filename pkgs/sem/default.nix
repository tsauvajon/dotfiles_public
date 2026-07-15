{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  version = "0.21.0";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-3lAcIxNM/4IFSj+7rMOjXsLZiIcAC4EESJBzWYkuDK0=";
  };

  sourceRoot = "${src.name}/crates";

  cargoHash = "sha256-0/nTkOrGIWDJ3b1LbcIjR4yIZ8s/e5CcbgJ4m1AfxBs=";
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

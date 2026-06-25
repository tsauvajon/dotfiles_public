{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-HGyZo6Ee5fkPR77eFqRDbzZEuW73mNwlzNRuQMeoxkA=";
  };

  sourceRoot = "${src.name}/crates";

  cargoHash = "sha256-dQJNFc3/8rXhqP26C3Glf/LrIcbN5uS39d7FmreoCNk=";
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

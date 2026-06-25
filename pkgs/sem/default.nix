{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  version = "0.14.1";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-erTyUSzK7Q9eW0NnhDZgnzLq+KdQGVpXB7ZHhpZ8yyU=";
  };

  sourceRoot = "${src.name}/crates";

  cargoHash = "sha256-iNlR24RGjBL4RsMlL10ymc8VjaZxb+vlRAdSwu04VcA=";
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

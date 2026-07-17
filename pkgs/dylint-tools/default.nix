{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "dylint-tools";
  version = "6.0.0";

  src = fetchFromGitHub {
    owner = "trailofbits";
    repo = "dylint";
    rev = "v${version}";
    hash = "sha256-hoavNSVwaPpA+EtvRw2ukQ2KKg1d9AF7oNCy0mnxKdo=";
  };

  cargoHash = "sha256-WiXf8twRfU7w1b8o0EeZJdCLuXKier41z4ZnzoEUmDQ=";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];
  DOCS_RS = "1";
  OPENSSL_INCLUDE_DIR = "${lib.getDev openssl}/include";
  OPENSSL_LIB_DIR = "${lib.getLib openssl}/lib";
  cargoBuildFlags = [
    "-p"
    "cargo-dylint"
    "-p"
    "dylint-link"
  ];
  doCheck = false;

  installPhase = ''
    runHook preInstall
    target_root="''${CARGO_TARGET_DIR:-target}"
    target_dir=""
    for candidate in "$target_root"/*/release/cargo-dylint "$target_root"/release/cargo-dylint; do
      if [ -x "$candidate" ]; then
        target_dir="$(dirname "$candidate")"
        break
      fi
    done
    if [ -z "$target_dir" ]; then
      echo "cargo-dylint binary was not found under $target_root" >&2
      exit 1
    fi
    install -Dm755 "$target_dir/cargo-dylint" -t "$out/bin"
    install -Dm755 "$target_dir/dylint-link" -t "$out/bin"
    runHook postInstall
  '';

  meta = {
    description = "cargo-dylint and dylint-link from Trail of Bits Dylint";
    homepage = "https://github.com/trailofbits/dylint";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}

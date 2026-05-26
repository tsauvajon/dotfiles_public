{
  lib,
  rustPlatform,
  apple-sdk_15,
  stdenv,
  src,
}:

rustPlatform.buildRustPackage {
  pname = "kache";
  version = "0.3.1";

  inherit src;

  cargoHash = "sha256-s61zrPFP+BdtHj0vGic8LDGBuR6vydPWksKvRXtd1cI=";

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
  ];

  checkFlags = lib.optionals stdenv.hostPlatform.isDarwin [
    "--skip=store::tests::test_exclude_from_indexing_sets_tmutil_xattr"
  ];

  env.RUSTC_WRAPPER = "";

  meta = {
    description = "Zero-copy, content-addressed Rust build cache";
    homepage = "https://github.com/kunobi-ninja/kache";
    license = lib.licenses.asl20;
    mainProgram = "kache";
    platforms = lib.platforms.unix;
  };
}

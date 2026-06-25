{
  lib,
  rustPlatform,
  fetchCrate,
}:

rustPlatform.buildRustPackage rec {
  pname = "dumap";
  version = "1.1.0";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-xoxiuokBDUEgycuK3WMCDsXPkEj96nqi6YPbnND9GS4=";
  };

  cargoHash = "sha256-gnp2ycY1vRAi7tTsvR2BQ8Ys6Kayt8GbDr68CpwjUGs=";
  doCheck = false;

  meta = {
    description = "Interactive disk usage treemap visualizer";
    homepage = "https://github.com/jrobhoward/dumap";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "dumap";
    platforms = lib.platforms.unix;
  };
}

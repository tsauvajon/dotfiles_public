{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.3.6";
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      cliHash = "sha256-HKSXj9RQkCLPdOi9euTPFAKMbfGyEw4ch2E4BImW9Tc=";
      driverHash = "sha256-fc/OJY16pWLAAoc4facLw+IshqzC5SFDF+xre6uS2FY=";
      mcpHash = "sha256-QnYqggwFuFUVJODtA6jmlnsRsu00roOezu/1F8DcnVs=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      cliHash = "sha256-3ZniXl5f0HLj7JdtwWRWZCz02zFiuzZeTbXLUBuVCgo=";
      driverHash = "sha256-Y0lFdP8XZKCM2gCM0KMihL35OpBKoBcb8umGD1Xx58I=";
      mcpHash = "sha256-PZNtKnlQQwvqlNlCKWCamVeL9yK0v5/4tyijnZle2D0=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      cliHash = "sha256-Ny194xZtPOJ+UTGMEvVzQzoMhjCThywv8qz0L4okf4I=";
      driverHash = "sha256-tjbDjUOic3bd85xOSNqkJ74fhVvMva/ERJY+dUAgZ3M=";
      mcpHash = "sha256-UBPG0w2DpuEJnTKSjx52KjQSjnZS1K3VJf4mwesL934=";
    };
  };
  asset =
    assets.${stdenvNoCC.hostPlatform.system}
      or (throw "weave: unsupported system ${stdenvNoCC.hostPlatform.system}");
  fetchAsset =
    name: hash:
    fetchurl {
      url = "https://github.com/Ataraxy-Labs/weave/releases/download/v${version}/${name}-${asset.target}.tar.gz";
      inherit hash;
    };
in
stdenvNoCC.mkDerivation {
  pname = "weave";
  inherit version;

  srcs = [
    (fetchAsset "weave-cli" asset.cliHash)
    (fetchAsset "weave-driver" asset.driverHash)
    (fetchAsset "weave-mcp" asset.mcpHash)
  ];

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 weave "$out/bin/weave"
    install -Dm755 weave-driver "$out/bin/weave-driver"
    install -Dm755 weave-mcp "$out/bin/weave-mcp"

    runHook postInstall
  '';

  # Linux release assets are dynamically-linked GNU binaries. They need the FHS
  # loader path (/lib64/ld-linux-*) that is absent in the Nix build sandbox.
  doInstallCheck = stdenvNoCC.hostPlatform.isDarwin;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/weave" --version || "$out/bin/weave" --help

    runHook postInstallCheck
  '';

  meta = {
    description = "Entity-aware Git merge driver for reducing code conflicts";
    homepage = "https://github.com/Ataraxy-Labs/weave";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "weave";
    platforms = builtins.attrNames assets;
  };
}

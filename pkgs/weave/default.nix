{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.3.4";
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      cliHash = "sha256-IbELRtqQDmLAIhd78ruZQTlf9AILZBtTMY1dIf52Rh0=";
      driverHash = "sha256-9c7VpdUzPnYlZdPUs0Nv3PA+PTW/EmBJqqCL+nUMxck=";
      mcpHash = "sha256-qVxHSW6Oj6ELA58tTlsxPCUs+JrWn83gI7qCAcCOSnE=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      cliHash = "sha256-V/X/gUlHbNfHfJ1YRw8GX3XIbXD867fAe7NWwqNLats=";
      driverHash = "sha256-6NHjq8MuL9qKB3sE9tfnSS8Vs/ExnsIG8VI7VnhAWK4=";
      mcpHash = "sha256-GLlYJjzik2xgeIgQ7LHVTkJebAhMuupzxMryLwxAN/g=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      cliHash = "sha256-nWkLmsl4X97VDkx1fgErqpvEeghBxtqWOR1JRopjF+E=";
      driverHash = "sha256-l1oPSUJVHFR9x+AEOjwKivm9Fl/1bpWlEK7dQiCllXQ=";
      mcpHash = "sha256-PmphAZvmubdoRZsL0g0j3kGu467LIsovzZEzhsPijTU=";
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

  meta = {
    description = "Entity-aware Git merge driver for reducing code conflicts";
    homepage = "https://github.com/Ataraxy-Labs/weave";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "weave";
    platforms = builtins.attrNames assets;
  };
}

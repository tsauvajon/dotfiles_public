{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.5.4";
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      cliHash = "sha256-bogOt6A4+9I8Lo33vU3tF+6cBPvx7fyLbQM2RHmwnYc=";
      driverHash = "sha256-4kSXyo563hKH0ZhtSa5EoSiY0x7Go+a/NpjllGKdE8I=";
      mcpHash = "sha256-+9wk9HtGuBkDwlmVNHQLIWwmFHRoz5G/Cffi2EcDj+M=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      cliHash = "sha256-YCXqjhmw0ldYN+Hu8uskKoZCX0QUyBpllvlH7EbI0IA=";
      driverHash = "sha256-Gjwu8V1I3MRyKhwnbvlTIRwvjF573O2QrHKeBWRFy9s=";
      mcpHash = "sha256-BjUPOlS6I3U5o4niAZu9FODFM2kbVAhpEOs0XIg/iBM=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      cliHash = "sha256-k7n6A+cUr4CR9MKKhse6gNmAPVoH0ZbEYBlgrVFCbfw=";
      driverHash = "sha256-gjaT7IM73+HZlRLtN/9YBHwWqoF0FsZFDiOfzd69BQM=";
      mcpHash = "sha256-0LvahQvkrAIHtUalyCCpUD1WjR8HU82JwnMmLTQbZE4=";
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

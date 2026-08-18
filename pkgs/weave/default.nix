{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.5.1";
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      cliHash = "sha256-C/QcpfiWGw2f2ZeyMDL4K3Db1uT0ZjO4lrAjeiUnEng=";
      driverHash = "sha256-hn+X5FTiI9hOWD+Ba21lD40NSNhzrCAG5RdDKjSt2W4=";
      mcpHash = "sha256-fMSYfj2vJXohOG6eC0wVzLhnLKqSpInr3xKFr72ZzP0=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      cliHash = "sha256-GozT3FZ31N6NyyiUhwzx+CjvF9h64rHve1U4wogVSZk=";
      driverHash = "sha256-Gzt7CfOHxHjjseRD8Og2IjrzorgABrhZN6YSoLBOdW4=";
      mcpHash = "sha256-HI8DulrzepUz94+oN2eRHc2a/Uj790JMlUQMgU46Lr8=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      cliHash = "sha256-Y6aLAeredco0fRzI2wJEoRzzZGvnc0HGmirfeCI/xr0=";
      driverHash = "sha256-CytlzsS5RSd12uFAPMhNB8tp2ktVNv34zNL/yVF3F9s=";
      mcpHash = "sha256-KuCZC3Gir+CFNChv9/OGQILGyxWKavqCXm/cgbMngW4=";
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

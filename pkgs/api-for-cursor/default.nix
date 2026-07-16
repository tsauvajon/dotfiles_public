{
  apple-sdk,
  bridgeMaxJsonBytes ? 16 * 1024 * 1024,
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  lib,
  libicns,
  nodejs_22,
  swift,
  swiftPackages,
  swiftpm,
  swiftpm2nix,
}:

assert lib.assertMsg (
  builtins.isInt bridgeMaxJsonBytes && bridgeMaxJsonBytes > 0
) "api-for-cursor: bridgeMaxJsonBytes must be a positive integer";

let
  version = "0.1.10";
  build = "13";

  src = fetchFromGitHub {
    # Unreleased lifecycle fix from https://github.com/standardagents/composer-api/pull/27.
    owner = "wbugitlab1";
    repo = "composer-api";
    rev = "5a0bb719e40529d6182371f48ef2578e4542ea15";
    hash = "sha256-IikBnUOOvRbYWgMeYNJJzrPxvwcZTrfcJ/E+tglfjU8=";
  };

  generated = swiftpm2nix.helpers ./generated;

  sparkleArtifact = fetchzip {
    url = "https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-for-Swift-Package-Manager.zip";
    hash = "sha256-g+vxuoB0CLQAlzKoEOOc6ALr7ep1umllXLdZWwyvkpw=";
    stripRoot = false;
  };

  nodeModules = buildNpmPackage {
    pname = "api-for-cursor-node-modules";
    inherit version src;

    npmDepsHash = "sha256-iVR27o1hxma3IQZ9fuJ5NmfhPcMG10NmDADWV++wX+w=";
    npmInstallFlags = [ "--omit=dev" ];

    dontNpmBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R package.json package-lock.json node_modules "$out/"

      runHook postInstall
    '';
  };
in
swiftPackages.stdenv.mkDerivation {
  pname = "api-for-cursor";
  inherit version src;

  patches = [ ./bridge-request-size.patch ];

  nativeBuildInputs = [
    nodejs_22
    libicns
    swift
    swiftpm
  ];

  buildInputs = [ apple-sdk ];

  postPatch = ''
    substituteInPlace scripts/cursor-sdk-local-agent-bridge.mjs \
      --replace-fail '@bridgeMaxJsonBytes@' '${toString bridgeMaxJsonBytes}'
    substituteInPlace macos/CursorAPI/Package.swift \
      --replace-fail "// swift-tools-version: 6.0" "// swift-tools-version: 5.10"
    substituteInPlace macos/CursorAPI/Sources/CursorAPICore/CursorSDKBridgeServer.swift \
      --replace-fail '        ].compactMap(\.self)' '        ].compactMap { $0 }'
    substituteInPlace macos/CursorAPI/Sources/CursorAPI/CursorAPIApp.swift \
      --replace-fail '        ].compactMap(\.self)' '        ].compactMap { $0 }'
    substituteInPlace macos/CursorAPI/Sources/CursorAPI/AppModel.swift \
      --replace-fail '        DispatchQueue.main.sync {' '        if Thread.isMainThread {' \
      --replace-fail '            self?.settings ?? CursorAPISettings()' '            return MainActor.assumeIsolated { self?.settings ?? CursorAPISettings() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { self?.settings ?? CursorAPISettings() }'
  '';

  dontFixup = true;

  configurePhase = ''
    runHook preConfigure

    pushd macos/CursorAPI
    ${generated.configure}
    swiftpmMakeMutable Sparkle
    ln -s ${sparkleArtifact}/Sparkle.xcframework .build/checkouts/Sparkle/Sparkle.xcframework
    substituteInPlace .build/checkouts/Sparkle/Package.swift \
      --replace-fail '            url: url,' '            path: "Sparkle.xcframework"' \
      --replace-fail '            checksum: checksum' '            // checksum is only used for remote binary targets'
    popd

    cp -R ${nodeModules}/node_modules ./node_modules
    chmod -R u+w ./node_modules

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    root=macos/CursorAPI
    repository=$PWD
    build_dir="$root/.build/release"
    app_name="API for Cursor"
    app_dir="$root/dist/$app_name.app"
    contents_dir="$app_dir/Contents"
    macos_dir="$contents_dir/MacOS"
    frameworks_dir="$contents_dir/Frameworks"
    resources_dir="$contents_dir/Resources"
    icon_source="$root/Sources/CursorAPI/Resources/APIForCursor.png"

    swift build --package-path "$root" -c release

    rm -rf "$app_dir" "$root/dist/CursorAPI.app"
    mkdir -p "$macos_dir" "$frameworks_dir" "$resources_dir"
    cp "$build_dir/CursorAPI" "$macos_dir/$app_name"
    cp -R "$build_dir/Sparkle.framework" "$frameworks_dir/"
    chmod -R u+w "$frameworks_dir/Sparkle.framework"
    if ! otool -l "$macos_dir/$app_name" | grep -q '@executable_path/../Frameworks'; then
      install_name_tool -add_rpath "@executable_path/../Frameworks" "$macos_dir/$app_name"
    fi

    otool -L "$macos_dir/$app_name" \
      | awk '$1 ~ /^\/nix\/store\/.*-swift.*-lib\/lib\/swift\/macosx\/libswift.*\.dylib$/ { print $1 }' \
      | while IFS= read -r swift_dylib; do
        [ -n "$swift_dylib" ] || continue
        dylib_name="$(basename "$swift_dylib")"
        bundled_dylib="$frameworks_dir/$dylib_name"

        cp "$swift_dylib" "$bundled_dylib"
        chmod u+w "$bundled_dylib"
        install_name_tool -id "@rpath/$dylib_name" "$bundled_dylib"
        install_name_tool -change "$swift_dylib" "@rpath/$dylib_name" "$macos_dir/$app_name"
      done

    if [ -d "$build_dir/CursorAPI_CursorAPI.bundle" ]; then
      cp -R "$build_dir/CursorAPI_CursorAPI.bundle" "$resources_dir/"
    fi

    cp "$icon_source" "$resources_dir/APIForCursor.png"
    cp "$repository/scripts/cursor-sdk-local-agent-bridge.mjs" "$resources_dir/cursor-sdk-local-agent-bridge.mjs"
    cp "${nodejs_22}/bin/node" "$resources_dir/node"
    chmod 755 "$resources_dir/node"
    cp -R "$repository/node_modules" "$resources_dir/node_modules"

    sdk_version="$(${nodejs_22}/bin/node -p 'require("./node_modules/@cursor/sdk/package.json").version')"
    cat > "$resources_dir/CursorAPITransportDefaults.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>clientVersion</key>
      <string>sdk-$sdk_version</string>
    </dict>
    </plist>
    PLIST

    png2icns "$resources_dir/APIForCursor.icns" "$icon_source"

    cat > "$contents_dir/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>$app_name</string>
      <key>CFBundleIdentifier</key>
      <string>ai.standardagents.cursorapi</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>$app_name</string>
      <key>CFBundleDisplayName</key>
      <string>$app_name</string>
      <key>CFBundleGetInfoString</key>
      <string>$app_name ${version}</string>
      <key>CFBundleIconFile</key>
      <string>APIForCursor</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>${version}</string>
      <key>CFBundleVersion</key>
      <string>${build}</string>
      <key>LSMinimumSystemVersion</key>
      <string>14.0</string>
      <key>LSApplicationCategoryType</key>
      <string>public.app-category.developer-tools</string>
      <key>NSHighResolutionCapable</key>
      <true/>
      <key>NSHumanReadableCopyright</key>
      <string>Copyright 2026 Standard Agents</string>
      <key>SUFeedURL</key>
      <string>https://api-for-cursor.standardagents.ai/appcast.xml</string>
      <key>SUAutomaticallyUpdate</key>
      <true/>
    </dict>
    </plist>
    PLIST

    while IFS= read -r -d "" path; do
      if file -b "$path" | grep -q 'Mach-O'; then
        case "$(basename "$path")" in
          node)
            /usr/bin/codesign --force --entitlements "$root/BridgeRuntime.entitlements" --sign - "$path" >/dev/null
            ;;
          *)
            /usr/bin/codesign --force --sign - "$path" >/dev/null
            ;;
        esac
      fi
    done < <(find "$resources_dir" -type f -print0)

    while IFS= read -r -d "" path; do
      /usr/bin/codesign --force --sign - "$path" >/dev/null
    done < <(find "$frameworks_dir" -maxdepth 1 -type f -name 'libswift*.dylib' -print0)

    /usr/bin/codesign --force --deep --sign - "$frameworks_dir/Sparkle.framework" >/dev/null
    /usr/bin/codesign --force --sign - "$app_dir" >/dev/null

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R "macos/CursorAPI/dist/API for Cursor.app" "$out/Applications/"
    cat > "$out/bin/api-for-cursor" <<EOF
    #!/bin/sh
    exec /usr/bin/open "$out/Applications/API for Cursor.app" "\$@"
    EOF
    chmod +x "$out/bin/api-for-cursor"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    contents="$out/Applications/API for Cursor.app/Contents"
    test -f "$contents/Info.plist"
    test -d "$contents/MacOS"
    test -x "$contents/MacOS/API for Cursor"
    test -x "$out/bin/api-for-cursor"
    /bin/sh -n "$out/bin/api-for-cursor"
    ${nodejs_22}/bin/node --check "$contents/Resources/cursor-sdk-local-agent-bridge.mjs"
    grep -F -q 'const maxJsonBytes = parseInteger(process.env.CURSOR_SDK_BRIDGE_MAX_JSON_BYTES, ${toString bridgeMaxJsonBytes});' \
      "$contents/Resources/cursor-sdk-local-agent-bridge.mjs"
    grep -F -q 'const body = Buffer.concat(chunks, bodyBytes).toString("utf8");' \
      "$contents/Resources/cursor-sdk-local-agent-bridge.mjs"
    ! otool -L "$contents/MacOS/API for Cursor" | grep -E -q '/nix/store/.*-swift.*-lib/lib/swift/macosx/libswift.*\.dylib'
    otool -L "$contents/MacOS/API for Cursor" \
      | awk '/@rpath\/libswift.*\.dylib/ { print $1 }' \
      | while IFS= read -r swift_dylib_ref; do
      dylib="$(basename "$swift_dylib_ref")"
      test -f "$contents/Frameworks/$dylib"
      /usr/bin/codesign --verify --strict "$contents/Frameworks/$dylib"
    done
    /usr/bin/codesign --verify --deep --strict "$out/Applications/API for Cursor.app"

    runHook postInstallCheck
  '';

  passthru = {
    inherit bridgeMaxJsonBytes;
  };

  meta = {
    description = "Local OpenAI-compatible API server for Cursor models";
    homepage = "https://github.com/standardagents/composer-api";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}

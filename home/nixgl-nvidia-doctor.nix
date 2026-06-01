# Runtime warning for host NVIDIA driver drift against the nixGL pin.
{
  config,
  lib,
  pkgs,
  nixglNvidiaVersion ? null,
  ...
}:

{
  home.activation.warnNixglNvidiaDriver =
    lib.mkIf (pkgs.stdenv.isLinux && nixglNvidiaVersion != null)
      (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
          export NIXGL_NVIDIA_CONFIG_FILE=${./hosts/linux.nix}
          if ! output="$(${pkgs.bash}/bin/bash ${../scripts/nixgl-nvidia-doctor.sh} 2>&1)"; then
            printf '%s\n' \
              'warning: nixGL NVIDIA driver mismatch detected.' \
              "$output" \
              ""
          fi
        ''
      );
}

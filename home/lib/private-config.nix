{ lib }:

let
  asOptionalAttrs =
    location: value:
    if value == null then
      { }
    else if builtins.isAttrs value then
      value
    else
      throw "${location} must be an attribute set or null";

  section =
    location: attrs: name:
    asOptionalAttrs "${location}.${name}" (attrs.${name} or null);

  personalSections = [
    "signal"
    "syncthing"
    "chromium"
    "naps2"
    "tailscale"
    "plezy"
    "immich"
    "printer-exporter"
    "cups-exporter"
    "brother-maintenance-exporter"
    "opencode-exporter"
    "opencode-ingress"
    "unifi-exporter"
  ];
in
{
  # Normalize only the optional structural boundaries understood by this
  # repository. Leaf nulls remain intact rather than being recursively
  # deleted; each consumer defines the meaning of null for its own fields.
  normalize =
    private:
    let
      git = section "private" private "git";
      goto = section "private" private "goto";
      personalRaw = section "private" private "personal";
      personal = personalRaw // lib.genAttrs personalSections (section "private.personal" personalRaw);
      opencode = section "private" private "opencode";
      homeModulesValue = private.homeModules or null;
      homeModules =
        if homeModulesValue == null then
          [ ]
        else if builtins.isList homeModulesValue then
          homeModulesValue
        else
          throw "private.homeModules must be a list or null";
    in
    {
      inherit
        git
        goto
        homeModules
        opencode
        personal
        ;
    };

  # Nix's `or` handles missing attributes, but not explicit nulls. Optional
  # scalar settings use null as "not configured" at this boundary.
  valueOr =
    attrs: name: default:
    let
      value = attrs.${name} or null;
    in
    if value == null then default else value;
}

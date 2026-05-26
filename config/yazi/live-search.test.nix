# Integration tests for the live-search Yazi plugin and its wiring.
{ pkgs }:

pkgs.runCommand "yazi-live-search-test"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.lua
    ];

    plugin = ./plugins/live-search.yazi/main.lua;
    keymap = ./keymap.toml;
    homeFiles = ../../home/files.nix;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    lua -e 'assert(loadfile(os.getenv("plugin")))'
    grep -Fq 'PATH="$HOME/.nix-profile/bin:$PATH";' "$plugin" \
      || fail "live-search should keep Home Manager tools on PATH"
    grep -Fq -- "--with-shell='/bin/sh -c'" "$plugin" \
      || fail "fzf child commands should use POSIX sh, not the login shell"
    grep -Fq '"$FZF_QUERY"' "$plugin" \
      || fail "content search should quote the fzf query for rg reloads"

    lua <<'EOF'
    ya = {
      sync = function(fn)
        return fn
      end,
      notify = function() end,
    }

    local plugin = dofile(os.getenv("plugin"))
    assert(type(plugin.entry) == "function", "entry must be a function")
    assert(type(plugin._test) == "table", "_test table must be exposed")
    assert(
      plugin._test.selected_content_path("src/main.rs:12:3:needle") == "src/main.rs",
      "vimgrep-style result should resolve to the matched file"
    )
    assert(
      plugin._test.selected_content_path("notes/today.md") == "notes/today.md",
      "plain file result should pass through unchanged"
    )
    EOF

    grep -Fq 'on = "s"' "$keymap" || fail "missing s binding"
    grep -Fq 'run = "plugin live-search files"' "$keymap" || fail "missing live-search files binding"
    grep -Fq 'on = "S"' "$keymap" || fail "missing S binding"
    grep -Fq 'run = "plugin live-search content"' "$keymap" || fail "missing live-search content binding"
    grep -Fq '"yazi/plugins/live-search.yazi".source = ../config/yazi/plugins/live-search.yazi;' "$homeFiles" \
      || fail "missing Home Manager live-search plugin wiring"

    echo "all yazi-live-search assertions passed"
    touch "$out"
  ''

# Integration test for home/lib/merge-dirs.nix.
#
# Unlike the other lib helpers, `merge-dirs` returns a derivation that
# produces a directory of symlinks at build time, so its behavior can
# only be observed by realising the derivation and inspecting the
# output. The test below builds three merged directories with
# representative input shapes and asserts on their contents from a
# wrapping `runCommand`. It exits non-zero on the first failed
# assertion (set -e), and exits 0 + writes $out when all assertions
# pass.
#
# Wired into the flake's `checks.${system}.merge-dirs-test` so
# `nix flake check` exercises it.
{ pkgs, lib }:

let
  mergeDirs = import ./merge-dirs.nix { inherit pkgs lib; };

  singleSource = mergeDirs {
    name = "merge-dirs-test-single";
    sources = [ ./merge-dirs.test/public ];
  };

  withCollision = mergeDirs {
    name = "merge-dirs-test-collision";
    sources = [
      ./merge-dirs.test/public
      ./merge-dirs.test/private
    ];
  };

  withMissingSource = mergeDirs {
    name = "merge-dirs-test-missing-source";
    sources = [
      ./merge-dirs.test/public
      /nonexistent/merge-dirs-source
    ];
  };
in
pkgs.runCommand "merge-dirs-test"
  {
    inherit singleSource withCollision withMissingSource;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    # --- Test 1: single source ----------------------------------------
    # Every top-level entry from `public/` should be linked into the
    # output (files and subdirs). Subdir contents must remain reachable
    # via the symlink (no flattening).
    [ -L "$singleSource/a.txt" ]   || fail "single: a.txt symlink missing"
    [ -L "$singleSource/b.txt" ]   || fail "single: b.txt symlink missing"
    [ -L "$singleSource/sub" ]     || fail "single: sub symlink missing"
    [ "$(cat "$singleSource/a.txt")" = "public-a" ]                       || fail "single: a.txt content"
    [ "$(cat "$singleSource/b.txt")" = "public-b" ]                       || fail "single: b.txt content"
    [ "$(cat "$singleSource/sub/c.txt")" = "in-public-subdir" ]           || fail "single: sub/c.txt content"
    [ "$(cat "$singleSource/sub/extra-public-only.txt")" = "extra-public" ] \
        || fail "single: sub/extra-public-only.txt content"

    # --- Test 2: two sources with collision ---------------------------
    # public/ provides a.txt, b.txt, sub/. private/ provides b.txt
    # (collides) and d.txt. Per the contract, private wins on b.txt,
    # public's other entries pass through, and private's d.txt is added.
    [ -L "$withCollision/a.txt" ]  || fail "collision: a.txt missing"
    [ -L "$withCollision/b.txt" ]  || fail "collision: b.txt missing"
    [ -L "$withCollision/d.txt" ]  || fail "collision: d.txt missing"
    [ -L "$withCollision/sub" ]    || fail "collision: sub missing"
    [ "$(cat "$withCollision/a.txt")" = "public-a" ]   || fail "collision: a.txt content"
    [ "$(cat "$withCollision/b.txt")" = "private-b" ]  || fail "collision: b.txt should be overridden by private"
    [ "$(cat "$withCollision/d.txt")" = "private-d" ]  || fail "collision: d.txt content"

    # Subdirectory collision: both public/ and private/ ship `sub/`.
    # `merge-dirs` only operates at top-level via `ln -sfn`, so the
    # later source's `sub/` symlink fully replaces the earlier one —
    # the subdir is NOT recursively merged. Asserts:
    #   - private's c.txt overrides public's
    #   - private's e.txt (only in private) is reachable
    #   - public's `extra-public-only.txt` (inside the colliding sub/)
    #     is NOT visible — proving wholesale replacement.
    [ "$(cat "$withCollision/sub/c.txt")" = "private-c" ] \
        || fail "collision: sub/c.txt should come from private (wholesale replace)"
    [ "$(cat "$withCollision/sub/e.txt")" = "private-only" ] \
        || fail "collision: sub/e.txt should come from private"
    [ ! -e "$withCollision/sub/extra-public-only.txt" ] \
        || fail "collision: public's sub/extra-public-only.txt should be hidden after private's sub/ replaces public's"

    # --- Test 3: non-existent source is silently skipped --------------
    # Tolerates an optional private overlay path that simply does not
    # exist on a given machine.
    [ -L "$withMissingSource/a.txt" ]                            || fail "missing-source: a.txt missing"
    [ "$(cat "$withMissingSource/a.txt")" = "public-a" ]         || fail "missing-source: a.txt content"

    echo "all merge-dirs assertions passed"
    touch "$out"
  ''

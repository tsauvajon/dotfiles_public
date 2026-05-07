# Unit tests for home/lib/deep-merge-json.nix.
#
# Returns an attrset of `lib.runTests`-compatible cases:
#   { expr = <actual>; expected = <expected>; }
# The flake-level checks aggregate this with the other lib tests and
# pass the union to `lib.runTests`. A non-empty list of failures fails
# the check.
{ lib }:

let
  inherit (import ./deep-merge-json.nix { inherit lib; }) deepMerge deepMergeAll;
in
{
  testEmptyMergeEmpty = {
    expr = deepMerge { } { };
    expected = { };
  };

  testDisjointKeysUnion = {
    expr = deepMerge { a = 1; } { b = 2; };
    expected = {
      a = 1;
      b = 2;
    };
  };

  testNumberOverlayWins = {
    expr = deepMerge { x = 1; } { x = 2; };
    expected = {
      x = 2;
    };
  };

  testStringOverlayWins = {
    expr = deepMerge { x = "old"; } { x = "new"; };
    expected = {
      x = "new";
    };
  };

  testBoolOverlayWins = {
    expr = deepMerge { x = true; } { x = false; };
    expected = {
      x = false;
    };
  };

  testNullOverlayWins = {
    expr = deepMerge { x = "value"; } { x = null; };
    expected = {
      x = null;
    };
  };

  testNestedObjectsMerge = {
    expr =
      deepMerge
        {
          a = {
            b = 1;
            c = 2;
          };
        }
        {
          a = {
            b = 99;
            d = 4;
          };
        };
    expected = {
      a = {
        b = 99;
        c = 2;
        d = 4;
      };
    };
  };

  testDeeplyNestedMerge = {
    expr =
      deepMerge
        {
          a.b.c.d = "old";
          a.b.c.e = "kept";
        }
        {
          a.b.c.d = "new";
          a.b.f = "added";
        };
    expected = {
      a = {
        b = {
          c = {
            d = "new";
            e = "kept";
          };
          f = "added";
        };
      };
    };
  };

  testArrayReplaced = {
    # Arrays are replaced wholesale, not concatenated, matching the
    # Rust deep_merge_json semantics referenced in deep-merge-json.nix.
    expr =
      deepMerge
        {
          x = [
            1
            2
            3
          ];
        }
        {
          x = [
            4
            5
          ];
        };
    expected = {
      x = [
        4
        5
      ];
    };
  };

  testObjectOverlaysScalar = {
    # Per the function's contract: when types disagree, overlay wins.
    expr = deepMerge { x = 1; } {
      x = {
        nested = true;
      };
    };
    expected = {
      x = {
        nested = true;
      };
    };
  };

  testScalarOverlaysObject = {
    expr = deepMerge {
      x = {
        nested = true;
      };
    } { x = 42; };
    expected = {
      x = 42;
    };
  };

  testDeepMergeAllEmpty = {
    expr = deepMergeAll [ ];
    expected = { };
  };

  testDeepMergeAllSingleton = {
    expr = deepMergeAll [ { a = 1; } ];
    expected = {
      a = 1;
    };
  };

  testDeepMergeAllPrecedence = {
    # Later list elements win on conflict; earlier-only keys survive.
    expr = deepMergeAll [
      {
        a = 1;
        b = 1;
      }
      {
        a = 2;
        c = 2;
      }
      { a = 3; }
    ];
    expected = {
      a = 3;
      b = 1;
      c = 2;
    };
  };

  testDeepMergeAllNestedPrecedence = {
    # Mirrors the real opencode merge: each tier may set partial keys
    # under `permission.bash`, with later tiers winning on conflict.
    expr = deepMergeAll [
      {
        permission.bash = "ask";
        permission.fs = "allow";
      }
      { permission.bash = "allow"; }
    ];
    expected = {
      permission = {
        bash = "allow";
        fs = "allow";
      };
    };
  };
}

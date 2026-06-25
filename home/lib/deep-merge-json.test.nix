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
  testDisjointKeysUnion = {
    expr = deepMerge { a = 1; } { b = 2; };
    expected = {
      a = 1;
      b = 2;
    };
  };

  testNullOverlayWins = {
    expr = deepMerge { x = "value"; } { x = null; };
    expected = {
      x = null;
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

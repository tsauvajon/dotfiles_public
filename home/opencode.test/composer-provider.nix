# Smoke tests for the real repo-managed API for Cursor OpenCode provider.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  merged = mkMergedOpencodeJson {
    publicRoot = ../../config/opencode;
  };

  provider = merged.provider.cursorapi;
in
{
  testComposerProviderUsesLocalApiForCursor = {
    expr = {
      npm = provider.npm;
      name = provider.name;
      baseURL = provider.options.baseURL;
      apiKey = provider.options.apiKey;
    };
    expected = {
      npm = "@ai-sdk/openai-compatible";
      name = "API for Cursor";
      baseURL = "http://127.0.0.1:8787/v1";
      apiKey = "cursor-local";
    };
  };

  testComposerProviderExposesPrimaryModels = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames provider.models);
    expected = [
      "composer-2.5"
      "composer-2.5-fast"
      "grok-4.5"
      "grok-4.5-fast"
    ];
  };

  testComposerProviderModelMetadataMatchesUpstreamApp = {
    expr = {
      composer = provider.models."composer-2.5";
      fast = provider.models."composer-2.5-fast";
      grok = provider.models."grok-4.5";
      grokFast = provider.models."grok-4.5-fast";
    };
    expected = {
      composer = {
        name = "Composer 2.5";
        cost = {
          input = 0.5;
          output = 2.5;
        };
        limit = {
          context = 200000;
          output = 65536;
        };
      };
      fast = {
        name = "Composer 2.5 Fast";
        cost = {
          input = 3;
          output = 15;
        };
        limit = {
          context = 200000;
          output = 65536;
        };
      };
      grok = {
        name = "Grok 4.5";
        cost = {
          input = 2;
          output = 6;
        };
        limit = {
          context = 200000;
          output = 65536;
        };
      };
      grokFast = {
        name = "Grok 4.5 Fast";
        cost = {
          input = 4;
          output = 18;
        };
        limit = {
          context = 200000;
          output = 65536;
        };
      };
    };
  };
}

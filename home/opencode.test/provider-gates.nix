# Pure tests for provider removal and exact model fallback rewriting.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) applyProviderGates;

  config = {
    model = "cursorapi/composer-2.5";
    small_model = "bifrost/claude-fable-5";
    disabled_providers = [ "legacy" ];
    provider = {
      cursorapi.name = "Cursor";
      bifrost.name = "Bifrost";
      openai.name = "OpenAI";
    };
    agent = {
      cursor = {
        model = "cursorapi/grok-4.5-fast";
        nested.small_model = "cursorapi/composer-2.5-fast";
      };
      bifrostSonnet = {
        model = "bifrost/claude-sonnet-5";
        variant = "xhigh";
      };
      bifrostGpt = {
        model = "bifrost/gpt-5.6-sol";
        variant = "xhigh";
      };
      openai = {
        model = "openai/gpt-5.6-sol";
        variant = "xhigh";
      };
    };
  };

  sonnetFallback = {
    direct = "anthropic/claude-sonnet-4-6";
    variantFallbacks.xhigh = "high";
  };

  gates = {
    cursorapi = {
      enable = true;
      modelFallbacks = {
        "composer-2.5".direct = "anthropic/claude-sonnet-4-6";
        "composer-2.5-fast".direct = "anthropic/claude-sonnet-4-6";
        "grok-4.5-fast".direct = "anthropic/claude-sonnet-4-6";
      };
    };
    bifrost = {
      enable = true;
      modelFallbacks = {
        "gpt-5.6-sol".direct = "openai/gpt-5.6-sol";
        "claude-fable-5" = sonnetFallback;
        "claude-sonnet-5" = sonnetFallback;
      };
    };
  };

  apply = providerGates: applyProviderGates { inherit config providerGates; };
  cursorDisabled = apply (
    gates
    // {
      cursorapi = gates.cursorapi // {
        enable = false;
      };
    }
  );
  bifrostDisabled = apply (
    gates
    // {
      bifrost = gates.bifrost // {
        enable = false;
      };
    }
  );
  bothDisabled = apply {
    cursorapi = gates.cursorapi // {
      enable = false;
    };
    bifrost = gates.bifrost // {
      enable = false;
    };
  };
  missingFallback = builtins.tryEval (
    builtins.deepSeq (applyProviderGates {
      config.model = "bifrost/unmapped-model";
      providerGates.bifrost = {
        enable = false;
        modelFallbacks = { };
      };
    }) "ok"
  );
in
{
  testEnabledProviderGatesLeaveConfigUnchanged = {
    expr = apply gates;
    expected = config;
  };

  testCursorDisabledRemovesProviderAndRewritesRecursively = {
    expr = {
      hasCursorProvider = cursorDisabled.provider ? cursorapi;
      keepsBifrostProvider = cursorDisabled.provider ? bifrost;
      rootModel = cursorDisabled.model;
      nestedModel = cursorDisabled.agent.cursor.model;
      nestedSmallModel = cursorDisabled.agent.cursor.nested.small_model;
    };
    expected = {
      hasCursorProvider = false;
      keepsBifrostProvider = true;
      rootModel = "anthropic/claude-sonnet-4-6";
      nestedModel = "anthropic/claude-sonnet-4-6";
      nestedSmallModel = "anthropic/claude-sonnet-4-6";
    };
  };

  testBifrostDisabledRewritesModelsAndOnlyMappedVariants = {
    expr = {
      hasBifrostProvider = bifrostDisabled.provider ? bifrost;
      rootSmallModel = bifrostDisabled.small_model;
      sonnet = bifrostDisabled.agent.bifrostSonnet;
      bifrostGpt = bifrostDisabled.agent.bifrostGpt;
      openai = bifrostDisabled.agent.openai;
    };
    expected = {
      hasBifrostProvider = false;
      rootSmallModel = "anthropic/claude-sonnet-4-6";
      sonnet = {
        model = "anthropic/claude-sonnet-4-6";
        variant = "high";
      };
      bifrostGpt = {
        model = "openai/gpt-5.6-sol";
        variant = "xhigh";
      };
      openai = {
        model = "openai/gpt-5.6-sol";
        variant = "xhigh";
      };
    };
  };

  testBothDisabledPreservesExistingDisabledProviders = {
    expr = bothDisabled.disabled_providers;
    expected = [
      "legacy"
      "bifrost"
      "cursorapi"
    ];
  };

  testBothDisabledRemovesBothProviders = {
    expr = {
      hasBifrost = bothDisabled.provider ? bifrost;
      hasCursor = bothDisabled.provider ? cursorapi;
      keepsOpenai = bothDisabled.provider ? openai;
      rootModel = bothDisabled.model;
      rootSmallModel = bothDisabled.small_model;
      sonnetVariant = bothDisabled.agent.bifrostSonnet.variant;
    };
    expected = {
      hasBifrost = false;
      hasCursor = false;
      keepsOpenai = true;
      rootModel = "anthropic/claude-sonnet-4-6";
      rootSmallModel = "anthropic/claude-sonnet-4-6";
      sonnetVariant = "high";
    };
  };

  testDisabledProviderWithoutFallbackFails = {
    expr = missingFallback.success;
    expected = false;
  };
}

# Pure tests for provider removal and exact model fallback rewriting.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) applyProviderGates;

  config = {
    model = "localproxy/model-a";
    small_model = "bifrost/claude-fable-5";
    disabled_providers = [ "legacy" ];
    provider = {
      localproxy.name = "Local Proxy";
      bifrost.name = "Bifrost";
      openai.name = "OpenAI";
    };
    agent = {
      local = {
        model = "localproxy/model-c";
        nested.small_model = "localproxy/model-b";
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
    localproxy = {
      enable = true;
      modelFallbacks = {
        model-a.direct = "anthropic/claude-sonnet-4-6";
        model-b.direct = "anthropic/claude-sonnet-4-6";
        model-c.direct = "anthropic/claude-sonnet-4-6";
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
  localProxyDisabled = apply (
    gates
    // {
      localproxy = gates.localproxy // {
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
    localproxy = gates.localproxy // {
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

  testLocalProxyDisabledRemovesProviderAndRewritesRecursively = {
    expr = {
      hasLocalProxyProvider = localProxyDisabled.provider ? localproxy;
      keepsBifrostProvider = localProxyDisabled.provider ? bifrost;
      rootModel = localProxyDisabled.model;
      nestedModel = localProxyDisabled.agent.local.model;
      nestedSmallModel = localProxyDisabled.agent.local.nested.small_model;
    };
    expected = {
      hasLocalProxyProvider = false;
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
      "localproxy"
    ];
  };

  testBothDisabledRemovesBothProviders = {
    expr = {
      hasBifrost = bothDisabled.provider ? bifrost;
      hasLocalProxy = bothDisabled.provider ? localproxy;
      keepsOpenai = bothDisabled.provider ? openai;
      rootModel = bothDisabled.model;
      rootSmallModel = bothDisabled.small_model;
      sonnetVariant = bothDisabled.agent.bifrostSonnet.variant;
    };
    expected = {
      hasBifrost = false;
      hasLocalProxy = false;
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

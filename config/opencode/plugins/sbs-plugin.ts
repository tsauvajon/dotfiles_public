import type { Plugin } from "@opencode-ai/plugin"

export const SbsPlugin: Plugin = async ({ client, $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        try {
          await $`sbs index`.quiet()
          await client.app.log({
            body: {
              service: "sbs-plugin",
              level: "info",
              message: "Vault reindexed on session start",
            },
          })
        } catch {
          // sbs CLI not installed or not in PATH - skip silently
        }
      }
    },
  }
}

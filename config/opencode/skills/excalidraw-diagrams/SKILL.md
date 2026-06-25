---
name: excalidraw-diagrams
description: Use when creating or editing Obsidian Excalidraw diagrams, `.excalidraw` files, `.excalidraw.md` files, compressed-json drawing blocks, or programmatically generated Excalidraw scenes.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.0"
---

# Excalidraw Diagrams

Use this skill when creating or editing Obsidian Excalidraw diagrams, especially when writing the file directly instead of using the Obsidian plugin UI.

## First Steps

- Read the current diagram file before editing it.
- Check whether the file is raw `.excalidraw` JSON or Obsidian plugin Markdown (`*.excalidraw.md`).
- For `*.excalidraw.md`, edit the drawing payload, not only the Markdown summary sections.
- Preserve the existing wrapper style unless there is a concrete reason to migrate it.
- Validate by decompressing/parsing the drawing block after every generated edit.

## Obsidian Wrapper Shape

The safest wrapper for Obsidian Excalidraw plugin 2.x in a compression-enabled vault is:

````md
---
title: Example
tags:
  - excalidraw
excalidraw-plugin: parsed
---

==Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document.== You can decompress Drawing data with the command palette: 'Decompress current Excalidraw file'. For more info check in plugin settings under 'Saving'

# Excalidraw Data

## Text Elements
Text in the drawing ^elementId

## Embedded Files

%%
## Drawing
```compressed-json
...
```
%%
````

Important details:

- If `# Excalidraw Data` is present, include `## Text Elements` before `## Drawing`.
- Missing `## Text Elements` can make the plugin fail with `Cannot read properties of null (reading '0')`.
- When generating files by hand, prefer leaving `## Text Elements` empty unless you have verified the plugin will parse the mirror correctly. Bad mirrors can leak `^elementId` anchors into the rendered canvas.
- `## Embedded Files` may be empty, but keeping it mirrors plugin-saved files.
- Put the drawing section behind `%%` so the large payload is hidden in Markdown view.
- The highlighted warning line is informational; the plugin does not parse it, and exact wording is less important than the drawing sections.
- Prefer `compressed-json` when the vault setting has compression enabled.
- Plain `json` drawing blocks are recognized by the plugin, but they are less reliable in a vault where all normal saved files use `compressed-json`.

## Scene Payload

A valid scene payload should include the normal Excalidraw fields:

- `type: "excalidraw"`
- `version`
- `source`
- `elements`
- `appState`
- `files`

When generating or modifying elements:

- Use stable unique IDs for new elements.
- Use `boundElements: []`, not `boundElements: null`.
- Preserve `index` ordering conventions when possible.
- Keep `fontFamily` consistent with the diagram. In many Obsidian diagrams, `2` is Helvetica and avoids the handwritten look.
- For text boxes, set width/height generously enough that labels do not wrap unexpectedly.
- After changing `elements`, either leave `## Text Elements` empty or let the plugin regenerate it. Do not hand-write a full mirror if the drawing is primarily meant to render cleanly.

## Compression

`compressed-json` is LZ-string Base64 data containing the scene JSON.

Guidelines:

- Prefer a known-good LZ-string implementation over ad-hoc compression code.
- Round-trip check the exact file contents: extract the `compressed-json` block, decompress it, parse JSON, then inspect the changed elements.
- Do not trust a successful JSON parse alone if the compressor was hand-written; compare key changed element text and counts.

## Common Failure Modes

- Error: `Cannot read properties of null (reading '0')`.
- Likely cause: `# Excalidraw Data` exists but `## Text Elements` is missing before `## Drawing`.
- Fix: rebuild the Markdown wrapper to include `## Text Elements`, optional `## Embedded Files`, and a hidden `compressed-json` drawing block.

- Error: drawing loads but labels look wrong.
- Likely cause: text dimensions, font family, or stale Markdown text summary do not match scene elements.
- Fix: inspect text elements after decompression and update text boxes in the scene payload.

- Error: Obsidian still shows the old loading error after a file fix.
- Likely cause: the pane cached the failed parse.
- Fix: close/reopen the pane or reload Obsidian before continuing to edit.

- Error: `^elementId` anchors or duplicated text appear on the canvas.
- Likely cause: a hand-written `## Text Elements` mirror was parsed or synced incorrectly.
- Fix: keep the `## Text Elements` header but empty the section, then validate that all intended text is present in the scene JSON itself.

## Verification Checklist

Before saying the diagram is fixed:

- Confirm there is exactly one drawing block.
- Decompress or parse the drawing block successfully.
- Confirm `scene.type === "excalidraw"`.
- Confirm expected element count and changed text are present.
- Confirm no generated element has `boundElements: null`.
- Confirm `## Text Elements` exists if the file has `# Excalidraw Data`.
- Re-read the file header and wrapper after writing it.

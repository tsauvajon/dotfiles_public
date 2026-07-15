---
name: excalidraw-diagrams
description: Create or edit Obsidian Excalidraw diagrams. Use for .excalidraw, .excalidraw.md, or generated Excalidraw scenes.
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
- Re-read the file immediately before each edit pass. If Obsidian has the diagram open, the plugin may have resaved and changed element IDs or regenerated `## Text Elements`.
- Prefer semantic lookup over stored IDs when editing an existing scene. Find text by normalized `text` content and arrows by their bindings, direction, or nearby labels. Do not assume IDs from a previous read, a `## Text Elements` mirror, or an earlier edit pass still exist.
- Ask the user to close the Excalidraw pane before programmatic writes when repeated edits keep disappearing or IDs churn. An open pane can write stale in-memory canvas state back to disk.

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

### Text Elements

- Treat plugin-generated text element IDs as ephemeral after Obsidian opens or saves the diagram. The `## Text Elements` `^id` suffixes are mirrors, not a stable edit API.
- Size text elements and parent boxes together. Estimate text width from character count and `fontSize`, then add 20-40% padding; JSON parsing will not catch mid-word wrapping or clipped labels.
- Keep `fontSize`, `fontFamily`, and `textAlign` consistent across peer labels in the same card, lane, or connector group.

### Arrows And Bound Labels

- Connector labels should be arrow-bound, not free-floating text near a line. Set the label text element's `containerId` to the arrow ID, set the arrow's `boundElements` to include that text ID, and keep the label's `boundElements: []`.
- When replacing an arrow, also recreate or rebind its label. Remove stale labels that still reference the old arrow `containerId`.
- For flow diagrams, prefer crisp straight or orthogonal connectors: `roughness: 0`, `roundness: null`, and explicit points. Use curves only when they intentionally communicate looping or feedback.
- Terminate arrows at box boundaries or semantic target cards. Avoid routing arrows through cards or over text; crossing parent lane backgrounds is usually fine, crossing content cards is usually not.

### Layout Discipline

- Use one semantic arrow per relationship. Duplicate arrows between the same nodes quickly become visual noise unless they are deliberately parallel and well separated.
- Leave at least 40-60px of gutter between parallel connectors, connector labels, and box edges.
- Resize parent rectangles before nudging child text or labels. Changing a box without updating its contained text dimensions is a common cause of clipped or overlapping labels.

## Programmatic Edit Loop

For non-trivial generated diagrams, expect a separate content pass and layout pass:

- Decompress the drawing block and build a semantic index from the fresh scene.
- Edit scene JSON using IDs only within that one pass.
- Recompress and write the wrapper, keeping `## Text Elements` empty unless you intentionally let Obsidian regenerate it.
- Run structural checks on the decompressed payload.
- Re-read from disk and rebuild the semantic index before another edit.
- If Obsidian was open during the edit, treat the next disk read as the source of truth and discard old ID maps.
- Ask for or inspect a visual pass when possible; structural validation cannot prove that text fits or arrows are readable.

## Compression

`compressed-json` is LZ-string Base64 data containing the scene JSON.

Guidelines:

- Prefer a known-good LZ-string implementation over ad-hoc compression code.
- Round-trip check the exact file contents: extract the `compressed-json` block, decompress it, parse JSON, then inspect the changed elements.
- Do not trust a successful JSON parse alone if the compressor was hand-written; compare key changed element text and counts.
- Add structural sanity checks after parse: every `containerId` references an existing element, every arrow-bound text ID exists, no generated element has `boundElements: null`, and expected key labels still exist.

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

- Error: agent edits disappear or expected element IDs are missing.
- Likely cause: Obsidian resaved the open Excalidraw pane and regenerated elements or the Markdown mirror.
- Fix: close the pane, re-read the file, rebuild a semantic index, and retry without relying on IDs from previous reads.

- Error: connector labels float away from arrows or overlap boxes.
- Likely cause: labels are free-positioned text, or an arrow was replaced without rebinding its label.
- Fix: bind labels through `containerId` and arrow `boundElements`, then delete stale orphan labels.

- Error: diagram parses but arrows look tangled or wavy.
- Likely cause: default rounded/rough connectors, duplicate relationship arrows, or arrows routed through content cards.
- Fix: use straight/orthogonal connectors, dedupe arrows, terminate at card boundaries, and add gutter space.

- Error: text wraps or clips inside a box after opening in Obsidian.
- Likely cause: the text element and parent rectangle are too small for the rendered font.
- Fix: widen the box and text element together, lower `fontSize` if needed, and verify line counts against height.

## Verification Checklist

Before saying the diagram is fixed:

- Confirm there is exactly one drawing block.
- Decompress or parse the drawing block successfully.
- Confirm `scene.type === "excalidraw"`.
- Confirm expected element count and changed text are present.
- Confirm no generated element has `boundElements: null`.
- Confirm `## Text Elements` exists if the file has `# Excalidraw Data`.
- Re-read the file header and wrapper after writing it.
- Confirm every arrow with a visible label has a text element whose `containerId` points at that arrow, and the arrow's `boundElements` points back to that text element.
- Confirm no stale label references a missing arrow `containerId`.
- Confirm key multi-line text elements have enough height for `lineCount × fontSize × lineHeight`.
- Confirm parallel connectors have enough visual spacing and labels are not sitting on top of boxes or other arrows.
- After an Obsidian/plugin save, discard old ID maps and verify using a fresh decompressed scene.
